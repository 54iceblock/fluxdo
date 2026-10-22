# VENDOR：share_plus（OHOS 适配副本）

| 项 | 内容 |
|---|---|
| 上游 | <https://github.com/fluttercommunity/plus_plugins> 的 `share_plus` 12.0.1 |
| OHOS 来源 | `gitcode.com/CPF-Flutter/flutter_plus_plugins`，分支 `br_share_plus-v12.0.1_ohos`（路径 `packages/share_plus/share_plus`） |
| 许可证 | BSD-3-Clause（见同目录 `LICENSE`，Copyright 2017 the Flutter project authors） |
| 同步日期 | 2026-10-21 |

## 本地改动

- **Dart/原生代码零改动**（含 `ohos/` ArkTS 实现）。仅保留 `lib/ android/ ios/ macos/ ohos/ windows/` 与
  `pubspec.yaml`/`LICENSE`/`CHANGELOG*`，剔除 `example/`（10.5 MB）与 `test/` 以控制仓库体积。
- 依赖 `share_plus_platform_interface` 仍为相对 path `../share_plus_platform_interface`，由同目录旁的
  `packages/share_plus_platform_interface`（同样是 vendored 副本）提供。

## 为什么 vendored 而不是 git override

CPF fork 的 app-facing 包通过相对 path 引用其 `_platform_interface`，而该 PI 的原始 pubspec 又带一个
**嵌套 git 依赖**（`gitcode.com/openharmony-sig/flutter_packages`，ref `master`，巨型仓库）。直接 git override
会让每次 `flutter pub get` 克隆该仓库、并把 `path_provider` 变成第二种 source。vendored 后把 PI 的
`path_provider` 改回 hosted 约束，`flutter pub get` 只走本地 path，秒级完成。

## 升级/回滚

- 升级：重新拷 `lib/ android/ ios/ macos/ ohos/ windows/` + `pubspec.yaml`，确认 PI 无嵌套 git 依赖。
- 回滚：`pubspec.yaml` 里 `share_plus` 改回 `^12.0.1` hosted（或 `^12.0.2`），删除本目录与
  `packages/share_plus_platform_interface` 即可。
