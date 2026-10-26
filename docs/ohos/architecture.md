# 移植架构

> 目标：在不改动上游业务逻辑的前提下，让 FluxDO（Flutter）运行在 HarmonyOS 7（API 26）上，
> 并把上游依赖的原生插件替换/补齐为 OHOS 可用实现。

## 1. 分层结构

```
Flutter (Dart)  lib/  ← 上游业务代码，仅做平台判定与能力开关
      │  MethodChannel / FFI
      ▼
OHOS 平台层（新增）
├── ohos/                                   HarmonyOS 工程（bundle com.fluxdo.app）
│   ├── build-profile.json5                 compatibleSdkVersion/targetSdkVersion "26.0.0"
│   ├── entry/src/main/module.json5         权限、fluxdo:// 与 discourse:// 深链 skills
│   └── entry/src/main/ets/
│       ├── entryability/EntryAbility.ets   注册插件、注入 UIAbilityContext
│       └── plugins/FluxdoBridgePlugin.ets  自研 ArkTS 桥（见 §4）
└── ohos/entry/libs/<abi>/*.so              5 个自编译原生库（见 §3）
```

Dart 侧平台适配集中在两处：

| 文件 | 作用 |
|---|---|
| `lib/utils/platform_utils.dart` | `isOhos` 判定；`isMobile` 纳入 OHOS；UA 等平台差异 |
| `lib/utils/ohos_compat.dart` | OHOS 能力开关（DOH / rhttp / cook / 动图 / AVIF / 相册 / 通知 / 后台任务 / 剪贴板等） |

业务代码里所有平台分支都以 `PlatformUtils.isOhos` / `OhosCompat.*` 前置，非 OHOS 平台行为不变。

## 2. 插件适配策略

26 个 Flutter 插件分三类处理（逐项见 [plugin-matrix.md](./plugin-matrix.md)）：

1. **官方/社区已有 OHOS 实现**：直接用（`path_provider_ohos`、`shared_preferences_ohos`、
   `url_launcher_ohos`、`sqflite_ohos`、`file_picker`、`share_plus`、`mobile_scanner`、
   `flutter_local_notifications`、`saver_gallery`、`image_picker_harmonyos` 等）。
2. **无 OHOS 实现 → 自研 ArkTS 桥或降级**：时区、剪贴板、通知初始化、系统浏览器打开等（见 §4）。
3. **上游 Flutter 引擎能力**：图片解码、输入法、WebView（ArkWeb）等由引擎/系统提供。

> 后台保活（系统长时任务）已移除：它会常驻通知栏且收益有限，切后台交给系统正常挂起；
> 通知权限也从「启动即申请」改为按需申请。

`packages/` 下有 5 个 vendored 包（`rhttp`、`native_animated_image`、`file_picker`、
`share_plus`、`flutter_math_fork`、`just_audio_harmonyos`），用于：
- 修复 `TargetPlatform.ohos` 未覆盖的 switch 分支；
- 去掉上游包里的嵌套 git 依赖（OHOS 构建环境不适用）；
- 补齐 API 26 的媒体接口差异；
- 为 `file_picker` 的保存流程注入 bytes。

## 3. 自编译原生库（5 个）

全部交叉编译（OHOS NDK sysroot + clang/lld），已预编译提交，普通构建无需重编：

| 库 | 来源 | 用途 | 大小（x86_64 / arm64） |
|---|---|---|---|
| `librhttp.so` | Rust reqwest + flutter_rust_bridge | 高性能网络引擎（HTTP/2） | 7.1 / 5.6 MB |
| `libdoh_proxy.so` | Rust（`core/doh_proxy`） | DNS over HTTPS 本地网关，**进程内 FFI**，非独立进程 | 7.1 / 6.3 MB |
| `libohos_avif.so` | libavif + dav1d + 小封装 | AVIF 解码（输出 RGBA） | 0.9 / 0.8 MB |
| `libnative_animated_image_codec.so` | Rust（native_animated_image） | 动图解码（GIF/WebP 等） | 0.6 / 0.5 MB |
| `libohos_quickjs.so` | QuickJS 0.17 + C 桥 | cook 脚本渲染，持久 JSRuntime/JSCContext | 1.1 / 1.1 MB |

重新编译（需要 WSL + OHOS NDK）见 `tools/ohos/build-*.sh`，脚本内用 `OHOS_NDK`、`FLUXDO_WS` 环境变量指定路径。

### 交叉编译要点

- DevEco 自带 NDK 只提供 **Windows 版 clang**，且路径含空格，脚本化构建不可靠；
  因此在 WSL 内用 Ubuntu clang-18 + LLD，配 `--sysroot=$NDK/sysroot`、
  `-resource-dir=$NDK/llvm/lib/clang/<ver>`、`-target x86_64-linux-ohos` / `aarch64-linux-ohos`。
- 未解析的 `_Unwind_*` 符号会导致 dlopen 失败：
  - arm64 链接 NDK 的 `libunwind.a`；
  - x86_64 链接一个最小的 `_Unwind_*` 桩（`tools/ohos/ohos-unwind-stub.c`）；
  - 所有 Rust 库以 `-C panic=abort` 构建。
- 打包：`.so` 放入 `ohos/entry/libs/<abi>/`，hvigor 自动打进 HAP 的 `libs/<abi>/`。

## 4. ArkTS 桥（`FluxdoBridgePlugin`）

MethodChannel：`com.fluxdo/ohos`

| 方法 | 用途 |
|---|---|
| `getLocalTimezone` / `getAvailableTimezones` | 系统时区（替代 `flutter_timezone` 的缺失实现） |
| `getSystemLocale` | 系统语言 |
| `probeAvif` / `decodeAvif` | AVIF 能力探测与 ImageKit 解码（备用路径） |
| `writeImageToPasteboard` / `readClipboardHtml` | 剪贴板写图片；读 HTML（受系统权限限制，失败降级） |
| `openExternalUrl` | 用系统浏览器打开链接（`url_launcher` 在 OHOS 无实现，走 `startAbility(viewData)`） |

关键点：

- `openExternalUrl` 需要 **UIAbilityContext**：由 `EntryAbility` 在注册插件前注入
  `FluxdoBridgePlugin.abilityContext`；
- 剪贴板「写图片」路径：PNG → `image.createPixelMap` → `pasteboard.createData(MIMETYPE_PIXELMAP)`；
- 剪贴板「读 HTML」：`getData().getPrimaryHtml()`；`READ_PASTEBOARD` 属 system_basic 权限，
  普通应用证书无法授予，**不要声明**（否则安装直接失败），代码按失败降级为纯文本。

## 5. Dart 侧适配要点

| 模块 | 改动 |
|---|---|
| 网络 | OHOS 平台适配器；Cloudflare 挑战修复（见下）；DOH FFI 分支（`DohProxyFfi.isAvailable` 需包含 isOhos） |
| 图片 | AVIF 平台编解码入口（原生库优先，ImageKit 备用）；动图原生库加载 |
| cook 渲染 | QuickJS 引擎实现 `CookJsEngine`，持久上下文以保留 `__fluxdoCook` 全局 |
| 后台 | `OhosBackgroundTask` + `BackgroundNotificationService` 接线（切后台申请、回前台释放） |
| 剪贴板 | OHOS 写图片桥；读富文本降级为纯文本 |

### Cloudflare 403 的处理

linux.do 前置 Cloudflare 盾，OHOS 上的关键点：

1. 手机设备 + 桌面 UA 会被直接 403 → OHOS 分支使用移动端 UA；
2. 部分 WebView 回调（`useOnNavigationResponse` / `useShouldOverrideUrlLoading`）会让挑战
   「看似完成但未真正执行」→ OHOS 关闭这些回调，让 ArkWeb 真跑挑战；
3. ArkWeb 的 HttpOnly `cf_clearance` 无法导出给 dio → 失败时自动切换到 WebView 网络栈重放请求。

## 6. 构建产物

| 类型 | 大小 | 说明 |
|---|---|---|
| release（双 ABI，含 5 原生库） | 约 204 MB（签名后） | 真机/模拟器通用 |
| release（单 arm64） | 约 114 MB（未签名）/ 115 MB（签名） | 真机 |
| debug（多 ABI） | 约 398 MB | 调试用，含 JIT 快照 |

debug 包含 `kernel_blob.bin`/`vm_snapshot_data` 等标记；release 为 AOT，无 DEBUG 角标。
