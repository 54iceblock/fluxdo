# fluxdo × HarmonyOS 7 插件适配矩阵（task-1 交付）
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从 `module.json5` 删除。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 调研对象：`repo/pubspec.yaml`（107 条直接依赖，含 9 个 workspace/path 包）+ `repo/pubspec.lock`（约 340 个包）+ `lib/`、`packages/` 共 1015 个 dart 文件的 `package:` 导入
> 目标平台：HarmonyOS 7 / OpenHarmony API 26；OHOS Flutter SDK `C:\Users\iceblock\fluxdo\tools\flutter`（分支 `oh-3.47.7-preview`，版本 **3.47.7-ohos-0.0.1-canary1**）；DevEco Studio 26.0
> 调研时间：2026-10-21；调研者：plugin-scout（task-1）
> 证据等级：**✓已验证** = 本机 `git ls-remote` / raw pubspec 抓取 / pub.dev API 实测确认；**○文档** = 官方适配清单列出但未拉取仓库验证；**?未验证** = 推断，需构建期确认

---

## 0. 结论摘要（先看这里）

1. **生态版本上限低于目标框架**：官方适配清单 <https://gitcode.com/OpenHarmony-Flutter/docs>（`ThirdpartyLibrarites.md`）只标注 Flutter **3.7 / 3.22 / 3.27 / 3.35** 四档；CPF-Flutter 组织最新活跃分支是 `br_3.41_dev`（2026-10-19）。**没有任何 OHOS 插件 fork 声明支持 3.47.7**。目标 SDK 是 canary1（0.0.1），插件全部要在 3.47 har 上重新编译验证 → **这是本移植最大的系统性风险**。
2. **好消息**：pub.dev 上已存在一批 `*_ohos` 联邦实现（path_provider / shared_preferences / url_launcher 等，2026-08 重新发布），项目 lockfile 里已经解析到 `screen_brightness_ohos 2.1.4` 与 `flutter_image_compress_ohos 0.0.3+1` —— 说明这两条链路**零改动**即可用。
3. **基础 8 件套（path_provider / shared_preferences / url_launcher / package_info_plus / device_info_plus / connectivity_plus / flutter_secure_storage / sqflite）全部有可用实现**，其中 7 个是 pub.dev 包或已验证 git fork，足以让 app 启动到首屏。
4. **最大单点风险是 `flutter_inappwebview`**（24 个业务文件 + 34 个平台接口文件）：只能退到 CPF 的 `6.1.5-ohos`，项目现在用的是 `6.2.0-beta.3`；且 OHOS 用 ArkWeb 内核，`InAppWebViewController` 的 cookie/JS 注入/OAuth 回调行为需逐个验证。
5. **Rust/FFI 类包几乎全线缺失**：`rhttp`、`native_animated_image`、`super_clipboard(super_native_extensions)`、`full_svg_flutter(quickjs_engine)`、`flutter_avif` 在 OHOS 无实现。其中 `rhttp` 已有优雅降级（`main.dart` 5s 超时 → `RhttpSettingsService.forceDisable()`），其余需要在 `lib/` 加条件降级。
6. **一个被忽视的代码级地雷**：OHOS 上 `dart:io` 的 `Platform.operatingSystem == 'ohos'`（已核对 SDK：`packages/flutter/lib/src/foundation/_platform_io.dart:28` 映射为 `TargetPlatform.ohos`）。而 `lib/` 里现有 **100 处 `Platform.isWindows`、52 处 `isAndroid`、52 处 `isMacOS`、41 处 `isIOS`**，在 OHOS 上**全部为 false** → 大量"移动端逻辑"会静默走桌面 else 分支。插件适配前必须先加 `PlatformExt.isOhos` 并逐点修正。
7. **权限模型与 Android 完全不同**：媒体库**不要**申请 `READ_IMAGEVIDEO`/`WRITE_IMAGEVIDEO`（受限权限，需 ACL 申请，普通三方应用拿不到），OHOS 官方推荐 **Picker 读 + SaveButton/授权弹窗 写**（无权限）。`READ_PASTEBOARD` 同为受限权限。详见 §3。
8. **pubspec 改写建议采用"双文件"策略**：`pubspec.yaml` 保持五端现状，新增 `pubspec.ohos.yaml` + 切换脚本，避免把 Android/iOS/Windows 的插件版本一并降级（inappwebview 6.1.5、file_picker 10.3.8、record 等都低于现网版本）。详见 §2。
9. **`flutter pub get` 在本机会被两件事卡住**（已实测）：① pub 缓存默认写 `%LOCALAPPDATA%\Pub` 被沙箱拒绝（`Creation failed ... errno = 5`）→ 需 `PUB_CACHE=C:\Users\iceblock\fluxdo\.cache\pub`；② gitcode 的 TLS 必须走 OpenSSL → 用 `GIT_CONFIG_GLOBAL=<workspace>\.gitconfig`（内容 `[http] sslBackend = openssl`）**已验证可让 git 与 pub get 都通**。
10. **矩阵覆盖**：本文件逐行覆盖 **56 个原生/插件类依赖**（pubspec 直接 43 + 关键传递 13；拆开分组行后逐一给出结论），另列出 **45 个纯 Dart 依赖**（无需处理）。

---

## 1. 全量插件矩阵

图例：OHOS 支持 = ✅有 / ⚠️仅替代 / ❌无。风险 = 低/中/高（含版本差、内核差异、权限模型差异）。

### 1.1 A 组：上游已内置 OHOS 或 OHOS 社区已发布联邦实现（改动量 ≈ 0）

| 包名 | 用途（使用处） | 纯 Dart | OHOS 支持 | 推荐仓库 + ref | 适配风险 | 建议动作 |
|---|---|---|---|---|---|---|
| screen_brightness 2.1.11 | 播放器亮度手势（2 文件） | 否 | ✅ pub.dev 已联邦化：`screen_brightness_ohos 2.1.4`（lock 已解析） | pub.dev，无需覆盖 | 低 | 保持 |
| flutter_image_compress 2.5.1 | 上传前压缩（1 文件） | 否 | ✅ 联邦化：`flutter_image_compress_ohos 0.0.3+1`（lock 已解析） | pub.dev，无需覆盖 | 低 | 保持 |
| chat_bottom_container 0.4.1 | 聊天输入框容器（4 文件） | 否（主体 Dart+shared_preferences） | ⚠️ **0.5.3 起声明 ohos**，现锁 0.4.1 无 | pub.dev `^0.5.3` | 低 | 升级到 `^0.5.3`（需回归聊天页） |

### 1.2 B 组：有社区 OHOS 实现，需 `dependency_overrides` / 追加实现包（核心工作量）

| 包名 | 用途（使用处） | 纯 Dart | OHOS 支持 | 推荐仓库 + ref（已验证） | 适配风险 | 建议动作 |
|---|---|---|---|---|---|---|
| **path_provider** 2.1.6 | 缓存/DB/导出目录（30 文件） | 否 | ✅ pub.dev `path_provider_ohos 2.2.1`（2026-08-19，env sdk≥2.18/flutter≥3.3，dartPluginClass） | `path_provider_ohos: ^2.2.1`（也可 `gitcode.com/openharmony-tpc/flutter_packages` packages/path_provider/path_provider_ohos） | 低 | 作为**直接依赖**加入 pubspec.ohos.yaml |
| **shared_preferences** 2.5.5 | 全局设置（67 文件） | 否 | ✅ pub.dev `shared_preferences_ohos 2.2.0`（同上，dartPluginClass） | `shared_preferences_ohos: ^2.2.0` | 低 | 直接依赖 |
| **url_launcher** 6.3.2 | 外链/商店页（8 文件） | 否 | ✅ pub.dev `url_launcher_ohos 6.3.0`（要求 sdk≥3.2/flutter≥3.16） | `url_launcher_ohos: ^6.3.0` | 低 | 直接依赖 |
| **flutter_secure_storage** 10.3.4 | token/密钥加密（3 文件，含 ai_model_manager） | 否 | ✅ 原生-only 插件（官方 Dart API 不动）：`ClosedHarmony/flutter_secure_storage_ohos@main` | `git: https://github.com/ClosedHarmony/flutter_secure_storage_ohos.git, ref: main`（其 README：通道 `plugins.it_nomads.com/flutter_secure_storage` 在 platform_interface 1.x/2.x 下一致，方法/参数键相同；其作者验证组合是官方 **11.x**，本项目 10.3.4 走 PI 2.1.1 同一通道，需实测 `readAll/deleteAll`） | 中（首次迁移/`resetOnError`；ArkTS 侧 RSA+AES-GCM） | 保留官方 `flutter_secure_storage`，**追加**该包为依赖（不要用 CPF 分支，见下） |
| flutter_secure_storage（备选，不推荐） | 同上 | 否 | ⚠️ CPF `br_v11.2.0_ohos_dev` 内 app-facing 仍是 **9.2.4**，`flutter_secure_storage_platform_interface` 只有 **1.1.2**（项目锁 2.1.1）→ 版本冲突 | `gitcode.com/CPF-Flutter/fluttertpc_flutter_secure_storage`, path 覆盖 | 高 | 仅当 ClosedHarmony 方案失败时评估 |
| **package_info_plus** 8.3.1 | 版本号（6 文件） | 否 | ✅ 两条路：① CPF `br_package_info_plus-v9.0.0_ohos`（app 9.0.0，含 ohos）；② Wayaer impl `package_info_plus_harmonyos 0.0.1`（PI ^3.1.0，可保留 8.3.1） | ① `gitcode.com/CPF-Flutter/flutter_plus_plugins` ref `br_package_info_plus-v9.0.0_ohos` path `packages/package_info_plus/package_info_plus`；② `git: Wayaer/harmony_flutter_packages`, path `package_info_plus_harmonyos` | 中（9.x 会牵动 win32/device_info_plus 约束，pubspec 已有注释） | 先走 ②（不改版本）；失败再升 9.x |
| **device_info_plus** 12.3.0 | 设备信息/UA（3 文件） | 否 | ✅ CPF `br_device_info_plus-v12.3.0_ohos`（app **12.3.0，与现网完全一致**，含 ohos） | `gitcode.com/CPF-Flutter/flutter_plus_plugins` ref `br_device_info_plus-v12.3.0_ohos` path `packages/device_info_plus/device_info_plus` | 低 | override 到该 ref |
| **connectivity_plus** 7.0.0 | 网络状态/VPN 自愈（2 文件） | 否 | ✅ CPF `br_connectivity_plus-v7.0.0_ohos`（app **7.0.0，精确匹配**） | 同上 org, ref `br_connectivity_plus-v7.0.0_ohos`, path `packages/connectivity_plus/connectivity_plus` | 低 | override |
| **share_plus** 12.0.2 | 分享主题/图片（7 文件） | 否 | ✅ CPF `br_share_plus-v12.0.1_ohos`（app **12.0.1，精确匹配**） | 同上 org, ref `br_share_plus-v12.0.1_ohos`, path `packages/share_plus/share_plus` | 中（Share Kit 能力：文本/图片/URI 组合与 Android 不完全等价） | override；`share_utils.dart` 需实测 |
| **open_filex** 4.7.0 | 打开已下载文件（2 文件） | 否 | ✅ CPF `fluttertpc_open_filex` TAG `4.7.0-ohos-1.0.0`（app 4.7.0 精确匹配） | `gitcode.com/CPF-Flutter/fluttertpc_open_filex.git`, ref `4.7.0-ohos-1.0.0` | 中（需 URI 授权 + want 拉起，文件须在应用沙箱或授权 URI 内） | override |
| **file_picker** 10.3.10 | 选文件/导出（6 文件） | 否 | ✅ CPF `fluttertpc_file_picker` TAG `10.3.8-ohos-1.0.0`（分支 `br_v10.3.8_ohos`, 2026-08-01） | `gitcode.com/CPF-Flutter/fluttertpc_file_picker.git`, ref `10.3.8-ohos-1.0.0` | 中（10.3.10→10.3.8 降级；文档选择器返回 file:// 需转换为沙箱路径） | override + 回归 6 处调用 |
| **image_picker** 1.2.3 | 选图/拍照（6 文件） | 否 | ✅ Wayaer impl `image_picker_harmonyos 0.0.1`（plats=[ohos]，PI ^2.8.0；项目 PI 2.11.1 ✓） | `git: https://github.com/Wayaer/harmony_flutter_packages.git, ref: main, path: image_picker_harmonyos` | 中（PhotoViewPicker 无 exif 旋转位；相机走 CAMERA 权限） | 追加为依赖，保留官方 image_picker |
| **mobile_scanner** 7.4.2 | 扫码登录（1 文件） | 否 | ✅ CPF `fluttertpc_mobile_scanner` TAG `7.1.4-ohos-1.0.0-beta.1`（分支 `br_v7.1.4_ohos`） | `gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner.git`, ref `br_v7.1.4_ohos` | 中高（7.4.2→7.1.4 API 差异；CAMERA 权限；扫码结果回调需实测） | override；`qr_login_scan_page.dart` 用 `zxing2` 解码兜底已有 |
| **record** 7.1.1 | 语音消息录制 AAC（1 文件） | 否 | ✅ `ClosedHarmony/record_ohos@main`（1.0.0，`record_platform_interface ^2.1.0` 与 record 7.1.1 匹配） | `git: https://github.com/ClosedHarmony/record_ohos.git, ref: main` | 中（MICROPHONE 权限；AAC-LC 编码器参数需实测） | 追加为依赖（保留官方 record 7.x） |
| **video_player** 2.14.0 | 视频播放（6 文件） | 否 | ✅ Wayaer impl `video_player_harmonyos 0.0.1`（AVPlayer，PI ^6.4.0，项目 6.9.0 ✓） | `git: Wayaer/harmony_flutter_packages, ref: main, path: video_player_harmonyos` | 高（外接纹理/全屏切换/`video_player_platform_interface` 6.9 新 API 覆盖度），桌面 media_kit 后端不动 | 追加依赖 + 重点回归播放器 |
| **just_audio** 0.10.6 | 音频播放（2 文件） | 否 | ✅ ① Wayaer `just_audio_harmonyos 0.0.1` + `audio_session_harmonyos`（PI 4.6.0 精确匹配）；② CPF `br_v0.10.6_ohos`（app 0.10.5）+ `flutter_audio_session br_v0.2.2_ohos` | ① path 依赖同 Wayaer 仓库；② `gitcode.com/CPF-Flutter/fluttertpc_just_audio.git` ref `br_v0.10.6_ohos`、`gitcode.com/CPF-Flutter/flutter_audio_session.git` ref `br_v0.2.2_ohos` | 高（AVPlayer 与 ExoPlayer 行为差异：seek/pitch/播放列表） | 先试 ①，失败再试 ② |
| **wakelock_plus** 1.3.3 | 播放防熄屏（1 文件） | 否 | ✅ ① Wayaer `wakelock_plus_harmonyos 0.0.1`（PI ^1.2.3，可保留 1.3.3）；② CPF `br_v1.4.0_ohos`（app 1.4.0，但 1.4 需 package_info_plus ^9） | ① path 依赖；② `gitcode.com/CPF-Flutter/fluttertpc_wakelock_plus.git` ref `br_v1.4.0_ohos` | 低 | 优先 ①（不动版本） |
| **volume_controller** 3.7.0 | 手势调音量（1 文件） | 否 | ✅ CPF `br_v3.6.0_ohos_dev`（2026-10-20 更新，分支内含 `ohos/`） | `gitcode.com/CPF-Flutter/fluttertpc_volume_controller.git`, ref `br_v3.6.0_ohos_dev`（TAG `3.4.0-ohos-1.0.0` 太旧，不建议） | 低（`^3.6.0` 约束可放宽到 3.6.0） | override |
| **flutter_local_notifications** 21.0.0 | 本地通知（1 文件） | 否 | ✅ CPF `br_3.41_dev`：app **22.0.1 已含 ohos**，其 `ohos/src/main/module.json5` 声明 `INTERNET + PUBLISH_AGENT_REMINDER`（已验证） | `gitcode.com/CPF-Flutter/fluttertpc_flutter_local_notifications.git` ref `br_3.41_dev`, path `flutter_local_notifications`；若坚持 19.x 用 TAG `19.5.0-ohos-1.0.0` | 中（21→22 升级；OHOS 需 `requestEnableNotification` 用户开关，通知渠道概念与 Android 不同） | override + 升级；`local_notification_service.dart` 加 OHOS 初始化参数 |
| **flutter_inappwebview** 6.2.0-beta.3 | 内置浏览器/OAuth/编辑器预览（24 业务文件 + 34 平台接口文件） | 否 | ✅ CPF `br_v6.1.5_ohos`（2026-10-16 更新）：app `6.1.5` + `flutter_inappwebview_ohos 1.1.3` + PI `1.3.0+1`。`ClosedHarmony/zikzak_inappwebview` **不含 ohos 目录**（已验证） | `gitcode.com/CPF-Flutter/flutter_inappwebview.git`, ref `br_v6.1.5_ohos`，**需 path 覆盖 3 个包**：`flutter_inappwebview` / `flutter_inappwebview_platform_interface`(1.3.0+1) / `flutter_inappwebview_ohos`；android/ios/web/windows 各平台包继续用 pub 版 | **高**（6.2.0-beta.3→6.1.5 降级 + PI 1.4.0→1.3.0；ArkWeb 内核 cookie/JS/`evaluateJavascript`/OAuth 回调差异；项目里 `packages/flutter_inappwebview_linux` 与 `packages/flutter_inappwebview_windows` 两个私有 fork 与 ohos 无交集） | 最高优先级专项：先在本机生成 `ohos/` 工程并跑通 `flutter build hap`，再逐页回归 OAuth/编辑器预览 |
| **app_links** 7.2.1 | 深链 `fluxdo://` `discourse://`（1 文件） | 否 | ✅ CPF `br_7.2.2_ohos_dev`（7.2.2，2026-10-13；TAG `7.0.0-ohos-1.0.1` 亦可） | `gitcode.com/CPF-Flutter/fluttertpc_app_links.git`, ref `br_7.2.2_ohos_dev`, path `app_links` | 中（OHOS 需在 module.json5 配 `skills.uris`+`want`，冷启动参数取法不同） | override + 配 module.json5 |
| **sqflite** 2.4.4（经 flutter_cache_manager 传递） | 图片/主题缓存 DB | 否 | ✅ CPF `flutter_sqflite` `br_3.41_dev`：`sqflite 2.4.2+1` + `sqflite_ohos`（2026-10-15） | `gitcode.com/CPF-Flutter/flutter_sqflite.git`, ref `br_3.41_dev`, path `sqflite`（+ `sqflite_platform_interface` 视版本） | 中（2.4.4→2.4.2；OHOS 走 RDB，SQL 方言差异需回归缓存清理） | override |
| **audio_session** 0.2.4（just_audio 传递） | 音频会话/打断处理 | 否 | ✅ CPF `flutter_audio_session` `br_v0.2.2_ohos`（0.2.2，2026-10-12） | `gitcode.com/CPF-Flutter/flutter_audio_session.git`, ref `br_v0.2.2_ohos` | 中 | override（与 just_audio 方案配套） |
| **flutter_math_fork** 0.7.4 | 数学公式渲染（1 文件） | 是（纯 Dart） | ✅ CPF `br_v0.7.4_flutter3.35.7_ohos`（0.7.4，字体/兼容修正） | `gitcode.com/CPF-Flutter/flutter_math_fork.git`, ref `br_v0.7.4_flutter3.35.7_ohos` | 低（纯 Dart，可先用 pub 版） | 先不覆盖；渲染异常再换 |
| **fluttertoast** 10.0.0（catcher_2 传递） | 崩溃/提示 toast | 否 | ✅ CPF `flutter_fluttertoast` `br_8.2.8_ohos`（另有 `br_3.41_dev`） | `gitcode.com/CPF-Flutter/flutter_fluttertoast.git`, ref `br_8.2.8_ohos` | 低 | 需要时 override（catcher_2 的 toast handler） |
| **flutter_foreground_task** 9.2.2 | 后台通知轮询保活（2 文件） | 否 | ⚠️ 官方清单标"开发中"；CPF `fluttertpc_flutter_foreground_task` 仅 `br_3.35_dev`（**无 TAG**，2026-10 仍在改） | `gitcode.com/CPF-Flutter/fluttertpc_flutter_foreground_task.git`, ref `br_3.35_dev`（未验证可用性） | 高 | 不作为 P0；建议 OHOS 侧改为自写「长时任务」桥（`backgroundTaskManager.startBackgroundRunning` + `KEEP_BACKGROUND_RUNNING`）或降级为前台定时器 |

### 1.3 C 组：OHOS 无实现，需替代 / 自写 ArkTS 桥 / 运行时降级

| 包名 | 用途（使用处） | 纯 Dart | OHOS 支持 | 替代方案 + 推荐 ref | 适配风险 | 建议动作 |
|---|---|---|---|---|---|---|
| **gal** 2.3.3 | 保存图片到相册（1 文件 `image_save_utils.dart`） | 否 | ❌ 无 OHOS（官方清单无此条目；`fluttertpc_gal` 仓库无 ohos 分支） | ✅ `saver_gallery ^5.1.0`（plats 含 ohos，env flutter≥3.44，5.x 起支持鸿蒙；返回媒体库 URI，内部用 SaveButton/授权弹窗 → **无需权限**） | 中（API 不同：`Gal.putImageBytes` → `SaverGallery.saveImage`；需改 1 处封装） | 换包 + 改 `image_save_utils.dart` |
| **flutter_js** 0.8.7 | Discourse markdown-it cook 渲染（1 文件 `cook_js_engine_io.dart`） | 否（FFI/QuickJS） | ❌ 无 OHOS；`ClosedHarmony/fjs` 也不含 ohos 平台目录 | ✅ CPF `fluttertpc_flutter_qjs`：TAG `0.3.7-ohos.1.0.0-beta.1`，仓库**含 `ohos/` 目录**（已验证） | 中高（换引擎 API：`JavascriptRuntime` → `QjsRuntime`；cook bundle 执行/内存上限需回归） | 用 flutter_qjs 重写 cook 引擎适配层（单文件，可控） |
| **super_clipboard** 0.9.1 | 富文本/图片剪贴板（6 文件） | 否（Rust `super_native_extensions`） | ❌ 无 OHOS（`super_native_extensions` 平台=android,ios,linux,macos,windows,web；`irondash_*` 同） | 降级：`Clipboard.getData(Clipboard.kTextPlain)` + 现有 `html2md`（文本）；图片粘贴走 file_picker | 高（富粘贴保真度下降；6 处调用需抽一层 `RichClipboard` 门面） | 加平台门面 + 条件降级；不要尝试移植 Rust |
| **native_animated_image** 0.3.4 | 动图解码（4 文件：cached_image/cache_manager/sticker/main） | 否（Rust） | ❌ 无 ohos 平台包（仅 macos/ios/android/windows/linux） | 回退 Flutter 内置 `ImageProvider`（`cached_image.dart` 已有 provider 链，只需在 OHOS 分支不注册 native） | 中（内置 multi_frame_codec 在 disposal=2 有 #85831 缺陷；动图可能闪烁/卡顿） | 运行时降级；后续可由作者（Lingyan000）新增 `native_animated_image_ohos`（Rust target `aarch64-unknown-linux-ohos`） |
| **flutter_avif** 3.1.0 + `_platform_interface` 3.1.0 | AVIF 解码（`avif_image_provider.dart` + 直连 FFI 的 `avif_fast_bridge.dart`） | 否（C: libavif/dav1d） | ❌ 官方清单标"开发中"，无实现 | ① 短期：OHOS 分支禁用 provider → 普通图片加载失败占位；② 中期：用 OHOS ImageKit（`@ohos.multimedia.image`）解 AVIF（需验证 API 26 是否支持 AVIF） | 中（`avif_fast_bridge.dart` 直连 `FlutterAvifImpl.flutterAvifFFI`，OHOS 无该符号 → 必须编译期/运行期隔离） | 加 `if (!isOhos)` 门面；`avif_fast_bridge` 用条件导入排除 |
| **rhttp**（git `Lingyan000/rhttp_plus`, FRB 2.12.0） | 高性能/TLS 指纹网络栈（2 文件） | 否（Rust） | ❌ 无 OHOS（无 ohos 平台；`flutter_rust_bridge_ohos` 只有 **2.11.2**，与项目 pin 的 2.12.0 冲突） | 已有降级：`main.dart:378` `Future.any` 5s 超时 → `RhttpSettingsService.forceDisable()`，网络回落 dio 默认 adapter | 中（指纹/DoH 相关能力在 OHOS 丢失；需验证 `dio_compatibility_layer` 回落路径无报错） | P2：先依赖现成降级；后续再评估 Rust 交叉编译 |
| **dio / native_dio_adapter / cronet_http / cupertino_http / jni** | HTTP（dio 88 文件） | dio 纯 Dart；其余含原生 | ❌（cronet=Cronet/JNI，cupertino=Darwin） | OHOS 走 Dio 默认 `IOHttpClientAdapter`（`platform_adapter.dart` 只在 Android/iOS/macOS/Windows 分支启用原生 adapter → OHOS 自然回落） | 低 | 无需改动，验证回落分支 |
| **pro_image_editor** 11.23.0 | 图片编辑（2 文件） | 否（原生插件仅 android） | ⚠️ 插件声明只有 android（`ch.waio.pro_image_editor`） | Dart 侧裁剪/滤镜可用；OHOS 上原生插件不注册 → 依赖原生的入口需 try/catch | 中 | 加 try/catch 降级到 `flutter_image_compress` + 直接上传 |
| **catcher_2** 2.1.12 | 崩溃/错误上报（3 文件） | 是（纯 Dart 插件，无原生） | ⚠️ 自身可用；但它拉 `flutter_mailer`（无 OHOS）+ `fluttertoast`（有 OHOS 移植） | 保留 `catcher_2`；禁用邮件 handler；`fluttertoast` 用 CPF 覆盖 | 中 | 配置层禁用 email/toast 上报 |
| **full_svg_flutter** 1.5.1（依赖 `quickjs_engine` FFI） | 动画 SVG（1 文件 `animated_svg_view.dart`） | 否（FFI） | ❌ `quickjs_engine` 平台=android,ios,macos,linux,windows，无 ohos | 降级：动画 SVG 改用 `jovial_svg` 静态渲染（项目已大量使用 jovial_svg） | 中 | 条件导入/降级 |
| **flutter_timezone** 5.1.0 | 本地时区（1 文件 `time_utils.dart`） | 否 | ❌ 无 OHOS（CPF `fluttertpc_flutter_timezone` 仅到 2.1.0，API 是旧版返回 String；pub `flutter_timezone_ohos 1.0.0` 是旧 1.x） | 自写 MethodChannel（ArkTS：`@ohos.i18n` → `i18n.System.getSystemTimeZone()`，约 30 行） | 中（时区错会污染全部时间显示；`TimeUtils` 是全局基座） | 自写桥（P0 级：影响所有时间格式化） |
| **flutter_displaymode** 0.7.0 | Android 高刷（2 文件） | 否 | ❌ 无 OHOS | 自写桥（`@ohos.display` `getDefaultDisplaySync().refreshRate`）或直接禁用（默认 60/90Hz） | 低 | 平台守卫内禁用 |
| **flutter_dynamic_icon_plus** 1.4.1 | 动态图标（pubspec 声明） | 否 | ❌ 无 OHOS（同类 `flutter_dynamic_icon` 仍是"开发中"） | OHOS 三方应用不能运行时换图标 | 低 | 禁用（保留设置项但隐藏/置灰） |
| **window_manager / screen_retriever / flutter_acrylic** | 桌面窗口/亚克力（4+1+1 文件） | 否（桌面专属） | ❌ 无 OHOS（`screen_retriever` 有 CPF 0.1.9-ohos，但项目用 0.2.x 且手机端不需要） | OHOS 手机形态不需要；现有代码已被 `Platform.isWindows/isMacOS/isLinux` 守卫 | 低 | 不注册、不改代码（但注意 §0.6：OHOS 上这些守卫全 false，正好不会调用） |
| **workmanager** 0.9.3 | iOS 后台拉取（2 文件） | 否（android/apple only） | ❌ 无 OHOS | 代码仅在 `Platform.isIOS` 分支调用 → OHOS 不会触发 | 低 | 保持依赖，无需实现 |
| **ota_update** 7.1.0 | APK 下载更新（1 文件 `apk_download_service.dart`） | 否 | ⚠️ CPF `br_3.35`（app 7.0.2，2026-08-21，**含 `ohos/`**，新增 `executeOhos` API） | `gitcode.com/CPF-Flutter/fluttertpc_ota_update.git`, ref `br_3.35`（TAG `7.0.2-ohos-1.0.0`）；测试环境仅 3.32/3.35 | 中高（HAP 安装受系统限制：三方应用不能静默安装，需引导用户；`executeOhos` 用法见其 README） | 改调用为 `executeOhos()` 分支；安装流程需产品确认 |
| **win32_registry** 2.1.0 | Windows 注册表/深链注册（2 文件） | 否 | ❌（Windows 专属，OHOS 无意义） | 现有守卫已隔离 | 低 | 不动 |
| **dns_client** 1.3.1 | 自定义 DNS（DoH/自建解析） | 是（`dart:io` UDP） | ✅ 纯 Dart 可用（仅需 `INTERNET`） | — | 低 | 不动 |
| **hive_ce / hive_ce_flutter** 2.20.0 / 2.3.4 | 本地 KV/草稿/缓存（5+ 文件） | 是（纯 Dart） | ✅ 依赖 `path_provider_ohos` 即可 | — | 低 | 不动 |
| **jovial_svg / google_fonts / flutter_math_fork / pointycastle / crypto / archive / html / markdown / html2md / zxing2 / qr_flutter / re_highlight / slang / riverpod / visibility_detector / scroll_to_index / popover / emoji_extension / uuid / mime / path / intl / timezone / logging / ffi / vm_service / collection / synchronized / cross_file / http / cookie_jar / dio_cookie_manager / dio_compatibility_layer / ua_client_hints / font_awesome_flutter / material_symbols_icons / chinese_font_library / extended_nested_scroll_view / media_kit_libs_windows_video / media_kit_libs_linux / audioplayers_linux / audioplayers_platform_interface / just_audio_media_kit / video_player_media_kit / just_audio_platform_interface / flutter_inappwebview_linux / flutter_inappwebview_windows | 见 pubspec | 是 | ✅ 纯 Dart 或桌面专属，OHOS 无影响 | — | 低 | 不动（`google_fonts` 在官方清单标"开发中"，但它本质是纯 Dart + path_provider，可用） |

### 1.4 D 组：需要新增的 OHOS 侧原生能力（声明式清单，供 task-2/Lead 排期）

| 能力 | 触发点 | 实现方式 | 优先级 |
|---|---|---|---|
| 时区读取 | `TimeUtils`（全局） | ArkTS MethodChannel：`i18n.System.getSystemTimeZone()` | P0 |
| 通知开关/渠道初始化 | `local_notification_service.dart` | `notificationManager.requestEnableNotification` + fork 插件 | P1 |
| 保存图片到相册 | `image_save_utils.dart` | 换 `saver_gallery`（SaveButton/授权弹窗） | P1 |
| 长时后台任务 | `background_notification_service.dart` | `backgroundTaskManager.startBackgroundRunning` + `KEEP_BACKGROUND_RUNNING`（或暂缓） | P2 |
| AVIF 解码 | `avif_image_provider.dart` | 先禁用；后续 ImageKit | P2 |
| 深链 skills 配置 | `deep_link_service.dart` | module.json5 `skills[].uris` | P1 |
| HAP 更新安装 | `apk_download_service.dart` | ota_update `executeOhos` + 系统安装引导 | P2 |
| 刷新率设置 | `appearance_defs.dart` | `@ohos.display` 或禁用 | P3 |

---

## 2. `pubspec` 改写建议（可执行）

### 2.1 策略选择：双文件（推荐）

现网 `pubspec.yaml` 面向 Android/iOS/macOS/Windows/Linux。OHOS 需要用**更低版本号或社区 fork** 的插件（例如 inappwebview 6.2.0-beta.3 → 6.1.5、file_picker 10.3.10 → 10.3.8、record 7.1.1 → 7.0.x/7.1.x 实现、mobile_scanner 7.4.0 → 7.1.4），若直接写进主 `pubspec.yaml`，会让其他五端的插件版本被动降级。

**做法**：
1. 从 `repo/pubspec.yaml` 派生 `repo/pubspec.ohos.yaml`（内容 = 原文 + 下面 §2.2 的增删）。
2. 加一个切换脚本 `repo/scripts/ohos/use-ohos-pubspec.ps1`：备份 `pubspec.yaml` → 用 `pubspec.ohos.yaml` 覆盖 → `flutter pub get`（`PUB_CACHE`/`GIT_CONFIG_GLOBAL` 见 §2.4），另存 `pubspec.lock.ohos` 便于比对。
3. `pubspec.ohos.yaml` 里**保留**桌面专属依赖（`media_kit_libs_*`、`flutter_inappwebview_linux/windows`、`window_manager` 等），只做"追加 + override"，避免 `pub get` 大范围重解析。

> 快速验证的临时方案（方案 B）：直接在主 `pubspec.yaml` 的 `dependency_overrides` 里加上 §2.2 的 override 块，先打通 `flutter build hap`，验证完再拆成双文件。

### 2.2 `pubspec.ohos.yaml` 差异块（可直接粘贴）

```yaml
# ---- 追加：OHOS 联邦实现（插件的 Dart API 仍来自官方包，这里只是补平台实现）----
dependencies:
  # pub.dev 已有的 OHOS 实现（2026-08 重新发布，dartPluginClass 注册，无需 fork）
  path_provider_ohos: ^2.2.1
  shared_preferences_ohos: ^2.2.0
  url_launcher_ohos: ^6.3.0
  screen_brightness_ohos: ^2.1.4        # 已由 screen_brightness 自动带入，显式声明便于锁版本
  flutter_image_compress_ohos: ^0.0.3+1 # 同上

  # 社区"原生-only"实现（配合官方 Dart API）
  flutter_secure_storage_ohos:
    git: { url: https://github.com/ClosedHarmony/flutter_secure_storage_ohos.git, ref: main }
  record_ohos:
    git: { url: https://github.com/ClosedHarmony/record_ohos.git, ref: main }

  # Wayaer 的实现包（单包多实现，依赖 platform_interface，配合官方 app-facing 包）
  image_picker_harmonyos:
    git: { url: https://github.com/Wayaer/harmony_flutter_packages.git, ref: main, path: image_picker_harmonyos }
  video_player_harmonyos:
    git: { url: https://github.com/Wayaer/harmony_flutter_packages.git, ref: main, path: video_player_harmonyos }
  just_audio_harmonyos:
    git: { url: https://github.com/Wayaer/harmony_flutter_packages.git, ref: main, path: just_audio_harmonyos }
  audio_session_harmonyos:
    git: { url: https://github.com/Wayaer/harmony_flutter_packages.git, ref: main, path: audio_session_harmonyos }
  wakelock_plus_harmonyos:
    git: { url: https://github.com/Wayaer/harmony_flutter_packages.git, ref: main, path: wakelock_plus_harmonyos }

  # 替代实现
  saver_gallery: ^5.1.0        # 替代 gal（仅 OHOS 分支使用；gal 保留给其他端）

dependency_overrides:
  # --- CPF-Flutter 官方 OHOS fork（TAG 规则：<原版本>-ohos-<x.y.z>）---
  device_info_plus:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git, ref: br_device_info_plus-v12.3.0_ohos, path: packages/device_info_plus/device_info_plus }
  connectivity_plus:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git, ref: br_connectivity_plus-v7.0.0_ohos, path: packages/connectivity_plus/connectivity_plus }
  share_plus:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git, ref: br_share_plus-v12.0.1_ohos, path: packages/share_plus/share_plus }
  open_filex:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_open_filex.git, ref: 4.7.0-ohos-1.0.0 }
  file_picker:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_file_picker.git, ref: 10.3.8-ohos-1.0.0 }
  mobile_scanner:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner.git, ref: br_v7.1.4_ohos }
  volume_controller:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_volume_controller.git, ref: br_v3.6.0_ohos_dev }
  app_links:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_app_links.git, ref: br_7.2.2_ohos_dev, path: app_links }
  flutter_local_notifications:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_local_notifications.git, ref: br_3.41_dev, path: flutter_local_notifications }
  sqflite:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_sqflite.git, ref: br_3.41_dev, path: sqflite }
  audio_session:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_audio_session.git, ref: br_v0.2.2_ohos }
  fluttertoast:   # catcher_2 依赖
    git: { url: https://gitcode.com/CPF-Flutter/flutter_fluttertoast.git, ref: br_8.2.8_ohos }

  # --- flutter_inappwebview：必须成组覆盖（app 6.1.5 + PI 1.3.0+1 + ohos 1.1.3）---
  flutter_inappwebview:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git, ref: br_v6.1.5_ohos, path: flutter_inappwebview }
  flutter_inappwebview_platform_interface:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git, ref: br_v6.1.5_ohos, path: flutter_inappwebview_platform_interface }
  flutter_inappwebview_ohos:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git, ref: br_v6.1.5_ohos, path: flutter_inappwebview_ohos }

  # --- 版本必须跟随的补充：package_info_plus 若走 Wayaer 实现则不需要注释掉下面这段 ---
  # package_info_plus:
  #   git: { url: https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git, ref: br_package_info_plus-v9.0.0_ohos, path: packages/package_info_plus/package_info_plus }

  # --- 保留原有 overrides ---
  # device_info_plus: 12.3.0   ← 已被上面的 git override 取代
  flutter_inappwebview_linux:
    path: packages/flutter_inappwebview_linux
  flutter_inappwebview_windows:
    path: packages/flutter_inappwebview_windows
  flutter_rust_bridge: 2.12.0
```

**注意（容易踩的坑）**：
- `flutter_inappwebview` 是**联邦插件**：只覆盖 app-facing 包会导致 `platform_interface` 版本对不上（fork 里是 `1.3.0+1`，pub 上是 `1.4.0-beta.3`），所以必须同时覆盖 `_platform_interface` 与 `_ohos` 三个 path。
- CPF 的 `flutter_secure_storage` fork **不要用**：其 `flutter_secure_storage_platform_interface` 只有 1.1.2，与项目锁定的 2.1.1 冲突。用 ClosedHarmony 的"原生-only"包（官方 10.3.4 Dart API + OHOS 原生插件，通道名一致）。
- `record` / `flutter_secure_storage` 这类"追加实现包"的写法是 **不 override 主包**，只多一条依赖；Flutter 工具会按 `flutter.plugin.platforms.ohos` 自动注册（`tools/flutter/packages/flutter_tools/lib/src/platform_plugins.dart:795` 的 `OhosPlugin`）。
- `chat_bottom_container` 升到 `^0.5.3` 才带 ohos 平台声明（lock 里现在 0.4.1）。
- 若 `package_info_plus` 走 9.x 分支，会与 `wakelock_plus 1.4` 的约束、`win32 5.15.0` 相互牵扯（pubspec 已有注释），建议优先 Wayaer 的 impl 以保持 8.3.1。

### 2.3 需要"移除/条件化"的依赖（不是删包，而是运行时降级）

| 包 | 处理 |
|---|---|
| `flutter_avif`, `flutter_avif_platform_interface` | 保留依赖（其他端仍用）；`lib/services/avif_fast_bridge.dart` 用**条件导入**（`dart.library.io` 不够，需按 `isOhos` 运行期判断 + 不触碰 FFI 符号） |
| `native_animated_image` | 保留依赖；`cached_image.dart`/`sticker_thumbnail_provider.dart` 在 OHOS 分支不注册 native codec |
| `super_clipboard` | 保留依赖；6 处调用收口到一个 `RichClipboard` 门面，OHOS 走纯文本 |
| `flutter_js` | 可保留依赖（不 import 即不注册）；`cook_js_engine_io.dart` 改为 `flutter_qjs` 实现或条件导入 |
| `full_svg_flutter` | 保留；`animated_svg_view.dart` 降级为 jovial_svg |
| `gal` | 保留（其他端）；`image_save_utils.dart` 内 OHOS 走 `saver_gallery` |
| `flutter_displaymode` / `flutter_dynamic_icon_plus` / `window_manager` / `flutter_acrylic` / `screen_retriever` / `win32_registry` / `workmanager` / `ota_update` / `rhttp` | 保留依赖；靠 `Platform` 守卫/超时降级 |

### 2.4 本机 `flutter pub get` 的前置条件（已实测）

```powershell
# 1) pub 缓存：默认 %LOCALAPPDATA%\Pub 在沙箱下被拒（Creation failed, errno = 5）
$env:PUB_CACHE = 'C:\Users\iceblock\fluxdo\.cache\pub'

# 2) gitcode 的 TLS：schannel 报 SEC_E_NO_CREDENTIALS；用全局配置指向本地 gitconfig
#    文件内容： [http]\n\tsslBackend = openssl
$env:GIT_CONFIG_GLOBAL = 'C:\Users\iceblock\fluxdo\.cache\gitconfig'
$env:GIT_CONFIG_SYSTEM = ''

# 3) 之后 flutter pub get / git clone 都走 OpenSSL（已验证 flutter_fluttertoast 可 ls-remote 成功）
```

---

## 3. OHOS 权限清单（`ohos/entry/src/main/module.json5`）

### 3.1 需要声明的权限

| 权限 | 级别 | 授权方式 | 对应功能/插件 | 建议 |
|---|---|---|---|---|
| `ohos.permission.INTERNET` | normal | system_grant | 全部网络（dio/rhttp/webview/图片/日志上报） | **必须**（Flutter 模板已默认写入） |
| `ohos.permission.GET_NETWORK_INFO` | normal | system_grant | `connectivity_plus` 网络状态、VPN 自愈 | **必须** |
| `ohos.permission.CAMERA` | normal | user_grant | `mobile_scanner` 扫码登录、`image_picker` 拍照 | 需要扫码/拍照时 |
| `ohos.permission.MICROPHONE` | normal | user_grant | `record` 语音消息 | 需要语音时 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | normal | system_grant | 长时任务（`flutter_foreground_task` 的替代：后台通知轮询） | 需要后台保活时（配合 `backgroundModes`） |
| `ohos.permission.PUBLISH_AGENT_REMINDER` | normal | system_grant | 代理提醒（定时/提醒类通知）；CPF 的 local_notifications fork 的 module.json5 就声明它（已验证） | 仅当用 agent reminder |
| `ohos.permission.VIBRATE` | normal | system_grant | 触觉反馈 | 可选 |
| `ohos.permission.GET_WIFI_INFO` | normal | system_grant | WiFi 名称/网络诊断 | 可选 |
| `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` | normal | user_grant | 公共 Download 目录直读写 | 可选（**仅 2in1/Tablet 支持，手机无效**；文件导出优先用 file_picker 保存控件） |

### 3.2 **不要声明**的权限（常见 Android 思维陷阱）

| 权限 | 为什么不要 |
|---|---|
| `ohos.permission.READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO` | **受限权限（restricted）**，需 ACL + 特殊审批，普通三方应用拿不到。官方推荐：读用 `PhotoViewPicker`，写用 **SaveButton/授权弹窗**（均**无需权限**）。对应本项目：`image_picker` 走 Picker；`gal` → `saver_gallery`（内部走保存控件） |
| `ohos.permission.READ_PASTEBOARD` | 同为受限权限。前台粘贴走系统剪贴板 UI 无需权限；`super_clipboard` 降级为纯文本后不需要 |
| `ohos.permission.NOTIFICATION_CONTROLLER` | `system_basic`，系统应用专用。三方通知**不需要**声明权限，只需运行期 `notificationManager.requestEnableNotification(context)` 让用户打开开关 |
| `ohos.permission.INSTALL_BUNDLE` | `system_core`，三方无法静默安装 HAP → `ota_update` 需引导用户确认安装 |
| `ohos.permission.READ_MEDIA` / `WRITE_MEDIA` | **API 22 已废弃**，替代方案即上面第 1 行（受限权限/Picker） |

### 3.3 建议的 `module.json5` 片段

```json5
{
  "module": {
    // ... 既有字段 ...
    "requestPermissions": [
      { "name": "ohos.permission.INTERNET" },
      { "name": "ohos.permission.GET_NETWORK_INFO" },
      { "name": "ohos.permission.KEEP_BACKGROUND_RUNNING" },
      {
        "name": "ohos.permission.CAMERA",
        "reason": "$string:reason_camera",
        "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
      },
      {
        "name": "ohos.permission.MICROPHONE",
        "reason": "$string:reason_microphone",
        "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
      }
    ],
    // 后台保活（与 KEEP_BACKGROUND_RUNNING 配套）
    "backgroundModes": ["dataTransfer"],
    "abilities": [
      {
        "name": "EntryAbility",
        "srcEntry": "./ets/entryability/EntryAbility.ets",
        "exported": true,
        "skills": [
          { "entities": ["entity.system.home"], "actions": ["action.system.home"] },
          // 深链：app_links 依赖这些 uris（discourse://、fluxdo://）
          {
            "entities": ["entity.system.browsable"],
            "actions": ["ohos.want.action.viewData"],
            "uris": [
              { "scheme": "fluxdo" },
              { "scheme": "discourse" }
            ]
          }
        ]
      }
    ]
  }
}
```

> `reason`/`usedScene` 里的 `$string:reason_camera` 需在 `entry/src/main/resources/base/element/string.json` 补两条文案；`requestPermissions` 是数组，Flutter OHOS 模板默认只有 INTERNET（见 `tools/flutter/packages/flutter_tools/templates/app/ohos.tmpl/entry/src/main/module.json5`），需要手工补。

---

## 4. 风险排序 + 建议 Lead 的处理顺序

**P0（不通过就无法启动/登录，必须先打通）**
1. 生成 `ohos/` 工程（`flutter create --platforms ohos .`）+ 配置 §2.4 环境（PUB_CACHE / GIT_CONFIG_GLOBAL）→ 跑通 `flutter build hap` 空壳。
2. 基础 8 件套打通：`path_provider_ohos`、`shared_preferences_ohos`、`url_launcher_ohos`、`device_info_plus`、`connectivity_plus`、`flutter_secure_storage_ohos`、`package_info_plus`、`sqflite` —— 目标是 **冷启动到首屏 + 登录态读取**。
3. 在 `lib/` 增加 `isOhos` 判定并把 `Platform.isAndroid||Platform.isIOS` 的关键分支补上 OHOS（§0.6，约 145 处平台判断需要筛，重点在主流程/媒体/存储/通知）。
4. `flutter_timezone` 自写桥（`TimeUtils` 是全局基座，时区错会污染所有时间显示）。

**P1（主功能完整性）**
5. `flutter_inappwebview`（24 文件，OAuth 登录 + 编辑器预览，风险最高，单独排期回归）。
6. `file_picker` / `image_picker` / `share_plus` / `open_filex` / `mobile_scanner` / `record`（编辑器与分享链路）。
7. `video_player` / `just_audio` / `wakelock_plus` / `volume_controller` / `audio_session`（媒体播放链路，需外接纹理实测）。
8. `flutter_local_notifications`（21→22 升级）+ `app_links`（深链 skills 配置）。

**P2（可降级，先保证不崩）**
9. `gal → saver_gallery`、`flutter_js → flutter_qjs`、`flutter_avif` 禁用、`native_animated_image` 回退、`super_clipboard` 降级、`full_svg_flutter` 降级。
10. `rhttp`（已有 forceDisable，确认回落无报错）、`ota_update`（`executeOhos`）、`flutter_foreground_task`（或自写长时任务）、`flutter_displaymode` / `flutter_dynamic_icon_plus` 禁用。

**P3（体验优化）**
11. `flutter_math_fork` / `fluttertoast` 覆盖、`pro_image_editor` 降级路径、刷新率、动态图标。

**Top 5 风险项**
1. 生态最高 Flutter 3.41（CPF 分支）/3.35（官方清单） vs 目标 3.47.7-ohos-0.0.1-canary1 → 所有插件都要在新 har 上重编验证。
2. `flutter_inappwebview` 6.2.0-beta.3 → 6.1.5 降级 + ArkWeb 内核差异（影响登录）。
3. `Platform.operatingSystem == 'ohos'` 导致现有 145 处平台判断全 false（静默功能丢失，非崩溃，最难排查）。
4. 媒体链路（video_player / just_audio / record）的 AVPlayer 行为差异。
5. 权限模型差异（媒体库/剪贴板/通知/安装）——用 Android 的权限写法会直接申请失败。

---

## 5. 附录：证据与复现

### 5.1 关键来源

| 来源 | 用途 |
|---|---|
| <https://raw.gitcode.com/OpenHarmony-Flutter/docs/raw/main/ThirdpartyLibrarites.md> | 官方适配清单（已下载 411 行，仅标到 Flutter 3.35） |
| <https://gitcode.com/api/v5/repos/CPF-Flutter/<repo>/branches> | 匿名可用，返回分支 + 最后提交时间（用于判断 fork 活跃度） |
| <https://raw.gitcode.com/CPF-Flutter/<repo>/raw/<ref>/<path>> | 直接读 fork 的 pubspec / module.json5，无需 clone |
| <https://pub.dev/api/packages/<name>> | 包的 platforms 声明、`*_ohos` 依赖、发布时间 |
| `https://raw.githubusercontent.com/ClosedHarmony/...` | ClosedHarmony 组织（25 个仓库，最近推送 2026-10-17）：secure_storage / record / inappwebview 等 |
| `https://raw.githubusercontent.com/Wayaer/harmony_flutter_packages/...` | 18 个 `*_harmonyos` 实现（Flutter ≥3.27，2025-11 最后更新） |
| 本地 SDK `tools/flutter`：`packages/flutter/lib/src/foundation/_platform_io.dart:28`、`packages/flutter_tools/lib/src/platform_plugins.dart:795`、`templates/app/ohos.tmpl/entry/src/main/module.json5` | `TargetPlatform.ohos` 判定、`OhosPlugin` 平台声明规则、权限模板 |
| `https://raw.gitcode.com/openharmony/docs/raw/master/zh-cn/application-dev/security/AccessToken/*.md` | 权限级别/授权方式/受限权限（READ_IMAGEVIDEO 等）的权威依据 |

### 5.2 已执行的验证命令（可复现）

```powershell
# fork 是否存在 + 分支/TAG（必须带 sslBackend=openssl，或设置 GIT_CONFIG_GLOBAL）
git -c http.sslBackend=openssl ls-remote --heads https://gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner.git
# pub.dev 是否已发布 *_ohos 实现
node -e "fetch('https://pub.dev/api/packages/path_provider_ohos').then(r=>r.json()).then(j=>console.log(j.latest.version))"
# fork 的 pubspec（版本/平台声明）
#   https://raw.gitcode.com/CPF-Flutter/flutter_plus_plugins/raw/br_device_info_plus-v12.3.0_ohos/packages/device_info_plus/device_info_plus/pubspec.yaml
```

### 5.3 待构建期确认（本机无法静态验证）

- 各 CPF fork 的 `ohos/` ArkTS 代码是否兼容 3.47.7 的 `@ohos/flutter_ohos` har（`checkOhosPluginsDependencies` 会把依赖改写成本地 `har/flutter.har`，pubspec 里的 har 版本号不生效，但仍然依赖 ArkTS 插件 API 兼容）。
- `video_player_harmonyos` / `just_audio_harmonyos` 在 3.47 上的纹理与播放行为。
- `flutter_inappwebview_ohos 1.1.3` 与项目 24 处调用（cookie 同步 `enhanced_cookie_jar`、`evaluateJavascript`、`addJavaScriptHandler`）的兼容性。
- `pro_image_editor` / `flutter_math_fork` / `google_fonts` 在 OHOS 上的实际渲染表现。
- `saver_gallery 5.1.0` 要求 Flutter ≥3.44（目标 3.47.7 ✓），但需确认其 `ohos/` 用的是 SaveButton 还是受限权限。

