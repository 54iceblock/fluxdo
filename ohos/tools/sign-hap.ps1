# 使用 OpenHarmony SDK 自带默认证书链，为 HAP 生成调试签名（无需华为账号/DevEco GUI）
# 用法: .\sign-hap.ps1 -BundleName com.fluxdo.app -InHap <unsigned.hap> -OutHap <signed.hap>
param(
  [Parameter(Mandatory = $true)][string]$BundleName,
  [Parameter(Mandatory = $true)][string]$InHap,
  [Parameter(Mandatory = $true)][string]$OutHap,
  [string]$Udid = '454D55057494E058383609D94A75277F44F029C4E9A784E7E4F9600000000000',
  [string]$WorkDir = 'C:\Users\iceblock\fluxdo\.cache\signing'
)

$ErrorActionPreference = 'Stop'
$lib = 'C:\Users\iceblock\DevEcoStudio\sdk\default\openharmony\toolchains\lib'
$java = 'C:\Users\iceblock\DevEcoStudio\jbr\bin\java.exe'
$keytool = 'C:\Users\iceblock\DevEcoStudio\jbr\bin\keytool.exe'
$tool = Join-Path $lib 'hap-sign-tool.jar'
$p12 = Join-Path $lib 'OpenHarmony.p12'
$profilePem = Join-Path $lib 'OpenHarmonyProfileDebug.pem'
$template = Join-Path $lib 'UnsgnedDebugProfileTemplate.json'
# 口令：SDK 自带调试密钥库的公开口令 123456 作为兜底；换正式证书后改用环境变量：
#   $env:FLUXDO_SIGN_PWD = '<正式密钥库口令>'
$pwd = if ($env:FLUXDO_SIGN_PWD) { $env:FLUXDO_SIGN_PWD } else { '123456' }

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# 1) 导出应用签名证书链（叶子 -> 中间 -> 根）
$aliases = @(
  @{ alias = 'openharmony application release'; file = 'app-release.pem' },
  @{ alias = 'openharmony application ca';      file = 'app-ca.pem' },
  @{ alias = 'openharmony application root ca'; file = 'app-root.pem' }
)
foreach ($a in $aliases) {
  $f = Join-Path $WorkDir $a.file
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $keytool -exportcert -rfc -alias $a.alias -keystore $p12 -storepass $pwd -storetype PKCS12 -file $f 2>&1 | Out-Null
  $ErrorActionPreference = $old
  if (-not (Test-Path $f)) { throw "export cert failed: $($a.alias)" }
}
$appChain = Join-Path $WorkDir 'app-cert-chain.pem'
$leafPem = Get-Content (Join-Path $WorkDir 'app-release.pem') -Raw
@($leafPem, (Get-Content (Join-Path $WorkDir 'app-ca.pem') -Raw), (Get-Content (Join-Path $WorkDir 'app-root.pem') -Raw)) | Set-Content -Path $appChain -Encoding ascii

# 2) 生成 provisioning profile JSON
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$profile = [ordered]@{
  'version-name' = '2.0.0'
  'version-code' = 2
  'uuid' = [guid]::NewGuid().ToString()
  'validity' = [ordered]@{ 'not-before' = $now - 86400; 'not-after' = $now + 315360000 }
  'type' = 'debug'
  'bundle-info' = [ordered]@{
    'developer-id' = 'OpenHarmony'
    'development-certificate' = $leafPem
    'bundle-name' = $BundleName
    'apl' = 'normal'
    'app-feature' = 'hos_normal_app'
  }
  'acls' = @{ 'allowed-acls' = @('') }
  'permissions' = @{ 'restricted-permissions' = @('') }
  'debug-info' = @{ 'device-ids' = @($Udid); 'device-id-type' = 'udid' }
  'issuer' = 'pki_internal'
}
$profileJson = Join-Path $WorkDir 'profile.json'
$profile | ConvertTo-Json -Depth 10 | Set-Content -Path $profileJson -Encoding utf8

# 3) 签名 profile -> p7b
$p7b = Join-Path $WorkDir 'profile.p7b'
& $java -jar $tool sign-profile -mode localSign -keyAlias 'openharmony application profile debug' `
  -keyPwd $pwd -profileCertFile $profilePem -inFile $profileJson -signAlg SHA256withECDSA `
  -keystoreFile $p12 -keystorePwd $pwd -outFile $p7b 2>&1 | ForEach-Object { if ($_ -match 'ERROR') { throw $_ } }
if (-not (Test-Path $p7b)) { throw 'sign-profile failed: no p7b produced' }

# 4) 签名 HAP
& $java -jar $tool sign-app -mode localSign -keyAlias 'openharmony application release' `
  -keyPwd $pwd -appCertFile $appChain -profileFile $p7b -inFile $InHap -signAlg SHA256withECDSA `
  -keystoreFile $p12 -keystorePwd $pwd -outFile $OutHap 2>&1 | ForEach-Object { if ($_ -match 'ERROR') { throw $_ } }
if (-not (Test-Path $OutHap)) { throw 'sign-app failed: no signed hap produced' }
Write-Host "SIGNED OK: $OutHap"
