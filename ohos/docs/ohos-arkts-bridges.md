# FluxDO × HarmonyOS 7：ArkTS 原生能力桥（task-8 交付）

> 执行者：ohos-bridges（task-8）；时间：2026-10-21。
> 目标平台：HarmonyOS 7 / API 26（DevEco Studio 26，模拟器 x86_64）。
> 相关文档：`docs/ohos-port-status.md`（总状态）、`docs/ohos-build-notes.md`（构建/签名/安装命令）。
>
> **重要**：本任务的执行环境（子代理沙箱）**不能构建、不能运行** Flutter/HAP。因此本文所有
> "已实现" 指代码落地 + 静态校验通过；"待 Lead 验证" 指必须在完整权限会话里跑构建/装机的部分。
> 静态校验结论见 §1。

---

## 0. 一句话结论

| 能力 | 优先级 | 代码状态 | 需要 Lead 额外配置 | 预期效果 |
|---|---|---|---|---|
| 时区 | P0 | ✅ ArkTS 桥 + Dart 接入 | 无（无需权限） | `TimeUtils.localTimezone` = 真实 IANA 名，不再恒为 UTC |
| 保存到相册 | P1 | ✅ 优先 saver_gallery | 无（走系统保存确认框，不需要 READ_IMAGEVIDEO） | 弹系统「保存到相册」框，成功入图库；失败回落文件保存 |
| 剪贴板兜底 | P1 | ✅ 4/6 调用点已改（2 处 pages 超出本任务写入范围，见 §4.3） | 无 | OHOS 上不再因 super_clipboard 抛异常；图片复制降级为复制链接 |
| 本地通知 | P1 | ✅ 补 `OhosInitializationSettings` + 权限请求 + OHOS 渠道参数 | `PUBLISH_AGENT_REMINDER` 已在 module.json5 | 初始化不再抛 ArgumentError；首次启动弹通知授权；通知可发布/点击跳转 |
| 深链 | P1 | ✅ Dart 侧加冷启动重试与错误兜底（app_links fork 已负责 want） | `fluxdo://`/`discourse://` 已在 module.json5 | 冷启动/热启动都能取到 URI 并跳页 |

---

## 1. 本任务做了哪些改动

### 1.1 ArkTS 侧（`repo/ohos/entry/src/main/ets/`）

| 文件 | 说明 |
|---|---|
| `plugins/FluxdoBridgePlugin.ets`（**新增**） | 自研 OHOS 桥插件，注册 3 条 MethodChannel（见 §2.1），当前实现时区相关方法 |
| `entryability/EntryAbility.ets`（修改） | `configureFlutterEngine()` 里 `GeneratedPluginRegistrant.registerWith()` 之后，手动 `flutterEngine.getPlugins()?.add(new FluxdoBridgePlugin())` |

> 为什么不在 `GeneratedPluginRegistrant.ets` 里注册：该文件是 **flutter 工具每次构建重新生成**的
> gitignore 文件，手改会被覆盖。EntryAbility.ets 是工程模板文件，不会被构建流程覆盖。

### 1.2 Dart 侧

| 文件 | 改动 |
|---|---|
| `lib/utils/time_utils.dart` | 新增 `com.fluxdo/ohos` 时区桥调用；OHOS 优先桥、失败退 `flutter_timezone`、最后 UTC（§2） |
| `lib/utils/image_save_utils.dart` | OHOS 分支改为「saver_gallery → 失败回落 Documents 文件保存」；动作文案改回「保存到相册」（§3） |
| `lib/utils/clipboard_utils.dart`（**新增**） | 统一剪贴板出口：`copyText` / `copyPngImage`（按平台能力降级），OHOS 上不触碰 `SystemClipboard`（§4） |
| `lib/widgets/common/image_context_menu.dart` | 「复制图片」改走 `ClipboardUtils.copyPngImage`，OHOS 降级复制图片链接 |
| `lib/widgets/share/ai_share_image_preview.dart` | 「复制截图」改走 `ClipboardUtils.copyPngImage`，OHOS 明确提示剪贴板不可用（不崩） |
| `lib/widgets/markdown_editor/markdown_toolbar.dart` | `clipboardHasImage()` / `pasteImageFromClipboard()` 在 OHOS 直接返回 false（读图粘贴降级为纯文本粘贴） |
| `lib/widgets/markdown_editor/rich_composer/rich_composer_editor.dart` | `_importRichPaste()` 在 OHOS 直接返回 false（富文本粘贴降级为纯文本粘贴） |
| `lib/services/local_notification_service.dart` | OHOS 初始化参数、权限请求、通知渠道参数；OHOS 跳过 APK 进度通知（§5） |
| `lib/services/deep_link_service.dart` | 冷启动链接在 OHOS 上短重试 + 事件流错误兜底（§6） |

### 1.3 静态校验（本机已验证，非构建）

本机沙箱禁止 Dart 的 `dart analyze`（它会 spawn `analysis_server` 子进程，报
`CreateFile failed 5`）。改用 **进程内 analyzer 脚本**（`package:analyzer` 13.3.0，
临时脚本放在 `.tmp/ohos_analyze/check.dart`，不进 repo）对 `repo/lib` 全量 848 个
dart 文件做了分析：

```
analyzed 848 target(s) in 56209ms: errors=0 warnings=1 infos=1
WARN lib/utils/ohos_compat.dart:3 unused_import: Unused import: 'package:flutter/foundation.dart'.
INFO lib/widgets/auth/qr_login_sheet.dart:552 todo: ...
```

- `errors=0`：本任务改动（含新文件）**无编译错误**。
- 唯一 warning 是既有 `lib/utils/ohos_compat.dart` 的无用 import（task-5 文件，不属本任务，未动）。
- ArkTS 无法在本机编译（见 §8），但用 DevEco 自带的 TypeScript 解析器做了 **语法检查**：
  `FluxdoBridgePlugin.ets` / `EntryAbility.ets` 均 `0 parse diagnostic(s)`；
  符号级（API 存在性/签名）已按 API 26 SDK 的 d.ts 逐个核对，见 §8。

---

## 2. P0 时区桥（重点）

### 2.1 实现位置

**ArkTS**：`repo/ohos/entry/src/main/ets/plugins/FluxdoBridgePlugin.ets`

同时注册三条通道，全部由同一个 handler 应答：

| 通道名 | 谁在用 | 方法 |
|---|---|---|
| `com.fluxdo/ohos` | 自研业务通道：`lib/utils/time_utils.dart` 显式调用 | `getLocalTimezone` / `getAvailableTimezones` / `getSystemLocale` |
| `flutter_timezone` | **flutter_timezone 5.1.1 的实际通道名**（`.pub-cache/hosted/.../flutter_timezone-5.1.1/lib/flutter_timezone.dart:12`），桥顶替它的原生端，于是 `FlutterTimezone.getLocalTimezone()` 在 OHOS 直接可用 | 同上 |
| `plugins.jonasroesner.dev/flutter_timezone` | 任务书里写的历史通道名（部分 5.x 文档/旧版）。**实测 5.1.1 不用它**，但一并应答防版本漂移 | 同上 |

> 任务书里写的通道名与本仓库实际解析到的 flutter_timezone 版本不一致，这里**两个都注册**，
> 两种来源（自研桥 / 包自带 Dart API）都能拿到真实时区。

**Dart**：`lib/utils/time_utils.dart`

解析链（`initialize()` → `_resolveLocalTimezoneName()`）：

1. 仅 OHOS：调 `com.fluxdo/ohos#getLocalTimezone`，拿到名字后用 `tz.getLocation()` 校验；
   成功即 `tz.setLocalLocation(...)` 并写 `_localTimezone`。
2. 桥未注册 / 调用失败 / 名字不在 tz 数据库：退回 `FlutterTimezone.getLocalTimezone()`
   （其 `flutter_timezone` 通道同样由上面的 ArkTS 桥应答）。
3. 仍失败：沿用原逻辑回退 `UTC`，只打日志不抛异常。
4. **非 OHOS 平台逻辑不变**：直接 `FlutterTimezone.getLocalTimezone()`。

### 2.2 为什么不是 `i18n.System.getSystemTimeZone()`

任务书要求用 `i18n.System.getSystemTimeZone()`，但 **API 26 SDK 里没有这个方法**：

```text
D:\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.i18n.d.ts
  export class System { ... }   // 无 getSystemTimeZone / getTimeZone
  export function getTimeZone(zoneID?: string): TimeZone;   // 不传参 = 系统时区
  class TimeZone { getID(): string; ... }
  System.getAppDefaultTimeZone(): TimeZone                   // since 12
```

所以 ArkTS 侧用官方等效写法：

```ets
const systemZone: i18n.TimeZone = i18n.getTimeZone(); // 默认值即系统时区
const id: string = systemZone.getID();                // 例："Asia/Shanghai"
```

回退链：`i18n.getTimeZone().getID()` → `i18n.System.getAppDefaultTimeZone().getID()` → `"UTC"`。
每个失败点都打 hilog（TAG `FluxdoBridge`）。

### 2.3 Lead 需要跑什么（构建/安装）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
cd C:\Users\iceblock\fluxdo
.\tools\build-ohos.ps1 -Install -Launch        # 构建→签名→安装→启动（完整权限会话）
```

**首次构建要重点看 hvigor ArkTS 编译结果**（本任务改了两个 ets 文件、新增一个 ets 文件）：

- 若报 `'i18n' has no exported member ...` / 找不到 `@ohos.i18n`：检查 `FluxdoBridgePlugin.ets` 的
  import 是否被格式化工具改坏；SDK 里该模块在，正常不会失败。
- 若报 `FluxdoBridgePlugin` 相关类型错误：常见原因是 `MethodChannel` / `MethodCall` / `MethodResult`
  没有从 `'@ohos/flutter_ohos'` 导出 —— 已核对 SDK har 的 `index.ets` 有导出（`export *` /
  `export { default as MethodChannel }`）。
- 若报入口注册相关错误：替换方案是在 `EntryAbility.ets` 里直接建通道（不写插件类）：
  ```ets
  const channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), 'com.fluxdo/ohos');
  channel.setMethodCallHandler({ onMethodCall: (call, result) => { /* 同 FluxdoBridgePlugin */ } });
  ```
  （不推荐，仅兜底。）

### 2.4 Lead 看什么日志 / 界面

> **实测提示（2026-10-21/22 模拟器）**：Dart 侧 `debugPrint` **不会**出现在 `hilog` 里
> （当前运行中的旧版 App 日志里找不到已知的 `[Dio]` / `[TimeUtils]` 字符串，hilog 里只有
> 引擎的 `A000ff/Flutter` 原生日志）。因此本任务把关键证据都放在 **ArkTS 侧 hilog**（一定可见）
> 和 **MethodChannel 流量日志**（引擎 D 级）上；Dart 日志请用 `flutter run --debug` 的主机
> stdout 或 `flutter attach` 看。模拟器当前系统时间 `date` = `CST`（UTC+8），所以预期时区是
> **`Asia/Shanghai`**。

启动后抓日志：

```powershell
$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell hilog -r     # 清空
& $hdc -t 127.0.0.1:5555 shell aa force-stop com.fluxdo.app
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.app
Start-Sleep -Seconds 12
& $hdc -t 127.0.0.1:5555 shell hilog -x | Select-String -Pattern 'FluxdoBridge|com.fluxdo/ohos'
```

**期望日志（任一条都算桥通）：**

```
... I 0F1D/FluxdoBridge: bridge attached, 3 channels, localTimezone=Asia/Shanghai
... D A000ff/Flutter: DartMessenger --> Received message from Dart over channel 'com.fluxdo/ohos'
```

（第一条是 ArkTS 桥自身；第二条是 Dart `TimeUtils.initialize()` 真的调用了自研通道。）
`FluxdoBridgePlugin registered` 是 EntryAbility 注册成功的确认（`0F1D/EntryAbility`）。

**失败日志对照：**

| 日志 | 含义 | 处理 |
|---|---|---|
| 无 `FluxdoBridgePlugin registered` / 无 `bridge attached` | ArkTS 插件没注册上 | 查 hvigor 是否把 `EntryAbility.ets` 覆盖；查构建日志里 EntryAbility 的 ArkTS 编译错误 |
| `bridge attached ... localTimezone=UTC` | 桥通了，但系统时区解析为 UTC 或 i18n 全失败 | 看同 tag 的 `i18n.getTimeZone failed` / `getAppDefaultTimeZone failed` 警告 |
| 有 `Received message ... 'com.fluxdo/ohos'` 但 `localTimezone=` 行缺失 | 桥注册语句没执行到（EntryAbility 注册块被跳过） | 查 `FluxdoBridgePlugin register failed` 错误行 |
| Dart `[TimeUtils]` 仅在 `flutter run` 里可见 | 桥未注册会打 `OHOS 时区桥未注册` / 最终 `回退 UTC` | 用 `flutter run --debug` 观察 |

**界面验证（最直观）：** 打开任意话题，帖子的「X 分钟前 / 具体时间」应正确；发帖页「日期」
工具的时区一栏默认值（写进 BBCode 的 `timezone="..."`）应为 `Asia/Shanghai` 而不是 `UTC`。

### 2.5 已知限制（时区）

1. **`TimeUtils.localTimezone` ≠ 所有时间显示**：`parseUtcTime()` 里用的还是
   `DateTime.toLocal()`（Dart VM 的本地时区）。本桥修正的是「插件拿不到时区」这条链路
   （`local_date_builder`、聊天 BBCode 的 `timezone=`、以及任何读 `TimeUtils.localTimezone` 的地方）。
   如果 Lead 在模拟器上仍看到时间整体偏移，请先确认模拟器系统时区（见 §2.4 表最后一行）；
   若系统时区正确但 `toLocal()` 仍偏，那是 **Dart VM/引擎层的 OHOS 时区实现**问题，需要单独排查
   （不在本任务范围，可在 `parseUtcTime` 加兜底，属后续专项）。
2. HarmonyOS 返回的可能是 tz 数据库的别名（如 `Asia/Chongqing`、`PRC`）。`latest_all` 里都
   包含这些 link，`tz.getLocation()` 能解析；若某个别名不在库里，Dart 会走第 2 级回退
   （`flutter_timezone` API，同一个桥应答，结果相同）→ 最终 UTC。遇到时把 hilog 里的
   `localTimezone=` 值发给移值负责人加映射即可。
3. 未处理「系统时区运行期变化」：App 启动后修改系统时区不会热更新 `TimeUtils`（Android 侧
   也没有），需重启 App。

---

## 3. P1 保存到相册

### 3.1 实现位置

`lib/utils/image_save_utils.dart`

```
saveBytes()
 └─ PlatformUtils.isOhos → _saveToOhosGallery()
      ├─ SaverGallery.saveImage(bytes, fileName: <真实名.扩展名>, skipIfExists: false)
      │    成功：Toast「图片已保存」并 return true
      │    失败/异常（含用户在系统弹框取消）：debugPrint 后回落
      └─ _saveToOhosFile()
           写入 getApplicationDocumentsDirectory()/SavedImages/<name>
           Toast「文件已保存」；debugPrint 打印完整路径
```

- **为什么不用 gal**：`gal` 没有 OHOS 实现（`MissingPluginException`），原代码因此在 OHOS 上
  退回 `_saveAsFile()` → `ShareUtils.saveFile()` → file_picker/share_plus，而这两个包也没有
  OHOS 实现，等于「保存必失败」。现在主路径是 saver_gallery。
- **saver_gallery OHOS 实现**（`.pub-cache/hosted/.../saver_gallery-5.1.0/ohos/.../SaverGalleryPlugin.ets`）：
  走 `photoAccessHelper.showAssetsCreationDialog()` —— 系统弹「保存到相册」确认框，**不需要**
  `ohos.permission.READ_IMAGEVIDEO/WRITE_IMAGEVIDEO`，也不需要运行时申请媒体库权限。
  文件先从 Flutter 传入的 bytes 落到 App 缓存（`cacheDir/image_source.jpg`），再拷进用户确认的
  媒体库 URI；`quality > 0 && extension != gif` 时还会用 ImagePacker 重新编码。
- OHOS 上 `ImageSaveUtils.actionLabel` 改为「保存到相册」（原来是「保存图片」）。
  所有入口（图片查看器、图片长按菜单、AI 分享图预览等）都走同一个 `saveBytes`，只改这一处即可。

### 3.2 Lead 验证步骤

1. `.\tools\build-ohos.ps1 -Install -Launch`（无新权限、无 pubspec 改动）。
2. 进入任意话题 → 点开一张图片 → 菜单「保存到相册」。
3. **期望**：弹出系统「保存到相册 / 是否允许 FluxDO 保存图片」确认框 → 确认 → Toast
   「图片已保存」；打开系统「图库」能在「图片」里看到该图。
4. 抓日志：
   ```powershell
   & $hdc -t 127.0.0.1:5555 shell hilog -x | Select-String -Pattern 'ImageSaveUtils|saver_gallery|ImageGallerySaverPlugin'
   ```
   - 成功：`[ImageSaveUtils]` 无失败行 + saver_gallery TAG 无 error。
   - 失败回落：`[ImageSaveUtils] OHOS saver_gallery 失败，回落文件保存: save failed, errCode is ...`
     随后 `[ImageSaveUtils] OHOS 图片已写入文件: /data/storage/el2/base/.../SavedImages/xxx.png`，
     界面 Toast「文件已保存」。此时可在「文件管理 → 应用 → FluxDO」找到 `SavedImages/`（不同
     版本文件管理器入口略有差异，也可能只在应用沙箱内可见）。

### 3.3 已知限制（相册）

1. 用户在系统保存框点取消 → 按失败处理，会再走文件保存（这是我们选的「至少留一份」策略）；
   若希望「取消就静默返回」，需要在 saver_gallery 的错误文案里区分 `errCode`（当前版本
   `SaveResult.errorMessage` 只有字符串，暂不做字符串匹配）。
2. `share_plus` / `file_picker` 无 OHOS 实现 → **「分享图片」按钮在 OHOS 上仍会失败**
   （`ScreenshotUtils.shareImage` → `SharePlus.instance.share`）；这是既有问题，不在本任务范围。
   保存路径已不依赖它们。
3. AVIF/动图：saver_gallery 对 `gif` 与 `quality=100` 走原始字节复制（我们传默认 quality=100），
   动画帧不丢；但扩展名以 `_resolveFileName` 按文件头识别为准（avif/gif/webp 已覆盖）。

---

## 4. P1 剪贴板兜底（super_clipboard 无 OHOS 实现）

### 4.1 根因

`super_clipboard` → `super_native_extensions` 的原生初始化在 Dart 侧是：

```dart
// super_native_extensions-0.9.1/lib/src/native/context.dart
final dylib = Platform.isAndroid ? DynamicLibrary.open("libsuper_native_extensions.so")
    : (Platform.isWindows ? DynamicLibrary.open("super_native_extensions.dll")
    : DynamicLibrary.process());
dylib.lookup("super_native_extensions_init_message_channel_context");   // ← OHOS 无此符号
```

OHOS 既不是 Android 也不是 Windows，走 `DynamicLibrary.process()` + 查符号 → **抛异常**。
而且它是在 `SystemClipboard.instance` getter 里（`raw.ClipboardReader.instance`）就会触发，
所以 **不能在 OHOS 上先取 instance 再判空**，必须先看能力开关。

### 4.2 统一出口：`lib/utils/clipboard_utils.dart`

```dart
ClipboardUtils.supportsRichClipboard  // = OhosCompat.supportsRichClipboard（OHOS=false）
ClipboardUtils.copyText(text)         // 全平台：Clipboard.setData(ClipboardData(text:))，纯 Flutter，不依赖插件
ClipboardUtils.copyPngImage(bytes, {fallbackText}) // 支持富剪贴板的平台走 super_clipboard；
                                                   // 否则（OHOS）有 fallbackText 就复制文本，返回 false
```

### 4.3 6 个调用点状态

| # | 文件 | 处理方式 | 状态 |
|---|---|---|---|
| 1 | `lib/widgets/common/image_context_menu.dart`（`_copyImage`） | 走 `ClipboardUtils.copyPngImage(..., fallbackText: imageUrl)`；OHOS 复制图片链接并提示「链接已复制」 | ✅ 本次已改 |
| 2 | `lib/widgets/share/ai_share_image_preview.dart`（`_copyImage`） | 截图没有可降级文本 → OHOS 提示「剪贴板不可用」，不崩 | ✅ 本次已改 |
| 3 | `lib/widgets/markdown_editor/markdown_toolbar.dart`（`clipboardHasImage` / `pasteImageFromClipboard`） | OHOS 直接返回 false → 粘贴图片降级为 TextField 纯文本粘贴 | ✅ 本次已改 |
| 4 | `lib/widgets/markdown_editor/rich_composer/rich_composer_editor.dart`（`_importRichPaste`） | OHOS 直接返回 false → 富文本粘贴降级为纯文本粘贴 | ✅ 本次已改 |
| 5 | `lib/pages/image_viewer_page.dart`（`_copyMemoryImage`，约 L808） | **超出本任务写入范围（repo/lib/pages/**）**，需 Lead/task-5 套用 §4.4 patch | ⏳ 待改 |
| 6 | `lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart`（`_copyImageAttachment`，约 L392） | 同上 | ⏳ 待改 |

> 5/6 两处当前都在 `try/catch` 里，所以 **不会崩**，只是会弹「复制失败」；套用 patch 后
> 可降级成「复制链接 / 提示不可用」。两处都不在 task-8 允许的写入范围（`repo/lib/widgets/**`
> 与 `repo/lib/pages/**` 之别），故留 patch 给 Lead 合并。

### 4.4 给 Lead 的两处 patch（可直接套用）

**A. `lib/pages/image_viewer_page.dart`**

1) import 区加：
```dart
import '../utils/clipboard_utils.dart';
```
2) `_copyMemoryImage()` 方法体替换为（保留原 try/catch 结构即可）：
```dart
  Future<void> _copyMemoryImage() async {
    final bytes = widget.imageBytes;
    if (bytes == null || bytes.isEmpty) return;
    try {
      // OHOS：super_clipboard 无原生实现，走 ClipboardUtils 降级（无文本可复制 → 提示不可用）
      final copied = await ClipboardUtils.copyPngImage(bytes);
      if (!mounted) return;
      if (copied) {
        ToastService.showSuccess(S.current.image_copied);
      } else {
        ToastService.showError(S.current.common_clipboardUnavailable);
      }
    } catch (e) {
      debugPrint('[ImageViewerPage] copyMemoryImage error: $e');
      if (mounted) ToastService.showError(S.current.image_copyFailed);
    }
  }
```

**B. `lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart`**

1) import 区加（相对路径按该文件位置调整）：
```dart
import '../../../utils/clipboard_utils.dart';
```
2) `_copyImageAttachment()` 的 try 块替换为：
```dart
    try {
      final copied = await ClipboardUtils.copyPngImage(bytes);
      if (!context.mounted) return;
      if (copied) {
        ToastService.showSuccess(context.l10n.ai_imageCopied);
      } else {
        ToastService.showError(context.l10n.ai_imageCopyFailed);
      }
    } catch (e) {
      debugPrint('[AiChatMessageItem] copyImage error: $e');
      if (context.mounted) {
        ToastService.showError(context.l10n.ai_imageCopyFailed);
      }
    }
```
（两处完成后可以删除文件里已不再使用的 `package:super_clipboard` import。）

### 4.5 Lead 验证步骤

1. 图片长按菜单 →「复制图片」：OHOS 期望 Toast「链接已复制」（不是「复制失败」），
   然后到输入框粘贴应得到图片 URL 文本。
2. 富文本编辑器（发帖页「富文本」模式）里 Ctrl+V / 长按粘贴：纯文本能粘贴，**无崩溃**。
3. 抓日志确认没有插件异常：
   ```powershell
   & $hdc -t 127.0.0.1:5555 shell hilog -x | Select-String -Pattern 'MissingPluginException|super_native_extensions|ClipboardUtils|ImageContextMenu'
   ```
   期望：无 `MissingPluginException`、无 `Failed to lookup symbol`。
4. 若要回归非 OHOS 端：桌面端「复制图片」仍应写入图片剪贴板（`supportsRichClipboard=true`）。

### 4.6 已知限制（剪贴板）

- OHOS 上「粘贴剪贴板图片到编辑器」不可用（降级纯文本），这是首版取舍；ArkTS 侧可用
  `@ohos.pasteboard` 读图片，再做第二条桥（P2）。
- 「复制图片」在 OHOS 语义变为「复制图片链接」，文案已区分。

---

## 5. P1 本地通知（flutter_local_notifications CPF fork 22.0.1）

### 5.1 核对结论（必须改，否则 OHOS 初始化直接抛错）

fork 的 Dart 实现（`.pub-cache/git/fluttertpc_flutter_local_notifications-.../lib/src/flutter_local_notifications_plugin.dart`）：

- `initialize()` 在 `defaultTargetPlatform == TargetPlatform.ohos` 分支要求
  **`InitializationSettings.ohos != null`**，否则 `throw ArgumentError('Ohos settings must be set when targeting Ohos platform.')`。
- `show()` 需要 `NotificationDetails.ohos`（`OhosNotificationDetails`，第一个位置参数是
  `OhosNotificationSlotType`，缺省会导致系统通知渠道归类异常/发布失败）。
- 权限：`OhosFlutterLocalNotificationsPlugin.requestNotificationsPermission()` →
  ArkTS `notificationManager.requestEnableNotification()`，需要 **Ability 已绑定**
  （插件是 `AbilityAware`，注册顺序无误即可）。
- ArkTS `initialize` 会 `resourceManager.getMediaByName(defaultIcon)` 校验图标资源，
  找不到会 `result.error(ERROR_INVALID_ICON)`；这里用 entry 里确定存在的 **`icon`**
  （`repo/ohos/entry/src/main/resources/base/media/icon.png`，module.json5 的 `$media:icon`）。
- `PUBLISH_AGENT_REMINDER`：module.json5 已声明（`zonedSchedule` 的提醒代理需要；即时
  `show()` 不依赖它）。不用新增权限。

### 5.2 实现位置

`lib/services/local_notification_service.dart`

| 位置 | 改动 |
|---|---|
| `initialize()` | 新增 `const ohosSettings = OhosInitializationSettings('icon')` 并传给 `InitializationSettings(ohos: ...)` |
| `_requestPermission()` | 新增 OHOS 分支：`resolvePlatformSpecificImplementation<OhosFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission()`；异常时按已授权继续（避免 Ability 未绑定就让整条链路沉默） |
| `show()` | `NotificationDetails` 增加 `ohos: OhosNotificationDetails(SOCIAL_COMMUNICATION, importance: high, autoCancel: true)` |
| `showApkProgress()` | OHOS 直接跳过（OHOS 不支持应用内装 HAP；且下载进度模板部分设备 `isSupportTemplate` 返回 false 会让插件抛错） |
| `showApkComplete()` | 增加 `ohos: OhosNotificationDetails(SERVICE_INFORMATION, ...)`（正常路径在 OHOS 不会触发，保持 API 完整） |

### 5.3 Lead 验证步骤

1. 首次启动（或清除应用数据后启动）观察：应弹出系统「FluxDO 请求通知权限」/「允许通知」框。
   点允许。
2. 抓日志：
   ```powershell
   & $hdc -t 127.0.0.1:5555 shell hilog -x | Select-String -Pattern 'flutterlocalnotifications|dexterous|local_notifications|MethodCallHandlerImpl|NotificationManager'
   ```
   期望（插件 ArkTS 侧日志，tag 为 `A000ff/Flutter`，D/I 级）：
   - 初始化阶段出现 `initialize-->defaultIcon ...` / `defaultIcon seted`（说明 `OhosInitializationSettings('icon')` 生效、
     `icon` 资源找得到）；
   - 请求权限阶段出现 `requestNotificationsPermission` / `enableNotification-->success`；
   - Dart 侧日志（`[LocalNotification] 初始化完成` / `OHOS 权限: true`）不在 hilog 里，需要
     `flutter run --debug` 观察（见 §2.4 的实测提示）。
   失败对照：hilog 有 `ArgumentError: Ohos settings must be set...` → 改动没进构建；
   有 `ERROR_INVALID_ICON` / `The resource icon could not be found` → `icon` 资源未打进 HAP。
3. 真正发一条通知（二选一）：
   - 用另一台设备/浏览器登录同一账号，回复 Lead 账号的话题/发私信，App 在前台时 MessageBus
     会调 `LocalNotificationService().show(...)`；
   - 或等聊天新消息（`chat_notification_alert_provider`）。
   期望 `flutter run` 里出现 `[LocalNotification] 已发送: <标题>`，下拉通知栏看到通知；
   点击通知应跳到对应话题/私信/聊天页（payload 路由原逻辑不变）。hilog 侧可同时看到
   `NotificationManager --> publish` 之类的插件日志。
4. 系统侧确认通知已发布：
   ```powershell
   & $hdc -t 127.0.0.1:5555 shell "hidumper -s 3301 -a '-n com.fluxdo.app'" | Select-Object -First 40
   ```
   （通知服务 dump，能看到 bundle 下已发布的通知；不同 ROM 输出格式不同，看不到就以通知栏为准。）

### 5.4 已知限制（通知）

- 只验证了即时 `show()` 路径；`zonedSchedule`（提醒代理）/周期通知未在 OHOS 验证，代码未改。
- 后台/杀进程后的通知接收仍依赖 MessageBus 前台连接（`OhosCompat.supportsBackgroundTasks=false`），
  属既有降级。
- 通知图标是 App 图标（`icon`）；若要更规范的小图标，后续可在 resources 里加单色通知图标并
  把 `OhosInitializationSettings('notification_icon')` 改过去。

---

## 6. P1 深链

### 6.1 结论：ArkTS 侧不用改，Dart 侧加健壮性

- `repo/ohos/entry/src/main/module.json5` 的 `skills` 已声明：
  `entity.system.browsable` + `ohos.want.action.viewData`，`uris: [{scheme: fluxdo}, {scheme: discourse}]`。
- `app_links` 已 override 到 CPF fork 7.0.0（`AppLinksPlugin.ets`）：
  - `onAttachedToAbility()` 读 `ability.launchWant.uri` 存为 `initialLink`（冷启动）；
  - 注册 `addOnNewWantListener`，`onNewWant` 时把 `want.uri` 推给 EventChannel（热启动）；
  - Dart 侧 `getInitialLink()` / `uriLinkStream` 对应 `com.llfbandit.app_links/messages` 与
    `/events` 两条通道，`GeneratedPluginRegistrant.ets` 已注册 `AppLinksPlugin`。
- `lib/services/deep_link_service.dart` 原有逻辑已用 `getInitialLink()` + `uriLinkStream`，
  但没有错误兜底、冷启动只查一次。本次改动：
  1. `uriLinkStream.listen(..., onError: ...)`：事件通道异常只打日志，不影响启动；
  2. `_handleInitialLink()` 在 OHOS 上最多重试 5 次 × 200ms（覆盖「Ability 绑定晚于 Dart 首帧」
     的竞态），其他平台保持单次查询；
  3. 冷启动命中时打印 `DeepLinkService: 冷启动链接 <uri>` 便于 Confirm。

### 6.2 Lead 验证命令

```powershell
$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
# 0) 可选：确认系统已登记 scheme（bm dump 里能看到 skills）
& $hdc -t 127.0.0.1:5555 shell bm dump -n com.fluxdo.app | Select-String -Pattern 'fluxdo|discourse'

# 1) 冷启动：先杀进程，再带 URI 拉起
& $hdc -t 127.0.0.1:5555 shell aa force-stop com.fluxdo.app
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.app -U "fluxdo://topic/123"
Start-Sleep -Seconds 10
& $hdc -t 127.0.0.1:5555 shell hilog -x | Select-String -Pattern 'DeepLinkService|AppLinksPlugin'

# 2) 热启动：App 在前台时再发一次
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.app -U "fluxdo://user/neo"
```

**期望：**

- hilog：`DeepLinkService: 冷启动链接 fluxdo://topic/123`（冷启动）；
  热启动时 `DeepLinkService: 收到链接 fluxdo://user/neo`；
- 界面：冷启动进入首页后自动 push 对应话题 / 用户主页（123 需为真实存在的 topic id，
  否则会看到话题页错误态——这本身也说明路由通了）；
- `discourse://` 授权回调：用真实登录流程触发（浏览器授权后回跳），或手工验证：
  ```powershell
  & $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.app -U "discourse://auth_redirect?payload=test"
  ```
  期望 hilog `DeepLinkService: 收到链接 discourse://auth_redirect?payload=test`，
  随后 `UserApiKeyLoginFlow` 处理（payload 非法会报错，属预期）。

### 6.3 已知限制（深链）

- `https://linux.do/...`（App Linking / 自动验证 http 链接）**未声明**：需要先在 AGC 完成域名
  校验再往 module.json5 加 `{scheme: "https", host: "linux.do", ...}`，否则系统忽略。当前只保证
  `fluxdo://` 与 `discourse://` 两个自定义 scheme。`aa start -U "https://linux.do/t/123"` 不会进
  FluxDO，属预期。
- 深链处理依赖 `DeepLinkService.initialize()` 被首页调用（`main.dart` 既有逻辑，未改）。

---

## 7. 构建 / 验证总清单（Lead 按序执行）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
cd C:\Users\iceblock\fluxdo

# ① 构建+签名+安装+启动（本任务无需改 pubspec / module.json5，直接构建即可）
.\tools\build-ohos.ps1 -Install -Launch

# ② 清日志 → 冷启动 → 抓全量
$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell hilog -r
& $hdc -t 127.0.0.1:5555 shell aa force-stop com.fluxdo.app
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.app
Start-Sleep -Seconds 15
& $hdc -t 127.0.0.1:5555 shell hilog -x |
  Select-String -Pattern 'FluxdoBridge|TimeUtils|LocalNotification|DeepLinkService|ImageSaveUtils|ClipboardUtils|MissingPluginException'

# ③ 时区：看图/看 local_date / 看 TimeUtils.localTimezone
# ④ 相册：图片菜单保存 → 系统弹框 → 图库确认
# ⑤ 剪贴板：图片菜单「复制图片」→ 粘贴出链接；富文本粘贴纯文本不崩
# ⑥ 通知：首次启动授权框 + 触发一条消息通知
# ⑦ 深链：见 §6.2
```

**验收通过标准（本任务相关）：**

1. hilog 出现 `0F1D/FluxdoBridge: bridge attached, 3 channels, localTimezone=<IANA>`，
   且出现引擎级 `Received message from Dart over channel 'com.fluxdo/ohos'`；
2. 时区值非 UTC（模拟器当前系统时区为 CST，应为 `Asia/Shanghai`）；
3. 「保存到相册」出现系统弹框并能入图库（或至少走到 §3.2 的回落路径且文件落地）；
4. 所有原来的 6 个 super_clipboard 调用点无 `MissingPluginException` / 无崩溃
   （其中 5/6 号两处要等 Lead 套用 §4.4 patch）；
5. 首次启动出现系统通知授权框；`flutter run` 里能看到 `[LocalNotification] 初始化完成`；
6. 深链命令能拉起并（在 `flutter run` 里）打印 `DeepLinkService: 冷启动链接 ...`。

> 说明：第 2/5/6 条的 Dart 侧文本若在 hilog 里看不到，属已知现象（见 §2.4），
> 以 UI 行为 + ArkTS/引擎日志为准。

---

## 8. ArkTS 侧无法本地编译的风险与核对

本任务子代理沙箱不能跑 `flutter build hap`（需要完整权限，见 `docs/ohos-build-notes.md` §4.4），
ArkTS 改动没做过 hvigor 编译。已做的替代校验：

1. **语法**：DevEco 自带 TypeScript 解析器（`D:\DevEco Studio\tools\hvigor\hvigor\node_modules\typescript`）
   解析两个 ets 文件 → `0 parse diagnostic(s)`（脚本在 `.tmp/ohos_analyze/ets_syntax_check.js`，不进 repo）；
2. **符号**：对照 SDK d.ts / `@ohos/flutter_ohos` har 导出逐个核对（下表）。

| 符号 | 依据 |
|---|---|
| `MethodChannel` / `MethodCall` / `MethodResult` / `MethodCallHandler` / `FlutterPlugin` / `FlutterPluginBinding` | `@ohos/flutter_ohos` har `index.ets` 的导出（`export *` / `export { default as ... }`）；同包已编译插件（app_links、saver_gallery、flutter_local_notifications）用法一致 |
| `flutterEngine.getPlugins()?.add(plugin)` | `FlutterEngine.getPlugins(): PluginRegistry | null` + `PluginRegistry.add(plugin): void`；`GeneratedPluginRegistrant` 同款写法 |
| `i18n.getTimeZone()` / `TimeZone.getID()` | `@ohos.i18n.d.ts` L1683-1713（API 7 起） |
| `i18n.System.getAppDefaultTimeZone()` | 同文件 L1854（API 12 起） |
| `i18n.TimeZone.getAvailableIDs()` | 同文件 L1759（API 9 起） |
| `i18n.System.getSystemLocale()` | 同文件 L251 |
| `hilog.info/warn/error(domain, tag, format, ...args)` | `@ohos.hilog.d.ts`（`...args: any[]`） |

**首次构建若 ArkTS 报错，优先检查（按概率）：**

1. `EntryAbility.ets` 的 `import FluxdoBridgePlugin from '../plugins/FluxdoBridgePlugin';`
   路径大小写/文件名是否与文件系统一致（Windows 不敏感、hvigor 某些环节敏感）。
2. `FluxdoBridgePlugin.ets` 若被 hvigor 的 `build-profile` 排除（不会，ets 目录整体编译）。
3. ArkTS 严格模式下 `catch (e)` 之后必须 `as Error` 再用 —— 已按插件惯例写。
4. 若报 `i18n.System.getAppDefaultTimeZone` 不存在（低版本 SDK）：删掉 `getLocalTimezone()`
   里第二段 `appZone` 回退即可（主路径 `i18n.getTimeZone()` 从 API 7 起就有）。

**回滚方式：**

- 只回滚 ArkTS：`entryability/EntryAbility.ets` 删掉 `FluxdoBridgePlugin` import 与注册块、
  删除 `plugins/FluxdoBridgePlugin.ets`；Dart 侧 `time_utils.dart` 的 OHOS 桥调用会自动因
  `MissingPluginException` 回退到 `flutter_timezone`（其 OHOS 通道也没了）→ 最终 UTC，等同改动前。
- 只回滚 Dart 时区：把 `_resolveLocalTimezoneName()` 恢复为直接
  `(await FlutterTimezone.getLocalTimezone()).identifier`。
- 相册回滚：`saveBytes()` 里把 `PlatformUtils.isOhos` 分支删掉，恢复
  `PlatformUtils.isDesktop || PlatformUtils.isOhos ? _saveAsFile(...)`。
- 通知回滚：删 `ohos: ohosSettings` / `ohos:` details / OHOS 权限分支；注意 fork 下 OHOS
  `initialize()` 会重新抛 ArgumentError（main.dart 有 catch，但通知全链路不可用）。

---

## 9. 交付文件清单（本任务）

```
repo/ohos/entry/src/main/ets/plugins/FluxdoBridgePlugin.ets   （新增，ArkTS 桥）
repo/ohos/entry/src/main/ets/entryability/EntryAbility.ets     （修改，注册桥插件）
repo/lib/utils/time_utils.dart                                 （修改，时区接入）
repo/lib/utils/image_save_utils.dart                           （修改，saver_gallery 优先）
repo/lib/utils/clipboard_utils.dart                            （新增，剪贴板统一出口）
repo/lib/widgets/common/image_context_menu.dart                （修改，复制图片降级）
repo/lib/widgets/share/ai_share_image_preview.dart             （修改，复制截图降级）
repo/lib/widgets/markdown_editor/markdown_toolbar.dart         （修改，粘贴图片能力守卫）
repo/lib/widgets/markdown_editor/rich_composer/rich_composer_editor.dart （修改，富粘贴守卫）
repo/lib/services/local_notification_service.dart              （修改，OHOS 初始化/权限/渠道）
repo/lib/services/deep_link_service.dart                       （修改，冷启动重试+错误兜底）
docs/ohos-arkts-bridges.md                                     （本文）
```

未改：`repo/lib/main.dart`、`repo/lib/services/network/**`、`repo/pubspec.yaml`、
`repo/ohos/entry/src/main/module.json5`、`repo/lib/pages/**`（5/6 号剪贴板调用点见 §4.4 patch）。
