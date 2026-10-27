# 构建并安装 release 到真机（商用 HarmonyOS 设备，用 DevEco 自动生成的华为调试证书）
#
# 前提：
#   1) DevEco Studio 已登录华为账号，并在
#      File → Project Structure → Signing Configs 勾选过「Automatically generate signature」，
#      此时 repo/ohos/build-profile.json5 里会有 signingConfigs（含加密密码）与
#      products[].signingConfig = "default"；
#   2) 目标设备已用 USB 连接（hdc list targets 能看到）。
#
# 与 tools/build-ohos.ps1 的区别：
#   build-ohos.ps1 走 flutter build hap + 手工 OpenHarmony 证书签名（适合模拟器/开发板）；
#   本脚本走 hvigor 原生签名（华为证书 + 设备白名单 Profile），适合商用真机。
#
# 用法：
#   .\tools\build-device-release.ps1                       # 构建 + 安装 + 启动（自动选设备）
#   .\tools\build-device-release.ps1 -Device 2NP0...       # 指定设备
#   .\tools\build-device-release.ps1 -BuildOnly            # 只构建不安装
param(
  [string]$Device = '',
  [ValidateSet('release', 'debug')][string]$BuildMode = 'release',
  # 覆盖 API 基地址（mock 联调用），例如 http://127.0.0.1:8080
  [string]$BaseUrl = '',
  [switch]$BuildOnly,
  [switch]$SkipStopDaemon
)

$ErrorActionPreference = 'Stop'
$WS = 'C:\Users\iceblock\fluxdo'
$TOOL = 'C:\Users\iceblock\DevEcoStudio'
$REPO = Join-Path $WS 'repo'

$node = Join-Path $TOOL 'tools\node\node.exe'
$hvigorw = Join-Path $TOOL 'tools\hvigor\bin\hvigorw.js'
$hdc = Join-Path $TOOL 'sdk\default\openharmony\toolchains\hdc.exe'
$ohosDir = Join-Path $REPO 'ohos'

foreach ($p in @($node, $hvigorw, $hdc, $ohosDir)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "缺少依赖: $p" }
}

# 环境
$env:DEVECO_SDK_HOME = Join-Path $TOOL 'sdk'
$env:NODE_HOME = Join-Path $TOOL 'tools\node'
$env:JAVA_HOME = Join-Path $TOOL 'jbr'
$env:OHOS_SDK_HOME = Join-Path $TOOL 'sdk'
$env:NODE_OPTIONS = '--max-old-space-size=16384'
$env:PATH = (@(
  (Join-Path $TOOL 'jbr\bin'),
  (Join-Path $TOOL 'tools\node'),
  (Join-Path $TOOL 'tools\ohpm\bin'),
  (Join-Path $TOOL 'tools\hvigor\bin'),
  (Join-Path $TOOL 'sdk\default\openharmony\toolchains')
) -join ';') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'Machine')

# 签名配置检查
$profile = Join-Path $ohosDir 'build-profile.json5'
$profileText = Get-Content -LiteralPath $profile -Raw
if ($profileText -notmatch '"signingConfigs"\s*:\s*\[\s*\{') {
  Write-Host '[build-device] build-profile.json5 没有签名配置。' -ForegroundColor Yellow
  Write-Host '  请在 DevEco Studio 执行：File → Project Structure → Signing Configs →' -ForegroundColor Yellow
  Write-Host '  勾选 Automatically generate signature（需登录华为账号），应用后再运行本脚本。' -ForegroundColor Yellow
  exit 2
}

# 设备
if (-not $Device) {
  $targets = @(& $hdc list targets 2>&1 | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -and $_ -notmatch '^\[' })
  if ($targets.Count -eq 0) {
    if (-not $BuildOnly) { throw '没有已连接设备（hdc list targets 为空）' }
    Write-Host '[build-device] 无设备连接，仅构建。' -ForegroundColor Yellow
  } else {
    $Device = $targets[0]
  }
}
if ($Device) { Write-Host "[build-device] 设备: $Device" }

# 停 daemon（构建脚本/类型检查改动后必须）
if (-not $SkipStopDaemon) {
  Push-Location $ohosDir
  try {
    $ErrorActionPreference = 'Continue'
    & $node $hvigorw --stop-daemon 2>&1 | Out-Null
  } catch {
    # daemon 未运行等情况忽略
  } finally {
    $ErrorActionPreference = 'Stop'
    Pop-Location
  }
}

# 构建
Write-Host "[build-device] hvigor assembleHap (buildMode=$BuildMode) ..."
$log = Join-Path $WS ".cache\ohos-build\logs\device-build-$BuildMode-$(Get-Date -Format yyyyMMdd-HHmmss).log"

# dart-define：标准构建元信息 + 可选的 mock 基地址
$defines = @(
  'FLUTTER_BUILD_NAME=0.2.29',
  'FLUTTER_BUILD_NUMBER=2026102016',
  'FLUTTER_VERSION=3.47.7+ohos-0.0.1-pre',
  'FLUTTER_CHANNEL=[user-branch]',
  'FLUTTER_GIT_URL=https://gitcode.com/CPF-Flutter/flutter_flutter',
  'FLUTTER_FRAMEWORK_REVISION=650641656f',
  'FLUTTER_ENGINE_REVISION=deb287481e',
  'FLUTTER_DART_VERSION=3.13.5'
)
if ($BaseUrl) {
  $defines += "FLUXDO_BASE_URL=$BaseUrl"
  Write-Host "[build-device] 覆盖 API 基地址: $BaseUrl" -ForegroundColor Yellow
}
$dartDefines = ($defines | ForEach-Object {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_))
}) -join ','

Push-Location $ohosDir
try {
  # hvigor 会往 stderr 打 WARN，PowerShell 会当成错误记录；临时放宽
  $ErrorActionPreference = 'Continue'
  & $node $hvigorw --mode module -p module=entry@default -p product=default -p "buildMode=$BuildMode" `
    -p "DART_DEFINES=$dartDefines" `
    assembleHap --analyze=normal --parallel --incremental *> $log
  $exit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = 'Stop'
  Pop-Location
}
if ($exit -ne 0) {
  Write-Host "[build-device] 构建失败（exit=$exit），日志: $log" -ForegroundColor Red
  Get-Content -LiteralPath $log | Select-String -Pattern 'ERROR|error TS' | Select-Object -Last 10 | ForEach-Object { "  $($_.Line)" }
  exit $exit
}

$signed = Join-Path $ohosDir "entry\build\default\outputs\default\entry-default-signed.hap"
if (-not (Test-Path -LiteralPath $signed)) {
  throw "未找到签名产物: $signed（检查 signingConfigs 是否生效、hvigor 是否报 'No signingConfig found'）"
}
$sizeMb = [math]::Round((Get-Item -LiteralPath $signed).Length / 1MB, 1)
Write-Host "[build-device] 已签名产物: $signed ($sizeMb MB)" -ForegroundColor Green

if ($BuildOnly -or -not $Device) { return }

# 安装 + 启动
Write-Host "[build-device] 安装到 $Device ..."
$installOut = & $hdc -t $Device install -r $signed 2>&1 | Out-String
$installOut.Trim()
if ($installOut -notmatch 'install bundle successfully') { throw '安装失败' }

& $hdc -t $Device shell "aa start -a EntryAbility -b com.fluxdo.app" 2>&1 | Out-Null
Write-Host '[build-device] 已启动 com.fluxdo.app' -ForegroundColor Green
Write-Host "[build-device] 截图: & '$hdc' -t $Device shell snapshot_display -f /data/local/tmp/s.jpeg"
