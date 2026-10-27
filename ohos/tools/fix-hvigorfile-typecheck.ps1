# 修复 DevEco「构建脚本类型检查」导致的 hvigorfile.ts 报错
#
# 现象（DevEco Studio 26，构建或 sync 时）：
#   00305003 Syntax Error
#   error TS2742: The inferred type of 'default' cannot be named without a reference to
#     '.../.hvigor/project_caches/<hash>/workspace/node_modules/@ohos/hvigor/types'
#   error TS2550: Property 'replaceAll' does not exist on type 'string'
#   error TS2339: Property 'name' / 'path' does not exist on type 'JSON'
#
# 原因：
#   1) IDE 传 --enable-build-script-type-check，以 ES2016 + strict 检查构建脚本；
#   2) hvigorfile.ts 的 `export default { ... }` 推断类型引用了 hvigor 内部缓存路径，不可移植（TS2742）；
#   3) Flutter SDK 自带的 flutter-hvigor-plugin 有 ES2021/类型问题（已在本仓库 SDK 中修好，
#      见 docs/patches/flutter-hvigor-plugin-typecheck.patch）。
#
# 本脚本做的事：给所有 hvigorfile.ts 的默认导出对象加 `as any`，使导出类型可移植。
# 覆盖范围：repo/ohos、repo/packages、.pub-cache（插件工程的 hvigorfile.ts）。
# flutter pub get / pub cache repair 后 .pub-cache 里的补丁可能丢失，重跑本脚本即可。
#
# 用法：.\tools\fix-hvigorfile-typecheck.ps1 [-CheckOnly]

param(
  [string]$Workspace = 'C:\Users\iceblock\fluxdo',
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Continue'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$roots = @(
  (Join-Path $Workspace 'repo\ohos'),
  (Join-Path $Workspace 'repo\packages'),
  (Join-Path $Workspace '.pub-cache')
) | Where-Object { Test-Path $_ }

$files = @()
foreach ($r in $roots) {
  $files += Get-ChildItem $r -Recurse -File -Filter 'hvigorfile.ts' -ErrorAction SilentlyContinue
}
Write-Host "[fix-hvigorfile] 找到 $($files.Count) 个 hvigorfile.ts"

$patched = 0; $already = 0; $skipped = 0
foreach ($f in $files) {
  $text = [System.IO.File]::ReadAllText($f.FullName)
  if ($text -notmatch 'export default \{') { $skipped++; continue }
  if ($text -match '\} as any') { $already++; continue }
  if ($CheckOnly) {
    Write-Host "  需要修复: $($f.FullName)"
    $patched++
    continue
  }
  $idx = $text.LastIndexOf('}')
  if ($idx -lt 0) { $skipped++; continue }
  $text = $text.Substring(0, $idx + 1) + ' as any' + $text.Substring($idx + 1)
  [System.IO.File]::WriteAllText($f.FullName, $text, $utf8NoBom)
  $patched++
}

if ($CheckOnly) {
  if ($patched -gt 0) {
    Write-Host "[fix-hvigorfile] 有 $patched 个文件需要修复（只检查模式）" -ForegroundColor Yellow
    exit 2
  }
  Write-Host "[fix-hvigorfile] 全部已修复" -ForegroundColor Green
  exit 0
}

Write-Host "[fix-hvigorfile] 已修复 $patched 个，已是最新 $already 个，跳过 $skipped 个" -ForegroundColor Green
Write-Host "[fix-hvigorfile] 提示：改完需要停掉 hvigor daemon："
Write-Host '  & "$env:TOOL_HOME\tools\node\node.exe" "$env:TOOL_HOME\tools\hvigor\bin\hvigorw.js" --stop-daemon'
exit 0
