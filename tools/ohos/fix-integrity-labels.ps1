# 检查并修复工作区完整性标签（避免 Dart/Flutter 以低完整性运行）
#
# 背景：DSH 沙箱会给工作区打 "Low Mandatory Level" 标签。工作区内的 dart.exe
# 会以低完整性（Low IL）运行，无法写入 %APPDATA%，导致：
#   - Flutter 报 "Flutter failed to write to a file at ...\.flutter_tool_state"
#   - Dart 报 "PathAccessException: Creation failed, path = ...\.dart-tool"
#   - DevEco 里 assembleHap 在 FlutterTask / PackageHap 阶段失败
#
# 本脚本把工作区（默认 C:\Users\you\fluxdo）的完整性标签恢复为 Medium。
# 用法：
#   .\tools\ohos\fix-integrity-labels.ps1            # 检查 + 修复
#   .\tools\ohos\fix-integrity-labels.ps1 -CheckOnly # 只检查
param(
  [string]$Workspace = '',
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Continue'
if (-not $Workspace) { $Workspace = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent }
if (-not (Test-Path -LiteralPath $Workspace)) { throw "工作区不存在: $Workspace" }
$full = [System.IO.Path]::GetFullPath($Workspace)
Write-Host "[fix-integrity] 工作区: $full"

$label = & icacls $full 2>&1 | Select-String -Pattern 'Mandatory Label' | ForEach-Object { $_.Line.Trim() }
if (-not $label) {
  Write-Host "[fix-integrity] 未发现完整性标签（无需修复）" -ForegroundColor Green
  exit 0
}
Write-Host "[fix-integrity] 当前标签: $label"

if ($label -match 'Low Mandatory Level') {
  if ($CheckOnly) {
    Write-Host "[fix-integrity] 检测到 Low 标签（只检查模式，不修复）" -ForegroundColor Yellow
    exit 2
  }
  Write-Host "[fix-integrity] 正在把工作区标签恢复为 Medium（文件较多，约 3-6 分钟）..." -ForegroundColor Yellow
  $t0 = Get-Date
  & icacls $full /setintegritylevel '(OI)(CI)M' /T /C /Q 2>&1 | Select-Object -Last 2
  Write-Host "[fix-integrity] 完成，耗时 $([math]::Round(((Get-Date)-$t0).TotalSeconds,1))s"

  # 顺带把 Flutter/Dart 在 AppData 下的状态文件恢复为 Medium
  foreach ($p in @(
    "$env:APPDATA\.flutter_tool_state",
    "$env:APPDATA\.flutter_settings",
    "$env:APPDATA\.dart-tool",
    "$env:LOCALAPPDATA\.dart-tool"
  )) {
    if (Test-Path -LiteralPath $p) { & icacls $p /setintegritylevel M 2>&1 | Out-Null }
  }

  $after = & icacls $full 2>&1 | Select-String -Pattern 'Mandatory Label' | ForEach-Object { $_.Line.Trim() }
  Write-Host "[fix-integrity] 修复后标签: $after"
  if ($after -match 'Low Mandatory Level') {
    Write-Host "[fix-integrity] 修复未完全生效，请重试或检查权限" -ForegroundColor Red
    exit 1
  }
  Write-Host "[fix-integrity] 修复成功" -ForegroundColor Green
  exit 0
}

Write-Host "[fix-integrity] 标签为 Medium/其它，无需修复" -ForegroundColor Green
exit 0
