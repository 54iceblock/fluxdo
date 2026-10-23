# FluxDO HarmonyOS 移植环境变量（每次 pwsh 调用前 dot-source 本文件）
# usage: . <repo>\tools\ohos\env.ps1

# ---- path resolution (portable: derived from script location, env overrides) ----
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $WS) { $WS = if ($env:FLUXDO_WS) { $env:FLUXDO_WS } else { Split-Path $RepoRoot -Parent } }
if (-not $TOOL_HOME) { $TOOL_HOME = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' } }
if (-not $env:TOOL_HOME) { $env:TOOL_HOME = $TOOL_HOME }
# -------------------------------------------------------------------------------

$FLUTTER = if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { Join-Path $WS 'tools\flutter' }

$env:TOOL_HOME = $TOOL_HOME
$env:DEVECO_SDK_HOME = Join-Path $TOOL_HOME 'sdk'
$env:JAVA_HOME = Join-Path $TOOL_HOME 'jbr'
$env:NODE_HOME = Join-Path $TOOL_HOME 'tools\node'
$env:OHOS_SDK_HOME = Join-Path $TOOL_HOME 'sdk'
$env:HOS_SDK_HOME = Join-Path $TOOL_HOME 'sdk'

# 把用户目录指向 workspace 内，避免沙箱阻止 ohpm/hvigor/flutter 写 ~
$env:HOME = Join-Path $WS '.home'
$env:USERPROFILE = Join-Path $WS '.home'
$env:APPDATA = Join-Path $WS '.home\AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $WS '.home\AppData\Local'
New-Item -ItemType Directory -Force -Path $env:HOME, $env:APPDATA, $env:LOCALAPPDATA | Out-Null

$env:PUB_CACHE = Join-Path $WS '.pub-cache'
# 临时目录也放到 workspace 内，避免系统 Temp 的 ACL/沙箱问题
$env:TEMP = Join-Path $WS '.tmp'
$env:TMP = Join-Path $WS '.tmp'
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$env:FLUTTER_ROOT = $FLUTTER
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

# git 的 schannel 在本机不可用，统一走 openssl 后端
$env:GIT_SSL_BACKEND_DIRECT = 'openssl'
$env:GIT_PAGER = 'cat'

$env:PATH = @(
  (Join-Path $FLUTTER 'bin'),
  (Join-Path $TOOL_HOME 'tools\node'),
  (Join-Path $TOOL_HOME 'tools\ohpm\bin'),
  (Join-Path $TOOL_HOME 'tools\hvigor\bin'),
  (Join-Path $TOOL_HOME 'sdk\default\openharmony\toolchains'),
  (Join-Path $TOOL_HOME 'jbr\bin'),
  'C:\Program Files\Git\cmd',
  $env:PATH
) -join ';'

# hvigor 的 pnpm 默认用 symlink 链接 node_modules，Windows 无管理员/开发者模式会 EPERM；
# 改用 hoisted 扁平链接 + 复制，避免创建符号链接。
$env:npm_config_node_linker = 'hoisted'
$env:npm_config_package_import_method = 'copy'
# 再兜底一层：所有 node 进程注入 symlink→junction 降级补丁


# hdc 需要的端口/地址配置
$env:HDC_SERVER_PORT = $env:HDC_SERVER_PORT
