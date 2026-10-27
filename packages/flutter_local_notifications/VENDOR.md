# VENDOR：flutter_local_notifications（OHOS 适配副本）

| 项 | 内容 |
|---|---|
| 上游 | <https://github.com/MaikuB/flutter_local_notifications> 的 `flutter_local_notifications` 22.0.1 |
| OHOS 来源 | `gitcode.com/CPF-Flutter/fluttertpc_flutter_local_notifications`，分支 `br_3.41_dev` @ `714178b60a5d39268c6c74ec1082be559d1d121a`（路径 `flutter_local_notifications`） |
| 许可证 | BSD-3-Clause（见同目录 `LICENSE`） |
| 同步日期 | 2026-10-26 |

## 本地改动

- **唯一改动**：`ohos/src/main/module.json5` 删除 `ohos.permission.PUBLISH_AGENT_REMINDER`。
  - 该权限只给 `reminderAgentManager`（`zonedSchedule` 定时提醒）用；FluxDO 只调用 `show()`
    即时通知（`lib/services/local_notification_service.dart`）。
  - HAR 里声明的权限会被 hvigor 合并进最终 HAP —— 只删应用侧声明无效（2026-10 解包实测）。
    不删的话上架包会多一个「声明了却不用」的权限。
- Dart / ArkTS / Android / iOS 代码零改动；剔除 `example/`、`test/` 与构建产物。
- 兄弟包（`_platform_interface` / `_linux` / `_windows` / `_web`）仍走 pub.dev hosted，未 vendored。

## 为什么 vendored 而不是 git override

git override 只能整包引用，没法改 HAR 的 `module.json5`；权限删减必须改源码。

## 升级/回滚

- 升级：从 CPF fork 新 commit 重新拷 `lib/ android/ darwin/ ios/ macos/ ohos/` + `pubspec.yaml`，
  **再次删除** `module.json5` 里的 `PUBLISH_AGENT_REMINDER`，更新本文件的 commit。
- 若要启用定时提醒：在应用 `ohos/entry/src/main/module.json5` 补回该权限即可，无需改本包。
- 回滚：根 `pubspec.yaml` 的 `flutter_local_notifications` override 改回 git
  （url 同上，`ref: 714178b60a5d39268c6c74ec1082be559d1d121a`，`path: flutter_local_notifications`），删除本目录。
