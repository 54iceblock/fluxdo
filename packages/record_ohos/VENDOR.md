# VENDOR：record_ohos（OHOS 录音插件副本）

| 项 | 内容 |
|---|---|
| 上游 | `record` 的 OHOS 实现（Huawei 提供），Dart API 仍由官方 `record` 包提供 |
| 来源 | `github.com/ClosedHarmony/record_ohos`，`main` @ `851a667b5665611b068533e52ea16d06461a956f` |
| 许可证 | Apache-2.0（见同目录 `LICENSE`） |
| 同步日期 | 2026-10-27 |

## 本地改动（2 个 ArkTS 文件）

1. `ohos/src/main/ets/components/plugin/RecordOhosPlugin.ets`
   - **删除 attach 时的无条件 `checkPermission()`**。上游在 `onAttachedToEngine`
     里就 `requestPermissionsFromUser(MICROPHONE)`，导致 App **一冷启动就弹
     「允许 FluxDO 访问你的麦克风」**（模拟器实测：登录页还没操作就弹窗）。
     这属于与当前操作无关的索权，应用市场审核会判不合理。
   - `checkPermission()` → `ensurePermission()`：已授予直接返回 true，否则现场申请
     并返回最终结果；由 Dart 侧 `hasPermission()` 触发，即用户点「录音」时才弹窗。
   - `requestNecessaryPermissions()` 改为返回 `Promise<boolean>`（原实现是 void，
     拿不到申请结果）。
2. `ohos/src/main/ets/components/plugin/MethodCallHandlerImpl.ets`
   - `hasPermission` 原本硬编码 `result.success(true)`（因为权限已在 attach 时申请过）。
     改为通过注入的 `permissionProvider` 真实检查/申请后返回结果。
   - 否则会出现「Dart 以为有权限 → 直接 start() → 原生录音失败」。

## 为什么 vendored

权限申请时机是原生代码行为，git override 改不了；只能改源码。

## 升级/回滚

- 升级：从上游新 commit 重新拷 `lib/`、`ohos/`、`pubspec.yaml`，**重新应用上面两处改动**，
  更新本文件 commit。
- 回滚：根 `pubspec.yaml` 的 `record_ohos` 改回 git（url `https://github.com/ClosedHarmony/record_ohos.git`，
  `ref: 851a667b5665611b068533e52ea16d06461a956f`），删除本目录。注意回滚后会恢复「冷启动索权」行为。
