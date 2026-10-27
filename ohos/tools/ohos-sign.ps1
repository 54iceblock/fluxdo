# 一键签名 OHOS HAP（OpenHarmony 官方默认证书链 + 按 bundleName 生成 debug provisioning profile）
# 用法: .\ohos-sign.ps1 -BundleName com.fluxdo.app -InHap <unsigned.hap> -OutHap <signed.hap> [-Udid <udid>]
#
# 说明：
# - 无需华为账号 / DevEco Studio GUI，纯命令行完成，产物可安装到模拟器与已注册 UDID 的真机。
# - ⚠ 本文件必须保存为 “UTF-8 with BOM”。Windows PowerShell 5.1 会把无 BOM 的 UTF-8 当 GBK 解析，
#   中文注释后的换行可能被吞掉，导致后续赋值语句被当成注释（本脚本曾因此报 $tplRaw 为 null）。
# - hap-sign-tool 不会覆盖已存在的输出文件，必须先删旧产物；本脚本已自动清理。
param(
  [Parameter(Mandatory = $true)][string]$BundleName,
  [Parameter(Mandatory = $true)][string]$InHap,
  [Parameter(Mandatory = $true)][string]$OutHap,
  [string]$Udid = '',
  # 指定从哪台设备读取 UDID（真机测试时传设备序列号；留空则取默认/首个设备）
  [string]$Device = ''
)

# 签名口令：OpenHarmony 官方 SDK 自带密钥库的口令是公开值 123456（只用于调试证书链），
# 因此这里保留为兜底；一旦换成正式证书，务必用环境变量传入真实口令，不要写回脚本：
#   $env:FLUXDO_SIGN_PWD = '<正式密钥库口令>'
$signPwd = if ($env:FLUXDO_SIGN_PWD) { $env:FLUXDO_SIGN_PWD } else { '123456' }

$ErrorActionPreference = 'Continue'
$WS = 'C:\Users\iceblock\fluxdo'
$lib = 'C:\Users\iceblock\DevEcoStudio\sdk\default\openharmony\toolchains\lib'
$java = 'C:\Users\iceblock\DevEcoStudio\jbr\bin\java.exe'
$keytool = 'C:\Users\iceblock\DevEcoStudio\jbr\bin\keytool.exe'
$hapSignTool = Join-Path $lib 'hap-sign-tool.jar'
$p12 = Join-Path $lib 'OpenHarmony.p12'
$w = Join-Path $WS '.cache\signing'
New-Item -ItemType Directory -Force -Path $w | Out-Null

function Write-Step([string]$msg) { Write-Host "[ohos-sign] $msg" -ForegroundColor Cyan }

if (-not (Test-Path -LiteralPath $InHap)) { throw "InHap 不存在: $InHap" }
foreach ($need in @($java, $keytool, $hapSignTool, $p12)) {
  if (-not (Test-Path -LiteralPath $need)) { throw "缺少签名依赖: $need" }
}

# 0) 取设备 UDID（用于 profile 的调试设备白名单；模拟器也能取到）
if (-not $Udid) {
  $hdc = 'C:\Users\iceblock\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe'
  $hdcArgs = @('shell', 'bm', 'get', '-u')
  if ($Device) { $hdcArgs = @('-t', $Device) + $hdcArgs }
  $out = & $hdc @hdcArgs 2>&1 | Out-String
  $m = [regex]::Match($out, '([0-9A-Fa-f]{40,})')
  if ($m.Success) { $Udid = $m.Groups[1].Value }
  else { $Udid = '454D55057494E058383609D94A75277F44F029C4E9A784E7E4F9600000000000' }
}
Write-Step "bundle=$BundleName udid=$Udid"

# 1) 应用叶子证书 + CA + Root（缺失时从 SDK 的 OpenHarmony.p12 导出）
$caPem = Join-Path $w 'app-ca.pem'
$rootPem = Join-Path $w 'app-root.pem'
if (-not (Test-Path -LiteralPath $caPem) -or -not (Test-Path -LiteralPath $rootPem)) {
  Write-Step '导出 OpenHarmony 证书链（首次运行）'
  $exports = @(
    @{ alias = 'openharmony application ca';      file = 'app-ca.pem' },
    @{ alias = 'openharmony application root ca'; file = 'app-root.pem' },
    @{ alias = 'openharmony application release'; file = 'app-release.pem' }
  )
  foreach ($e in $exports) {
    $f = Join-Path $w $e.file
    if (Test-Path -LiteralPath $f) { continue }
    & $keytool -exportcert -rfc -alias $e.alias -keystore $p12 -storepass $signPwd -storetype PKCS12 -file $f 2>&1 | Out-Null
    if (-not (Test-Path -LiteralPath $f)) { throw "导出证书失败: $($e.alias)" }
  }
}

# 2) 用 SDK 内的 debug profile 模板生成 profile JSON（模板内嵌官方 leaf 证书）
$tplRaw = Get-Content -LiteralPath (Join-Path $lib 'UnsgnedDebugProfileTemplate.json') -Raw
$tpl = $tplRaw | ConvertFrom-Json
$devCert = $tpl.'bundle-info'.'development-certificate'
if (-not $devCert) { throw '模板中缺少 development-certificate' }
$devCertPem = ($devCert -replace "`n", "`r`n")
$chainPem = $devCertPem + (Get-Content -LiteralPath $caPem -Raw) + (Get-Content -LiteralPath $rootPem -Raw)
[IO.File]::WriteAllText((Join-Path $w 'tpl-chain.pem'), $chainPem)

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$tpl.'bundle-info'.'bundle-name' = $BundleName
$tpl.'debug-info'.'device-ids' = @($Udid)
$tpl.'uuid' = [guid]::NewGuid().ToString()
$tpl.validity.'not-before' = $now - 86400
$tpl.validity.'not-after' = $now + 315360000
$profileJson = Join-Path $w 'profile-tpl.json'
($tpl | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $profileJson -Encoding utf8

# 3) 签 profile -> p7b（先删旧文件：hap-sign-tool 拒绝覆盖已有输出）
$p7b = Join-Path $w 'profile-tpl.p7b'
if (Test-Path -LiteralPath $p7b) { Remove-Item -LiteralPath $p7b -Force }
Write-Step 'sign-profile ...'
$profileLog = & $java -jar $hapSignTool sign-profile -mode localSign `
  -keyAlias 'openharmony application profile debug' -keyPwd $signPwd `
  -profileCertFile (Join-Path $lib 'OpenHarmonyProfileDebug.pem') `
  -inFile $profileJson -signAlg SHA256withECDSA `
  -keystoreFile $p12 -keystorePwd $signPwd -outFile $p7b 2>&1 | Out-String
$profileLog | Set-Content -LiteralPath (Join-Path $w 'sign-profile.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $p7b)) {
  Write-Host $profileLog
  throw "sign-profile 失败（exit=$LASTEXITCODE）"
}

# 4) 签 HAP（同样先删旧产物）
if (Test-Path -LiteralPath $OutHap) { Remove-Item -LiteralPath $OutHap -Force }
$outDir = [IO.Path]::GetDirectoryName($OutHap)
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
Write-Step 'sign-app ...'
$appLog = & $java -jar $hapSignTool sign-app -mode localSign `
  -keyAlias 'openharmony application release' -keyPwd $signPwd `
  -appCertFile (Join-Path $w 'tpl-chain.pem') -profileFile $p7b `
  -inFile $InHap -signAlg SHA256withECDSA `
  -keystoreFile $p12 -keystorePwd $signPwd -outFile $OutHap 2>&1 | Out-String
$appLog | Set-Content -LiteralPath (Join-Path $w 'sign-app.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutHap)) {
  Write-Host $appLog
  throw "sign-app 失败（exit=$LASTEXITCODE）"
}

Write-Host "SIGNED: $OutHap ($((Get-Item -LiteralPath $OutHap).Length) bytes) bundle=$BundleName udid=$Udid" -ForegroundColor Green
