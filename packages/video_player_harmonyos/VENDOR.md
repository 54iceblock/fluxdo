# VENDOR：video_player_harmonyos（OHOS 修复副本）

| 项 | 内容 |
|---|---|
| 上游 | pub.dev `video_player_harmonyos` 0.0.1（Wayaer/harmony_flutter_packages） |
| 许可证 | 见同目录 `LICENSE` |
| 改动日期 | 2026-11-16 |

## 为什么需要副本

真机（HarmonyOS 7 / API 26）上帖子内视频全部显示「视频无法播放」。hilog 显示
系统 AVPlayer 已正常 prepared（拿到时长、尺寸），但 Dart 侧 15 秒超时。

根因：`VideoPlayerApiImpl.create()` 返回的是独立自增的 `playerId`（从 1 开始），
而事件通道名是 `flutter.io/videoPlayer/videoEvents<textureId>`。Dart 侧按返回值
订阅 `videoEvents<playerId>`、`Texture(textureId: playerId)` → 两个 id 不一致，
`initialized` 事件发到没人监听的通道。

## 本地改动（均带「FluxDO 改动」注释）

1. `ohos/src/main/ets/VideoPlayerApiImpl.ets`：`playerId = textureId`（与官方 Android/iOS 一致），
   事件通道、Texture、unregisterTexture、videoPlayers 表统一同一个 id。
2. `ohos/src/main/ets/VideoPlayer.ets`：删除 COMPLETED 分支里的示例播放列表逻辑
   （读取从未设置的 `globalVideoList`，非循环视频播完即抛 TypeError）。
3. `ohos/src/main/ets/VideoPlayer.ets`：出错 `reset()` 回到 IDLE 后不再自动重新设源，
   避免持续性错误（404 / 不支持格式）无限 prepare→error 循环。

Dart API 不变。剔除 `example/`、`test/`。

## 回滚

`repo/pubspec.yaml` 改回 `video_player_harmonyos: 0.0.1`，删除本目录。
