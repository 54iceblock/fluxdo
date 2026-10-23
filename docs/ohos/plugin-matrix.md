# Flutter 插件 HarmonyOS 适配矩阵

> 说明：`插件注册 26 个` 指 hvigor 构建时注册进 `GeneratedPluginRegistrant` 的 OHOS 模块数量。
> 状态含义：**已有实现** = 上游/社区提供 OHOS 端；**自研** = 本移植新增 ArkTS 桥或 Dart 适配；
> **降级** = 无可用实现，功能以替代路径工作；**不涉及** = 该平台插件不参与 OHOS 构建。

## 1. 平台与基础

| 插件 | 状态 | 说明 |
|---|---|---|
| `path_provider_ohos` | 已有实现 | 应用目录（文档/缓存/临时） |
| `shared_preferences_ohos` | 已有实现 | 偏好设置落盘 |
| `package_info_plus_harmonyos` | 已有实现 | 版本号/包名 |
| `device_info_plus` | 已有实现 | 设备信息（社区 OHOS 分支） |
| `connectivity_plus` | 已有实现 | 网络状态 |
| `app_links` | 已有实现 | 深链 `fluxdo://` / `discourse://`（module.json5 skills 配合） |
| `url_launcher_ohos` | 已有实现 | 打开外部链接/浏览器 |
| `flutter_timezone` | 自研 | `FlutterdoBridgePlugin.getLocalTimezone` 替代 |
| `flutter_secure_storage_ohos` | 已有实现 | 安全存储 |

## 2. 网络

| 插件/库 | 状态 | 说明 |
|---|---|---|
| `dio` | Dart 内置 | HTTP 客户端，平台无关 |
| `rhttp`（vendored） | 自研原生库 | Rust reqwest + FRB → `librhttp.so`；设置里「高性能引擎」 |
| `core/doh_proxy` | 自研原生库 | Rust DoH 本地网关 → `libdoh_proxy.so`，进程内 FFI |
| `connectivity_plus` | 已有实现 | 见上 |
| `cronet_http` / `http2` | 不涉及 | 非 OHOS 路径 |

## 3. 媒体与图片

| 插件/库 | 状态 | 说明 |
|---|---|---|
| `native_animated_image`（vendored） | 自研原生库 | 动图解码 `libnative_animated_image_codec.so` |
| AVIF（flutter_avif 等） | 自研原生库 | `libohos_avif.so`（libavif+dav1d）；ImageKit 解码作备用 |
| `flutter_image_compress_ohos` | 已有实现 | 图片压缩 |
| `image_picker_harmonyos` | 已有实现 | 相册/拍照选择 |
| `pro_image_editor` | Dart 实现 | 纯 Dart 图像编辑 |
| `video_player_harmonyos` | 已有实现 | 视频播放 |
| `just_audio_harmonyos`（vendored） | 已有实现 | 音频播放（补 API 26 接口差异） |
| `saver_gallery` | 已有实现 | 保存图片到相册（系统授权弹窗） |

## 4. 系统能力

| 插件/库 | 状态 | 说明 |
|---|---|---|
| `mobile_scanner` | 已有实现 | 相机扫码（CPF OHOS 分支），扫码登录页相机预览正常 |
| `flutter_local_notifications` | 已有实现 | 本地通知（系统通知开关需用户手动开） |
| `flutter_foreground_task` / `workmanager` | 降级 | 无 OHOS 实现；改用系统长时任务（自研 ArkTS 桥） |
| `背景保活` | 自研 | `backgroundTaskManager` DATA_TRANSFER 长时任务 |
| `wakelock_plus_harmonyos` | 已有实现 | 屏幕常亮 |
| `screen_brightness_ohos` | 已有实现 | 屏幕亮度 |
| `volume_controller` | 已有实现 | 音量控制 |
| `record_ohos` | 已有实现 | 录音（麦克风权限） |
| `file_picker`（vendored） | 已有实现 | 选文件/另存为（补 `setSavePayload` 以支持传 bytes） |
| `open_filex` | 已有实现 | 打开文件 |
| `share_plus`（vendored） | 已有实现 | 系统分享面板 |
| `sqflite_ohos` | 已有实现 | SQLite |
| `super_clipboard` | 降级 | 无 OHOS 实现；写图片走自研 pasteboard 桥，读富文本降级纯文本 |
| `ota_update` | 降级 | HAP 不能静默安装；改为跳转发布页 |
| `flutter_inappwebview_ohos` | 已有实现 | 内嵌 WebView（浏览器授权登录等） |
| `flutter_js` | 降级 → 自研 | cook 渲染改用自编 QuickJS（`libohos_quickjs.so`） |
| `flutter_math_fork`（vendored） | 自研适配 | 补 `TargetPlatform.ohos` 分支 |
| `flutter_dynamic_icon_plus` / `gal` / `cronet_http` 等 | 不涉及/降级 | 仅 iOS/Android/桌面使用，不影响 OHOS 主流程 |

## 5. 结论

- **必须**在 OHOS 上工作的能力（网络、图片、存储、通知、相机、分享、文件、数据库、WebView）
  均有可用实现；
- 5 个自编译原生库补齐了 Flutter 生态在 OHOS 上缺位的编解码与 JS 能力；
- 剩余降级项（剪贴板读富文本、应用内更新、cook 的旧 flutter_js 路径）都有替代方案，不阻塞主要功能。
