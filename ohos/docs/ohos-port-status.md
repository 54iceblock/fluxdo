# FluxDO → HarmonyOS 7 移植状态（Lead 汇总）
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从应用侧 `module.json5` 删除（最终包仍由依赖 HAR 带入，见 README.md）。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 更新时间：2026-10-21；目标平台：HarmonyOS 7.0.0（API 26，DevEco Studio 26.0，模拟器 x86_64）
> Flutter：3.47.7+ohos-0.0.1-pre（`tools/flutter`，Dart 3.13.5，分支 `oh-3.47.7-preview`）

## 1. 已打通（有实测证据）

| 环节 | 结果 | 证据 |
|---|---|---|
| Flutter OHOS 工具链 | ✅ | `flutter doctor` HarmonyOS toolchain OK；`tools/env.ps1` 一键环境 |
| hvigor 构建 | ✅ | `tools/build-ohos.ps1`；junction 兜底补丁 `tools/node-symlink-fallback.js` |
| HAP 签名（无需华为账号） | ✅ | `tools/ohos-sign.ps1`（OpenHarmony 默认证书链 + 按 bundle 生成 profile） |
| 模拟器安装/启动 | ✅ | `hdc install` → `install bundle successfully`；`aa start` 成功 |
| FluxDO 启动渲染 | ✅ | 截图 `.cache/fluxdo-shot1.jpeg`（登录页）、`fluxdo-shot2.jpeg` |
| 插件原生编译 | ✅ | 25 个 OHOS 插件模块（path_provider/shared_preferences/url_launcher/secure_storage/record/video_player/just_audio/wakelock/inappwebview/local_notifications/sqflite/app_links/ota/mobile_scanner/open_filex/volume_controller/saver_gallery/image_picker/package_info/screen_brightness/flutter_image_compress…） |
| Dart 编译 | ✅ | `dart analyze lib` 0 error；kernel 编译通过 |
| 游客模式进入主界面 | ✅ | 截图 `.cache/fluxdo-shot3.jpeg`（话题页错误态，见下） |

## 2. Cloudflare 403 —— 已解决（task-7 两轮修复）

**根因（cf-fix 从插件源码定位）**：`flutter_inappwebview_ohos` 的 `onNavigationResponse` 是在主文档请求**发出前**合成的假回调（`statusCode` 恒 200、`headers` 恒空），导致 `cf_challenge_service` 把「/challenge 导航」误判为「已到达源站、无盾」，立刻结束验证并 cancel+reload —— **CF 挑战从未真正执行**，所以 ArkWeb 里自然没有 cf_clearance。

**修复**：
1. OHOS 上关闭 `useOnNavigationResponse`/`useShouldOverrideUrlLoading`，让 ArkWeb 像真浏览器自己跑完挑战；回调里 OHOS 直接 ALLOW；加入 pageReady/loadStop 定时兜底。
2. 放宽 OHOS 的 WebView 网络栈可用条件（原先排除 HTML/非 XHR GET，而失败请求正是首页 `GET https://linux.do/`），并在重试仍 403 时自动切浏览器栈重放。
3. 诊断打点：`[CfChallenge][OHOS]`、`[CookieStrategy][OHOS]`、`[BoundarySync][OHOS]`、`[Dio][OHOS]`。

**验证证据**：
- `.cache/fluxdo-shot5.jpeg`：CF「安全验证」页在 ArkWeb 内真正运行（Powered by Cloudflare）。
- `.cache/fluxdo-shot8.jpeg`：**游客话题列表加载成功**（标题/作者/头像/分类/标签/回复数/相对时间/底部导航）。
- `.cache/fluxdo-shot9.jpeg`：**话题详情页渲染成功**（正文 HTML、折叠块、楼层 #1、1/4 分页、作者卡、「7小时前」）。

**备注**：ArkWeb cookie store 仍读不到 HttpOnly 的 `cf_clearance`（API 26 `WebCookieManager` 无属性查询接口），所以最终走的是「WebView 网络栈重放」路径；这条路径是达标的（数据正常）。

## 3. 已做的 lib 适配（Lead）

- `lib/utils/platform_utils.dart`：新增 `isOhos`；`isMobile` 纳入 OHOS。
- `lib/utils/ohos_compat.dart`（新）：OHOS 能力开关（doh/rhttp/cookJs/avif/native animated/rich clipboard/desktop window/camera scanner/gallery/background/in-app update）。
- `lib/main.dart`：just_audio 后端仅在桌面注册；本地通知初始化 try/catch；rhttp 在 OHOS 直接 `forceDisable()`。
- 图片链路：`discourse_cache_manager.dart`、`cached_image.dart`、`sticker_thumbnail_provider.dart`、`image_viewer_page.dart` 在 OHOS 回退引擎内建解码（无 flutter_avif / native_animated_image 原生库）。
- `lib/services/cook/cook_js_engine_io.dart`：`cookJsSupported` 在 OHOS 为 false（无 QuickJS），自动降级 Dart 预览。
- `lib/utils/image_save_utils.dart`：OHOS 优先 saver_gallery，失败回落文件保存/分享。
- `lib/utils/clipboard_utils.dart`（新，ohos-bridges）：OHOS 富剪贴板降级纯文本。
- `lib/utils/time_utils.dart` + `ohos/entry/src/main/ets/plugins/FluxdoBridgePlugin.ets`：时区 ArkTS 桥（`i18n.getTimeZone().getID()`）。
- `lib/services/local_notification_service.dart`：补 `OhosInitializationSettings` + OHOS 权限请求。
- `lib/services/apk_download_service.dart`、`lib/pages/webview_page.dart`、`lib/services/webview_settings.dart`：对齐 inappwebview 6.1.5 / ota 7.0.2 的 API 差异。
- `lib/constants.dart`：OHOS 移动端 UA。

## 4. 依赖层（pubspec-ohos）

- 新增 12 个 OHOS 实现包（pub.dev 联邦实现 + Wayaer/ClosedHarmony 实现 + saver_gallery）。
- 12 条 git override（device_info_plus / connectivity_plus / open_filex / mobile_scanner / volume_controller / app_links / flutter_local_notifications / sqflite / inappwebview(+PI) / ota_update / flutter_secure_storage_ohos / record_ohos）。
- vendored 本地修复：`packages/flutter_math_fork`（补 `TargetPlatform.ohos` 分支）、`packages/just_audio_harmonyos`（补 API 26 `enableOfflineCache()/getID()`）。
- 移除 `flutter_inappwebview_windows/_linux` 的 path override（6.2.0-beta.3 版与 6.1.5 平台接口冲突）。

## 5. OHOS 上仍不可用 / 已降级（需后续专项）

| 能力 | 现状 | 计划 |
|---|---|---|
| DOH 代理（Rust） | 禁用，走系统 DNS | P1：Rust 交叉编译 `aarch64-unknown-linux-ohos`（见 docs/ohos-native-strategy.md） |
| rhttp（Rust TLS 指纹） | 强制关闭，回落 dio | P2：vendored FRB 补 ohos 加载器 |
| cook JS 1:1 预览 | 降级 Dart 近似预览 | P2：换 fluttertpc_flutter_qjs |
| AVIF / 动图解码 | 回退引擎解码 | P2 |
| 富文本剪贴板 super_clipboard | 待加纯文本兜底 | P1 |
| 保存到相册 | 走文件保存（saver_gallery 已入依赖，待接线） | P1 |
| 时区（flutter_timezone） | 回退 UTC → **时间显示会偏** | P0：ArkTS `i18n.System.getSystemTimeZone()` 桥 |
| 后台保活 / 后台通知 | 仅前台 | P2：长时任务 |
| 相机扫码 | 相册 + zxing2 兜底 | P2 |
| 应用内更新安装 | 禁用（HAP 不能静默装） | 引导跳应用市场 |

## 6. 复现命令

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
# 构建 + 签名 + 安装 + 启动（Lead 需 danger-full-access，沙箱禁止子进程）
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1 -Install -Launch
# 只构建
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1
# 截图
hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/x.jpeg
hdc -t 127.0.0.1:5555 file recv /data/local/tmp/x.jpeg .\x.jpeg
```

## 7. 关键坑（已解决，勿重踩）

1. 子代理沙箱禁止 Dart 创建带管道的子进程 → flutter/hvigor/签名/安装**必须由 Lead 在 `danger-full-access` 下执行**。
2. hvigor 用 symlink → `NODE_OPTIONS=--require tools/node-symlink-fallback.js` 降级 junction。
3. `compatibleSdkVersion/targetSdkVersion` 在 API 26 必须是 `"26.0.0"`。
4. hvigor 拒绝明文签名密码（要求 ≥32 字符密文）→ `signingConfigs: []` + 构建后手工签名。
5. `module.json5` 的 `backgroundModes` 不能放在 module 根（schema 校验失败）。
6. 脚本文件含中文必须 UTF-8 **BOM**（否则 Windows PowerShell 按 GBK 解析报语法错）。
7. PowerShell `Get-Content -Raw` + `Set-Content` 处理含中文的 Dart 文件会破坏编码 → 只用 edit 工具改 Dart。
8. `assets/certs/` 目录缺失会让 flutter 资源打包失败 → 已补 `.gitkeep`。
9. 子模块 `packages/fluxdo_render`、`core/doh_proxy` 必须先 `git submodule update --init`。
10. git 需 `core.longpaths=true` + `http.sslBackend=openssl`（`.home/.gitconfig`）。
