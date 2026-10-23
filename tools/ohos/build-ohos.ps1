# =============================================================================
# build-ohos.ps1 —— FluxDO HarmonyOS 7 HAP 一键构建 / 签名 / 安装脚本
#
# 封装链路（与 scratch\hello 已验证的链路一致）：
#   env.ps1 → flutter build hap（内部调用 hvigorw assembleHap）
#           → 从 entry\build\<flavor>\outputs\<flavor> 找 *-unsigned.hap
#           → tools\ohos\ohos-sign.ps1 手工签名（DevEco 默认证书链，无需华为账号）
#           → 可选 hdc install / aa start
#
# 用法：
#   .\tools\ohos\build-ohos.ps1                          # debug + ohos-x64，构建并签名
#   .\tools\ohos\build-ohos.ps1 -Install -Launch         # 构建 + 签名 + 装到模拟器并启动
#   .\tools\ohos\build-ohos.ps1 -Mode release -Arch ohos-arm64
#   .\tools\ohos\build-ohos.ps1 -NoSign                  # 只构建，输出 unsigned hap
#   .\tools\ohos\build-ohos.ps1 -PubGet                  # 先 flutter pub get 再构建（改过 pubspec 后用）
#   .\tools\ohos\build-ohos.ps1 -NoCodesign              # 传 --no-codesign，跳过 flutter 的签名检查（exit 0）
#
# 关键坑（详见 docs/ohos/build.md）：
#   1) 本文件必须 UTF-8 with BOM，否则 Windows PowerShell 5.1 按 GBK 解析中文注释，可能吞换行。
#   2) ohos\build-profile.json5 的 signingConfigs 必须为空数组（hvigor 不接受明文签名密码），
#      因此 flutter build hap 在 hvigor 成功后会打印“请通过DevEco Studio…配置调试签名”并 exit 1，
#      但 unsigned hap 已生成 —— 本脚本按“exit code 1 但找到 unsigned hap”容错。
#   3) 需要 tools\ohos\env.ps1 里的 NODE_OPTIONS（junction 降级）、PUB_CACHE、HOME 等环境变量。
# =============================================================================
param(
  [ValidateSet('debug', 'profile', 'release')][string]$Mode = 'debug',
  [ValidateSet('ohos-x64', 'ohos-arm64', 'ohos-arm')][string]$Arch = 'ohos-x64',
  [string]$Flavor = 'default',
  [string]$BundleName = 'com.fluxdo.app',
  [string]$RepoRoot = '',
  [string]$OutHap = '',
  # 默认模拟器；真机测试传 `-Device auto`（自动取第一个已连接设备）或具体序列号
  [string]$Device = '127.0.0.1:5555',
  # 签名 profile 的调试设备白名单 UDID；留空则由 ohos-sign.ps1 从已连接设备读取
  [string]$Udid = '',
  [switch]$NoSign,
  [switch]$NoCodesign,
  [switch]$PubGet,
  [switch]$SkipBuild,
  [switch]$Install,
  [switch]$Launch
)

# ---------- 设备解析：-Device auto / 模拟器不在线时自动回退到已连接设备 ----------
function Resolve-HdcTarget([string]$preferred) {
  $hdcExe = Join-Path $env:TOOL_HOME 'sdk\default\openharmony\toolchains\hdc.exe'
  if (-not (Test-Path -LiteralPath $hdcExe)) { $hdcExe = 'hdc' }
  $targets = @(& $hdcExe list targets 2>&1 | ForEach-Object { $_.ToString().Trim() } |
    Where-Object { $_ -and $_ -notmatch '^\[' })
  if ($preferred -eq 'auto') {
    if ($targets.Count -gt 0) { return $targets[0] }
    return '127.0.0.1:5555'
  }
  if ($targets -contains $preferred) { return $preferred }
  if ($targets.Count -gt 0) {
    Write-Host "[build-ohos] 目标设备 $preferred 不在线，改用已连接设备 $($targets[0])" -ForegroundColor Yellow
    return $targets[0]
  }
  return $preferred
}

$Device = Resolve-HdcTarget $Device

$ErrorActionPreference = 'Continue'
$RepoRoot = if ($RepoRoot) { $RepoRoot } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$WS = if ($env:FLUXDO_WS) { $env:FLUXDO_WS } else { Split-Path $RepoRoot -Parent }
$envScript = Join-Path $WS 'tools\ohos\env.ps1'
$signScript = Join-Path $WS 'tools\ohos\ohos-sign.ps1'
$logDir = Join-Path $WS '.cache\ohos-build\logs'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $logDir "build-$Mode-$Arch-$stamp.log"

function Write-Step([string]$msg) { Write-Host "`n[build-ohos] $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg) { Write-Host "[build-ohos] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "[build-ohos] $msg" -ForegroundColor Yellow }

# ---------- 0) 环境 ----------
if (-not (Test-Path -LiteralPath $envScript)) { throw "缺少环境脚本: $envScript" }
. $envScript
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { throw "找不到 flutter: $flutter（检查 env.ps1 的 FLUTTER_ROOT）" }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'ohos'))) { throw "仓库里没有 ohos 工程: $RepoRoot\ohos" }
if (-not $OutHap) { $OutHap = Join-Path $WS ".cache\ohos-build\fluxdo-$Mode-$Arch-signed.hap" }

Write-Step "Mode=$Mode Arch=$Arch Flavor=$Flavor Repo=$RepoRoot"
Write-Host "  日志: $log"

# ---------- 1) 可选 flutter pub get ----------
if ($PubGet) {
  Write-Step 'flutter pub get ...'
  Push-Location -LiteralPath $RepoRoot
  try {
    & $flutter pub get 2>&1 | Tee-Object -FilePath $log -Append | Out-Host
  } finally {
    Pop-Location
  }
}

# ---------- 2) flutter build hap ----------
$buildExit = 0
if ($SkipBuild) {
  Write-Step '跳过 flutter build（-SkipBuild），直接对已有产物签名/安装'
} else {
  $flutterArgs = @('build', 'hap', "--$Mode", '--target-platform', $Arch)
  if ($NoCodesign) { $flutterArgs += '--no-codesign' }
  Write-Step "flutter $($flutterArgs -join ' ')（工作目录: $RepoRoot）"

  Push-Location -LiteralPath $RepoRoot
  try {
    & $flutter @flutterArgs *>&1 | Tee-Object -FilePath $log -Append | Out-Host
    $buildExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  Write-Step "flutter build 退出码: $buildExit（日志 $log）"
}

# ---------- 3) 定位 HAP（容错：exit 1 + unsigned hap 也算成功） ----------
$outDir = Join-Path $RepoRoot "ohos\entry\build\$Flavor\outputs\$Flavor"
$unsigned = $null
$signedFromHvigor = $null
if (Test-Path -LiteralPath $outDir) {
  $unsigned = Get-ChildItem -LiteralPath $outDir -Filter '*-unsigned.hap' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $signedFromHvigor = Get-ChildItem -LiteralPath $outDir -Filter '*-signed.hap' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $unsigned -and -not $signedFromHvigor) {
  # 兜底：整棵 entry\build 里找最新的 hap
  $any = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'ohos\entry\build') -Filter '*.hap' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($any) { if ($any.Name -like '*-unsigned*') { $unsigned = $any } else { $signedFromHvigor = $any } }
}

if (-not $unsigned -and -not $signedFromHvigor) {
  Write-Warn '未找到任何 HAP 产物，构建失败。下面的错误行摘自日志：'
  $errs = @()
  if (Test-Path -LiteralPath $log) {
    $errs = Get-Content -LiteralPath $log |
      Select-String -Pattern 'ERROR|error:|Error:|FAILED|Failed|Exception|错误|失败|CreateFile failed' |
      Select-Object -Last 40 | ForEach-Object { $_.Line }
  }
  if ($errs.Count -eq 0) { $errs = @('（日志里没有匹配到错误行，请打开日志全文排查）') }
  $errs | ForEach-Object { Write-Host "  | $_" -ForegroundColor Red }

  $hint = '常见原因：pubspec 依赖未就绪（task-4）、lib 编译错误（task-5）、ohos 工程配置错误。'
  if (Test-Path -LiteralPath $log) {
    if (Select-String -LiteralPath $log -Pattern 'CreateFile failed|cannot access the file or directory' -Quiet) {
      $hint = '环境问题：flutter/dart 无法创建子进程（管道被沙箱拒绝）。' +
              '请在未受限的完整权限会话里运行本脚本（DSH 子代理沙箱会拦截 dart→git/hvigor 的管道）。'
    }
  }
  throw "HAP 构建失败（flutter build 退出码 $buildExit）。完整日志: $log`n$hint"
}

$hapPath = if ($unsigned) { $unsigned.FullName } else { $signedFromHvigor.FullName }
$isUnsigned = [bool]$unsigned
$hapSizeText = '{0:N1} MB' -f ((Get-Item -LiteralPath $hapPath).Length / 1MB)
Write-Ok "HAP 产物: $hapPath ($hapSizeText)"
if ($buildExit -ne 0) {
  if (Select-String -LiteralPath $log -Pattern '配置调试签名' -Quiet) {
    Write-Warn 'flutter build 非 0 退出属于预期：build-profile.json5 的 signingConfigs 为空，' +
               'flutter 在 hvigor 之后检查签名并退出（unsigned hap 已产出）。改为本脚本后续手工签名。'
  } else {
    Write-Warn "flutter build 退出码非 0（$buildExit），但已找到 HAP 产物，继续处理；请检查日志确认无隐患。"
  }
}

# ---------- 4) 签名 ----------
if ($NoSign) {
  Write-Step "跳过签名（-NoSign），unsigned HAP: $hapPath"
  Write-Host "  手工签名: & $signScript -BundleName $BundleName -InHap '$hapPath' -OutHap '$OutHap'"
  return
}
if (-not $isUnsigned) {
  Write-Ok "hvigor 已产出带签名 HAP，直接使用: $hapPath"
  $OutHap = $hapPath
} else {
  Write-Step "签名 HAP → $OutHap"
  & $signScript -BundleName $BundleName -InHap $hapPath -OutHap $OutHap -Udid $Udid -Device $Device
  if (-not (Test-Path -LiteralPath $OutHap)) { throw "签名失败，未产出 $OutHap（查看 .cache\signing\sign-app.log）" }
  Write-Ok "已签名 HAP: $OutHap ($((Get-Item -LiteralPath $OutHap).Length) 字节)"
}

# ---------- 5) 可选安装 / 启动 ----------
$hdc = Join-Path $env:TOOL_HOME 'sdk\default\openharmony\toolchains\hdc.exe'
if (-not (Test-Path -LiteralPath $hdc)) { $hdc = 'hdc' }
if ($Install) {
  Write-Step "hdc -t $Device install -r $OutHap"
  & $hdc -t $Device install -r $OutHap 2>&1 | Out-Host
}
if ($Launch) {
  Write-Step "启动 $BundleName / EntryAbility"
  & $hdc -t $Device shell aa start -a EntryAbility -b $BundleName 2>&1 | Out-Host
  Write-Host "  截图: & '$hdc' -t $Device shell snapshot_display -f /data/local/tmp/fluxdo.jpeg"
  Write-Host "        & '$hdc' -t $Device file recv /data/local/tmp/fluxdo.jpeg .\fluxdo.jpeg"
}

Write-Step '完成'
Write-Host "  签名 HAP : $OutHap"
Write-Host "  构建日志 : $log"
Write-Host "  安装命令 : hdc -t $Device install -r `"$OutHap`""
Write-Host "  启动命令 : hdc -t $Device shell aa start -a EntryAbility -b $BundleName"
