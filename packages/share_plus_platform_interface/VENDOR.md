# VENDOR：share_plus_platform_interface（配合 vendored share_plus）

| 项 | 内容 |
|---|---|
| 上游 | <https://github.com/fluttercommunity/plus_plugins> 的 `share_plus_platform_interface` 6.1.0 |
| 来源 | `gitcode.com/CPF-Flutter/flutter_plus_plugins`，分支 `br_share_plus-v12.0.1_ohos` |
| 许可证 | BSD-3-Clause（见同目录 `LICENSE`，Copyright 2017 The Chromium Authors） |
| 同步日期 | 2026-10-21 |

## 本地改动（仅 pubspec）

原始 pubspec 的 `path_provider` 是对
`gitcode.com/openharmony-sig/flutter_packages.git`（ref `master`，path `packages/path_provider/path_provider`）
的 **git 依赖**。FluxDO 已依赖官方 `path_provider` + `path_provider_ohos`（OHOS 联邦实现），故改为：

```yaml
path_provider: ^2.1.4
```

行为不变（PI 只用它拿临时目录），但 `flutter pub get` 不再克隆巨型 git 仓库，也不会出现
`path_provider` 双 source 冲突。

## 升级/回滚

- 升级：跟随 share_plus 版本升级，保持 `path_provider` 为 hosted 约束。
- 回滚：删除本目录并恢复 `share_plus` 为 hosted 依赖（PI 会从 pub.dev 解析）。
