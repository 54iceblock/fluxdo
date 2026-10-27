# 发布 GitHub Release（需要 network 写权限；由用户手动执行）
#
# 前置：已登录 gh（gh auth status 显示 54iceblock）
# 用法：pwsh -File C:\Users\iceblock\fluxdo\tools\publish-release.ps1
$ErrorActionPreference = 'Stop'
$repo = '54iceblock/fluxdo'
$tag = 'ohos-v0.2.29'
$branch = 'ohos'
$assets = 'C:\Users\iceblock\fluxdo\.cache\release-assets'
$notes = 'C:\Users\iceblock\fluxdo\.cache\release-notes.md'

if (-not (Test-Path $notes)) { throw "缺少 release notes: $notes" }
if (-not (Test-Path (Join-Path $assets 'fluxdo-ohos-arm64-unsigned.hap'))) { throw "缺少 arm64 HAP: $assets" }

Write-Host "[publish] 检查分支 $branch ..."
gh api "repos/$repo/branches/$branch" 2>&1 | Out-Null

Write-Host "[publish] 创建 Release $tag ..."
gh release create $tag `
  --repo $repo `
  --target $branch `
  --title 'FluxDO for HarmonyOS 7 v0.2.29（侧载版）' `
  --notes-file $notes `
  (Join-Path $assets 'fluxdo-ohos-arm64-unsigned.hap') `
  (Join-Path $assets 'fluxdo-ohos-x64-signed.hap') `
  (Join-Path $assets 'SHA256SUMS.txt')

Write-Host "[publish] 完成：https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
