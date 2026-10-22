# VENDOR：just_audio_harmonyos（OHOS API 26 补丁副本）

| 项 | 内容 |
|---|---|
| 上游 | pub.dev `just_audio_harmonyos` 0.0.1（Wayaer/harmony_flutter_packages） |
| 许可证 | BSD-3-Clause（见同目录 `LICENSE`，Copyright 2013 The Flutter Authors） |
| 改动日期 | 2026-10-21（OHOS 移植构建期修复，Lead 执行） |

## 为什么需要副本

HarmonyOS 7 / API 26 的 `media.MediaSource` 接口新增了两个成员，ArkTS 强校验
“类必须实现接口全部成员”，上游 0.0.1 未实现 → ArkTS 编译报
`class ... incorrectly implements interface media.MediaSource`。

## 本地改动（仅 1 个文件）

`ohos/src/main/ets/MediaSource.ets` 增补：

```ts
// API 26 的 media.MediaSource 接口新增成员（enableOfflineCache / getID）。
enableOfflineCache(enable: boolean): void { /* 暂不支持离线缓存，no-op */ }
getID(): string { /* 返回稳定 id */ }
```

Dart 侧 API 与官方 `just_audio` 0.10.6 不变；`audio_session_harmonyos` 仍为 pub.dev 0.0.1。

## 接入方式

`repo/pubspec.yaml` 的 `dependencies` 中直接把官方 hosted 依赖换成 path：

```yaml
  just_audio_harmonyos:
    path: packages/just_audio_harmonyos
```

## 升级/回滚

- 升级：上游若补了 API 26 成员，改回 `just_audio_harmonyos: 0.0.1` 并删除本目录。
- 回滚：同上（注意：OHOS 将无法编译）。
