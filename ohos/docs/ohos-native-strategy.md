# FluxDO HarmonyOS 7 原生组件移植策略（task-2）
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从 `module.json5` 删除。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 目标平台：HarmonyOS 7 / OpenHarmony API 26（模拟器 x86_64，真机 arm64）
> Flutter：`C:\Users\iceblock\fluxdo\tools\flutter`（`oh-3.47.7-preview`，实测 `CHANGELOG_OHOS.md` 首行为 `3.47.7-ohos-0.0.1`）
> DevEco Studio 26.0：`D:\DevEco Studio`；Native SDK：`D:\DevEco Studio\sdk\default\openharmony\native`（`oh-uni-package.json`：`apiVersion=26`、`platformVersion=26.0.0`）
> 本文只讨论原生/重依赖组件；普通插件矩阵见 `docs/ohos-plugin-matrix.md`（task-1）。

---

## 0.0 Rust 交叉编译实测结论（2026-10-21 补充）
## 0.0 Rust 交叉编译：已打通（2026-10-21 实测）

`core/doh_proxy` 已成功交叉编译为 HarmonyOS 原生库，**DOH 代理在 OHOS 上可用**。

最终可行路径（Windows 宿主机 + WSL Ubuntu-24.04，推荐）：

| 步骤 | 做法 |
|---|---|
| Rust | WSL 内 rustup 安装（rustc 1.99.1），`rustup target add x86_64-unknown-linux-ohos aarch64-unknown-linux-ohos` |
| C 编译器 | WSL 内 `apt-get install clang lld`（Ubuntu clang 18.1.3）。**不用** DevEco 自带 clang：只有 Windows 版，且其包装脚本对含空格路径未加引号 |
| sysroot / 内建库 | `--sysroot=<NDK>/sysroot` + `-resource-dir=<NDK>/llvm/lib/clang/15.0.4` |
| 链接 | `-fuse-ld=lld -unwindlib=none` |
| libunwind | NDK 无 `libunwind.a`；Rust 的 OHOS target 默认传 `-lunwind`，用空归档占位（cdylib 未定义符号运行时解析） |
| cmake 依赖 | `aws-lc-sys` 需要 cmake → WSL 内 `apt-get install cmake`（3.28.3） |
| 产物 | `libdoh_proxy.so`：x86_64 7.5 MB / arm64-v8a 6.6 MB，仅依赖 `libc.so`，导出全部 `doh_proxy_*` FFI 符号 |
| 打包 | 放 `repo/ohos/entry/libs/<abi>/`，hvigor 自动打进 HAP 的 `libs/<abi>/` |
| 运行时 | `doh_proxy_ffi.dart` 在 OHOS 走 `DynamicLibrary.open('libdoh_proxy.so')` |

可复现脚本：`tools/build-doh-ohos.sh`（WSL 内执行，含上述全部配置与两个 ABI 的构建）。

历史记录（Windows 原生尝试的两个坑，避免重踩）：MSVC 缺 `link.exe`、GNU 宿主缺 `dlltool.exe`；
转到 WSL 后这两个问题都不存在，因此**推荐始终在 WSL 里做 Rust 交叉编译**。

Dart 侧已就绪：`lib/services/network/doh_proxy/doh_proxy_ffi.dart` 已增加 OHOS 分支
（`DynamicLibrary.open('libdoh_proxy.so')`）。把交叉编译产物放进
`repo/ohos/entry/libs/<abi>/` 随 HAP 打包、再把 `OhosCompat.supportsDohProxy` 打开、
恢复网络设置里的 DOH 卡片，即可完成 DOH 代理在 HarmonyOS 上的启用。

---

## 0. 结论速览

| # | 组件 | 判断 | 首版动作 | 优先级 |
|---|------|------|----------|--------|
| 1 | `core/doh_proxy`（Rust DoH/ECH 代理） | **可行**：OHOS 是 Rust Tier-2 target（带 host tools），FFI 为纯 `extern "C"`，无 JNI 依赖 | 交叉编译 `libdoh_proxy.so` 放 `ohos/entry/libs/<abi>/`；首版**不带 `ech` feature**；`isAvailable`/`_loadLibrary` 增加 OHOS 分支 | **P0（必移植）** |
| 2 | `rhttp`（Rust reqwest + FRB 2.12） | **可移植**：Rust 侧依赖 aws-lc-rs（上游已合入 OpenHarmony 支持）；卡点在 FRB 2.12 的 Dart 加载器不认 `ohos` | 用 vendored `flutter_rust_bridge`（path override）补 OHOS 分支 + 手工构建 `librhttp.so`；首版默认关闭（默认即关闭） | P1 |
| 3 | `flutter_js` + Discourse cook | **需替换引擎**：`flutter_js` 无 OHOS；`flutter_qjs` 有 OHOS 适配 | 首版：OHOS 上 `cookJsSupported=false`（自动降级到 Dart 近似预览）；后续换 `fluttertpc_flutter_qjs` | 降级 P0 / 真移植 P2 |
| 3b | `render_backend_service` | **无需移植**：`_supported = Platform.isAndroid`，OHOS 上天然 no-op | 不改 | — |
| 4a | `native_animated_image`（Rust 解码 GIF/APNG/WebP） | **可行且简单**：纯 Rust（gif/png/image-webp），无 C 依赖；只有 Dart 加载器缺 OHOS | 交叉编译 `libnative_animated_image_codec.so` + 补加载器分支 | **P1（性价比最高）** |
| 4b | `flutter_avif`（libavif+dav1d） | **高成本**：native 是 Rust cdylib + C（dav1d/libavif）交叉编译；CPF 仓库尚无 ohos 适配 | 首版禁用；静态 AVIF 先依赖引擎 `OHOSImageGenerator`（OHOS ImageSource），动画 AVIF 降级 | 降级 P0 / 真移植 P2 |
| 5a | `video_player` 2.14.0 | **可移植**：官方联邦实现 `video_player_ohos` 已存在（基于 AVPlayer + Pigeon） | 用 `openharmony-tpc/flutter_packages` 的 `br_video_player-v2.11.1_ohos`（需从 2.14.0 降到 2.11.1） | **P1** |
| 5b | `just_audio` 0.10.6 | **可移植**：`just_audio/ohos` 已存在（0.10.5 分支） | git 覆盖到 `CPF-Flutter/fluttertpc_just_audio` `br_v0.10.6_ohos`（实际版本 0.10.5） | P1 |
| 5c | `record` 7.1.1 | **可移植且版本正好** | git 覆盖到 `CPF-Flutter/fluttertpc_record` `br_3.41_dev`（版本 7.1.1 + `record_ohos`） | P1 |
| 5d | `pro_image_editor` 11.23.0 | **基本可用**：纯 Dart + shared_preferences（仅 android 平台声明有原生部分） | 直接跑；验证裁剪/导出/文件读写 | P1（验证） |
| 5e | `mobile_scanner` 7.4.2 | **可移植**（fork 7.1.4） | 首版：走已有「相册选图 + zxing2」降级（`_supportsCamera` 不含 OHOS）；后续接 `br_v7.1.4_ohos` | 降级 P0 / 真移植 P2 |
| 5f | `flutter_inappwebview` 6.2.0-beta.3 | **必须移植**：登录/CF 验证/WebView 全靠它；`flutter_inappwebview_ohos` 已存在（基于 6.1.5） | git 覆盖到 `CPF-Flutter/flutter_inappwebview` `br_v6.1.5_ohos` + `flutter_inappwebview_ohos` | **P0（必移植）** |
| 6a | `flutter_local_notifications` 21.0.0 | **可移植**：fork 22.0.1 已含 `ohos/`（`OhosInitializationSettings`/`OhosNotificationDetails`） | git 覆盖到 `br_3.41_dev`（22.0.1）；`LocalNotificationService` 增加 `ohos:` 配置 | P1 |
| 6b | `flutter_foreground_task` / `workmanager` | **不可用**：无 OHOS 实现（`flutter_foreground_task` 的 CPF 仓库无 `ohos/`；workmanager 仅 Android/iOS/macOS） | OHOS 上后台轮询不做，保持「前台保活」；通知依赖前台会话 | 降级 P0 |
| 6c | `ota_update` | **不可用**（APK 安装语义）：fork 有 `ohos/`，但 OHOS 普通应用不能静默装包 | 设置页 OHOS 隐藏 APK 更新入口，改为「跳应用市场/浏览器下载」 | 降级 P0 |
| 6d | `app_links` 7.2.1 | **可移植**：fork 7.2.2 含 `app_links/ohos` | git 覆盖 + `module.json5` 声明 `fluxdo://` / `discourse://` skills | P1 |
| 6e | `super_clipboard` | **不可用**：依赖 `super_native_extensions`（Rust，无 OHOS） | OHOS 回退到 Flutter `Clipboard`（纯文本），富 HTML/图片粘贴禁用 | 降级 P0 |
| 6f | `window_manager` / `screen_retriever` / `flutter_acrylic` / `win32_registry` | **桌面专用，OHOS 不适用** | `main.dart` 已按 `isMacOS/isWindows/isLinux` 门控，OHOS 天然不执行；`win32_registry` 仅 `Platform.isWindows` 分支 | 不改（仅确认无泄漏调用） |

**首版必须在 OHOS 禁用的功能面**：rhttp（保持默认关闭）、cook JS（降级 Dart 预览）、flutter_avif（静态走引擎，动画降级）、后台通知（Android/iOS 专属保活）、APK 更新（改为外链）、super_clipboard 富粘贴、相机扫码（相册兜底）、窗口管理/亚克力、ECH（首版不编译 `ech` feature 时，ECH 设置项隐藏/置灰）。

**最值得真移植（投入产出比排序）**：doh_proxy（DoH 是产品核心）→ inappwebview（登录/CF）→ native_animated_image（动图体验）→ video_player/just_audio/record（媒体）→ rhttp（HTTP/2/3 + ECH 统一栈）→ flutter_js（编辑器 1:1 预览）→ flutter_avif（AVIF 完整性）。

---

## 1. 已验证的环境事实（写进任何步骤前先确认）

| 事实 | 验证方式/结果 |
|------|----------------|
| OHOS Flutter 平台已启用 | `tools/flutter/packages/flutter_tools/lib/src/features.dart:30` → `bool get isOhosEnabled => true` |
| `Platform.operatingSystem == 'ohos'`、存在 `Platform.isOhos`、`TargetPlatform.ohos` | `packages/flutter/lib/src/foundation/_platform_io.dart:28`、`platform.dart:85`；`flutter_tools/.../widgets/_window_io.dart:41` 使用 `Platform.isOhos` |
| OHOS 应用/插件模型 | 插件在 pubspec 声明 `flutter.plugin.platforms.ohos`，`ohos/` 目录被 flutter_tools 当作 HAR 模块加入 `build-profile.json5`（`ohos/ohos_plugins_manager.dart`） |
| 原生 `.so` 落位 | `ohos/<module>/libs/<abi>/`，abi 名与 Android 相同：`arm64-v8a` / `x86_64` / `armeabi-v7a`（`flutter_tools/.../build_info.dart:1004 getNameForOhosArch`；`ohos/ohos_builder.dart:98` 注释 `entry/libs/arm64-v8a/libapp.so`） |
| FFI 加载方式 | 裸名 `DynamicLibrary.open('libxxx.so')` 可用（OHOS 适配插件即这么做，如 `fluttertpc_flutter_qjs` 的 `lib/src/ffi.dart:140` 在 OHOS 上 `DynamicLibrary.open('libqjs.so')`） |
| 构建命令 | `flutter build hap --target-platform ohos-arm64|ohos-x64|ohos-arm`（`flutter_tools/lib/src/commands/build_hap.dart`），默认 `ohos-arm64`；`--codesign=false` 可跳过签名 |
| Rust OHOS target | `aarch64-unknown-linux-ohos` / `x86_64-unknown-linux-ohos` 为 **Tier 2（with host tools）**，`rustup target add` 可直接装（rustc book `platform-support/openharmony.html`）；`loongarch64` 才是 Tier 3 |
| OHOS triple 的 cfg | `env = "ohos"`、`os = "linux"`（`rustc_target/src/spec/base/linux_ohos.rs`：`Env::Ohos`、`has_thread_local: false`、`tls_model: Emulated`）。即：Rust 里 `cfg(target_os = "linux")` **会命中**，用 `cfg(target_env = "ohos")` 区分 |
| Native SDK 工具链 | `native/llvm/bin/{clang.exe,llvm-ar.exe,ld.lld.exe}`、`native/sysroot/{aarch64-linux-ohos,x86_64-linux-ohos,arm-linux-ohos}`、`native/build/cmake/ohos.toolchain.cmake`、`native/build-tools/cmake/bin/{cmake.exe,ninja.exe}`；SDK 自带 `*-ohos-clang` 是 `#!/bin/sh` 包装脚本（Windows 上不可直接给 cargo 用，需自建 `.bat`） |
| 本机 Rust | **未安装**（`cargo/rustc/rustup` 均不在 PATH，`C:\Users\iceblock\.cargo` 不存在）。所有 Rust 步骤都要先装工具链 |
| 本机 openssl | Git for Windows 自带 `C:\Program Files\Git\usr\bin\openssl.exe`，但在 DSH 沙箱下报 `couldn't create signal pipe, Win32 error 5`（MSYS 二进制的命名管道被拦），所以 **doh_proxy 的 build.rs 自动生成 CA 在沙箱里会失败**，需要预生成或改 build.rs（见 §3.3） |
| 仓库内 `assets/certs/` 目前不存在 | `core/doh_proxy/build.rs` / `src/bin/gen_ca.rs` 负责生成；`pubspec.yaml:243` 已声明 `assets/certs/`。`repo/.gitignore:91` 忽略 `assets/certs/proxy_ca.pem` |
| `core/doh_proxy` 是 git submodule 且未初始化 | `.gitmodules` → `https://github.com/Lingyan000/fluxdo_doh.git`；本工作区 `repo/core/doh_proxy` 为空目录 |

---

## 2. 通用 Rust 交叉编译配方（一次性基建，所有 Rust 组件共用）

### 2.1 安装 Rust 与 OHOS target

```powershell
# 在宿主（Windows）安装 rustup（若未装）
winget install --id Rustlang.Rustup   # 或 https://rustup.rs
rustup default stable
rustup target add aarch64-unknown-linux-ohos x86_64-unknown-linux-ohos
rustup target list --installed        # 应看到两个 *-unknown-linux-ohos
```

### 2.2 建 clang 包装器（解决 Windows 上 SDK 自带脚本是 sh 的问题）

`C:\Users\iceblock\fluxdo\tools\ohos\cc\cc-aarch64-ohos.bat`：

```bat
@echo off
set SDK=D:\DevEco Studio\sdk\default\openharmony\native
"%SDK%\llvm\bin\clang.exe" -target aarch64-linux-ohos --sysroot="%SDK%\sysroot" -D__MUSL__ %*
```

`cc-x86_64-ohos.bat` 同样内容，仅 `-target x86_64-linux-ohos`。
（对应 Rust target 的 `cc`/`linker` 都用它；`ar` 直接用 `native/llvm/bin/llvm-ar.exe`。）

### 2.3 cargo 配置（放在 `core/doh_proxy/.cargo/config.toml`，或工作区级 `--config`）

```toml
[target.aarch64-unknown-linux-ohos]
linker = "C:/Users/iceblock/fluxdo/tools/ohos/cc/cc-aarch64-ohos.bat"
ar = "D:/DevEco Studio/sdk/default/openharmony/native/llvm/bin/llvm-ar.exe"

[target.x86_64-unknown-linux-ohos]
linker = "C:/Users/iceblock/fluxdo/tools/ohos/cc/cc-x86_64-ohos.bat"
ar = "D:/DevEco Studio/sdk/default/openharmony/native/llvm/bin/llvm-ar.exe"
```

> 注意：路径含空格，TOML 字符串必须加引号；`linker` 指向 `.bat` 时 cargo 会通过 `cmd` 调用，可正常工作。

### 2.4 带 C 代码的 crate（ring / aws-lc-rs / dav1d 等）需要的环境变量

```powershell
. C:\Users\iceblock\fluxdo\tools\env.ps1
$OHOS = 'D:\DevEco Studio\sdk\default\openharmony\native'
$env:CC_aarch64_unknown_linux_ohos  = 'C:\Users\iceblock\fluxdo\tools\ohos\cc\cc-aarch64-ohos.bat'
$env:AR_aarch64_unknown_linux_ohos  = "$OHOS\llvm\bin\llvm-ar.exe"
$env:CC_x86_64_unknown_linux_ohos   = 'C:\Users\iceblock\fluxdo\tools\ohos\cc\cc-x86_64-ohos.bat'
$env:AR_x86_64_unknown_linux_ohos   = "$OHOS\llvm\bin\llvm-ar.exe"
# CMake 系 crate（aws-lc-sys 等）
$env:CMAKE_TOOLCHAIN_FILE = "$OHOS\build\cmake\ohos.toolchain.cmake"
$env:OHOS_ARCH = 'arm64-v8a'          # x86_64 目标时改 x86_64
$env:PATH = "$OHOS\build-tools\cmake\bin;$env:PATH"   # cmake.exe / ninja.exe
```

### 2.5 关键事实与风险

1. **`ring` 0.17.14（doh_proxy 默认 TLS 后端）可以编 OHOS**：ring 的 target 判定用 `CARGO_CFG_TARGET_OS == "linux"`，OHOS triple 正好是 `os=linux/env=ohos`，所以 asm 走 `linux64` 分支；历史上 ring 编 OHOS 失败（briansmith/ring#2122）的唯一原因是 **没有设置 `TARGET_CC`/`CC_<target>`**（用宿主 MSVC 编出 aarch64 目标文件，lld 报 `incompatible with aarch64linux`）。按 §2.4 设置 CC 即可（该 issue 已关闭，评论区确认可行）。
2. **`aws-lc-rs` 也支持 OHOS**：上游 PR aws/aws-lc-rs#434 `feat: support openharmony platform`（2024-06 合入），另有 #456 修 armv7a/x86_64 的 asm 参数。所以 ECH（`doh_proxy` 的 `ech` feature）与 rhttp 的 `rustls/aws_lc_rs` 都不是死路，但需要 CMake 交叉编译，属 P1。
3. **`panic` 策略**：`doh_proxy` 的 `[profile.release] panic = "abort"`。作为进程内 `cdylib`，任何 Rust panic 会直接 SIGABRT 杀掉 Flutter 进程。建议 OHOS profile 覆盖为 `panic = "unwind"`（或至少在 CI 用 `--config profile.release.panic=\"unwind\"`），并在 FFI 入口用 `catch_unwind` 兜底。`native_animated_image` 已明确用 `panic = "unwind"` + `catch_unwind`，可直接沿用。
4. **TLS 模拟**：`has_thread_local=false`、`tls_model=Emulated`，tokio 多线程运行时可用，但 TLS 访问走 `__emutls`，性能略降；不要用依赖真实 `#[thread_local]` 的 C 库。
5. **双 ABI**：模拟器 `x86_64-unknown-linux-ohos` → `ohos/entry/libs/x86_64/`；真机 `aarch64-unknown-linux-ohos` → `ohos/entry/libs/arm64-v8a/`。CI/本地都要出两份，否则 `flutter build hap --target-platform ohos-x64` 时缺库会在运行期 `DynamicLibrary.open` 失败。

### 2.6 产物校验（不需要设备）

```powershell
# 架构 / 动态依赖
& "$OHOS\llvm\bin\llvm-readelf.exe" -h target\aarch64-unknown-linux-ohos\release\libdoh_proxy.so
& "$OHOS\llvm\bin\llvm-readelf.exe" -d target\aarch64-unknown-linux-ohos\release\libdoh_proxy.so
# 导出符号（FFI 必须是 C 符号，不能带 hash 后缀）
& "$OHOS\llvm\bin\llvm-nm.exe" -D --defined-only target\aarch64-unknown-linux-ohos\release\libdoh_proxy.so | Select-String 'doh_proxy_'
# HAP 打包后确认 .so 真的进包（HAP 是 zip）
tar -tf build\ohos\...\entry-default-unsigned.hap | Select-String 'libs/'
```

---

## 3. 组件 1：`core/doh_proxy`（Rust DoH/ECH 代理）

### 3.1 现状（源码事实）

- 仓库：git submodule `core/doh_proxy` → `https://github.com/Lingyan000/fluxdo_doh.git`（本工作区未 init，需 `git -c http.sslBackend=openssl submodule update --init core/doh_proxy`）。
- crate：`Cargo.toml` `crate-type = ["rlib","cdylib","staticlib"]`，bin `doh_proxy_bin`（桌面进程模式）+ `gen_ca`；`[features] default=[]`，`ech = ["rustls/aws_lc_rs","dep:aws-lc-rs"]`；release `panic="abort"`、`strip=true`、`lto=true`。
- FFI（`src/ffi.rs`）：纯 `#[no_mangle] pub extern "C"`，参数 `c_int`/`*const c_char`，无 JNI/NAPI。导出 **19** 个符号（`grep -c '#\[no_mangle\]'`）：
  `doh_proxy_start_with_config_json`、`doh_proxy_start_with_server`、`doh_proxy_start`、`doh_proxy_stop`、`doh_proxy_is_running`、`doh_proxy_get_port`、`doh_proxy_set_ech_dns_policy_json`、`doh_proxy_lookup_ech_config`、`doh_proxy_lookup_ip`、`doh_proxy_lookup_host`、`doh_proxy_record_host_success`、`doh_proxy_clear_preferred_host_ip`、`doh_proxy_clear_dns_cache`、`doh_proxy_dns_cache_stats`、`doh_proxy_dns_cache_records`、`doh_proxy_generate_ca`、`doh_proxy_get_embedded_ca_pem`、`doh_proxy_free_string`、`doh_proxy_init_logging`。
- 日志：`doh_proxy_init_logging()` 里 `#[cfg(target_os="android")]` 用 `tracing-android`，其余平台用 `fmt` 到 stderr。OHOS 走 else 分支（stderr 在 HAP 里通常被丢弃）→ 首版日志看不到，需后续接 hilog（`ohos` crate 或 `OH_LOG_Print`）。
- CA：`src/cert.rs` 用 `include_str!("../certs/ca.crt")` / `ca.key` 编译期嵌入；`build.rs` 在证书缺失时调用 `openssl` CLI 生成并同步到 `../../assets/certs/proxy_ca.pem` 与 `android/app/src/main/res/raw/proxy_ca.der`；`gen_ca` bin 做同样的事。
- Dart 侧（`repo/lib/services/network/doh_proxy/`）：
  - `doh_proxy_ffi.dart`：`isAvailable` 仅 `Android/iOS/macOS/Windows`；`canFallbackToProcess` 仅桌面；`_loadLibrary()` 对 `Platform.isLinux` 用 `DynamicLibrary.open('libdoh_proxy.so')`，**没有 `isOhos` 分支**；符号查找全部 `try/catch`，可选符号（generate_ca/embedded_ca/stats/records）失败不影响主流程。
  - `doh_proxy_service.dart`：`isAvailable` 为 true 时走 **FFI + `Isolate.spawn`**（`_ffiIsolateEntry`），否则走 `Process.start(doh_proxy_bin)`；桌面 FFI 失败可回退进程。
  - `proxy_certificate.dart`：`SecurityContext.defaultContext.setTrustedCertificatesBytes(assets/certs/proxy_ca.pem)`（非 Android 路径）；`per_device_cert_service.dart` 通过 FFI `generate_ca` 生成设备级 CA。
  - `doh_resolver.dart`：DoH 解析主路径是纯 Dart（`dns_client`），Rust FFI 用于 ECH config / 共享缓存 / 优选 IP（`lookupHost` 等）。
  - `network_settings_service.dart`：启动本地代理（`_rustProxyService.start`），仅 Windows 走 `WindowsWebViewEnvironmentService.setProxy`；Android/iOS 走 `InAppWebView ProxyController`；OHOS 在 `_setWebViewProxy` 里因 `!isAndroid && !macOS14 && !iOS17` 提前 return（不会抛错）。
- 关键判断：**DoH 对 App 自身 HTTP 栈的价值（rhttp/dio 的 `dnsOverrides` + ECH）不需要本地 CONNECT 代理**；本地代理主要服务 WebView，而 OHOS WebView 无法设置应用级代理（见 §7.6），所以 OHOS 上「FFI 查询接口」是刚需，「本地代理 start()」是可选。

### 3.2 OHOS 可行性判断：**可行（P0，推荐真移植）**

理由：
1. FFI 是纯 C ABI，Dart 侧 `dart:ffi` 在 OHOS 上可用；`Isolate.spawn` + FFI 的模式在 OHOS 正常。
2. Rust target 是 Tier 2；`ring`/`aws-lc-rs` 均有 OHOS 支持路径；tokio/hyper/reqwest/hickory 都是纯 Rust（除 TLS 后端）。
3. 不依赖 JNI/NAPI/Java/ArkTS，不需要写插件壳；`.so` 放 `entry/libs/<abi>/` + `DynamicLibrary.open('libdoh_proxy.so')` 即可（与 `flutter_qjs` OHOS 同款做法）。
4. 无 `exec` 需求（FFI 在进程内），绕开了 HAP 内不能随意 `Process.start` 的限制。

### 3.3 具体移植步骤（可执行）

```powershell
. C:\Users\iceblock\fluxdo\tools\env.ps1
cd C:\Users\iceblock\fluxdo\repo

# 0) 取 submodule
git -c http.sslBackend=openssl submodule update --init core/doh_proxy

# 1) 预生成 CA（绕开 build.rs 调 openssl；沙箱里 openssl 不可用，见 §1）
#    方式 A（推荐，需先让 build.rs 不 panic，见下）：临时把 certs/ 用占位证书喂进去后跑 gen_ca
#    方式 B（本机有可用 openssl 时）：cd core/doh_proxy; cargo run --release --bin gen_ca
#    产物：core/doh_proxy/certs/{ca.crt,ca.key,ca.der} + repo/assets/certs/proxy_ca.pem
#    注意 assets/certs/proxy_ca.pem 被 .gitignore 忽略，但 pubspec 已声明该目录 → 必须在 flutter build 前存在

# 2) 构建（真机 arm64；模拟器把 target 换成 x86_64-unknown-linux-ohos）
cd core\doh_proxy
cargo build --release --lib --target aarch64-unknown-linux-ohos
cargo build --release --lib --target x86_64-unknown-linux-ohos

# 3) 落位（先创建 ohos 工程：flutter create --platforms ohos .）
New-Item -ItemType Directory -Force ..\..\ohos\entry\libs\arm64-v8a, ..\..\ohos\entry\libs\x86_64 | Out-Null
Copy-Item target\aarch64-unknown-linux-ohos\release\libdoh_proxy.so ..\..\ohos\entry\libs\arm64-v8a\
Copy-Item target\x86_64-unknown-linux-ohos\release\libdoh_proxy.so ..\..\ohos\entry\libs\x86_64\

# 4) 构建 HAP
cd ..\..
flutter build hap --debug --target-platform ohos-x64      # 模拟器
flutter build hap --release --target-platform ohos-arm64  # 真机
```

`build.rs` 建议改动（Lead 改 `core/doh_proxy`，不在本任务范围）：
- 增加 `[build-dependencies] rcgen`，证书缺失时用 rcgen 生成（与 `cert.rs` 同一套逻辑），避免依赖 `openssl` CLI；生成后同样写 `certs/`、`../../assets/certs/proxy_ca.pem`、`android/.../raw/proxy_ca.der`。
- 增加 OHOS 资源同步：`../../ohos/entry/src/main/resources/rawfile/proxy_ca.pem`（若将来 ArkTS 侧要信任 CA）。
- OHOS profile 覆盖 `panic = "unwind"`；`ffi.rs` 各入口 `std::panic::catch_unwind`。

### 3.4 最小验证方法（分层）

1. **符号/架构**：§2.6 的 `llvm-readelf -h/-d`、`llvm-nm -D`。
2. **纯 Dart 加载（无 UI）**：临时在 `main()` 早期加（debug 构建）：
   ```dart
   if (Platform.isOhos) {
     final lib = DynamicLibrary.open('libdoh_proxy.so');
     debugPrint('[DOH] loaded=${lib.lookup<NativeFunction<Int32 Function()>>('doh_proxy_get_port').asFunction<int Function()>()()}');
   }
   ```
   期望 hilog 输出 `loaded=0`（未启动）。
3. **解析接口**：设置页 → 网络设置打开 DoH，观察 `NetworkLogger` 的 `[DOH]` 日志与「DNS 缓存统计」页（`dnsCacheStats` 有数据即 FFI 通路正常）。
4. **代理启动**（可选）：`DohProxyService.instance.start(...)` 返回端口 > 0；`checkAlive()` 为 true。
5. **回归**：关闭 DoH → 代理 stop，`isRunning=false`，无崩溃。

### 3.5 降级方案（若首版编译/运行失败）

按「不崩溃 + 保留 UI」原则分两级：

- **D1（推荐兜底，成本最低）**：`DohProxyFfi.isAvailable` 保持不含 OHOS，`DohProxyService` 走「无 FFI、无进程」分支。但当前代码在 `isAvailable=false` 时会 `_startWithProcess()`，而 `_getExecutablePath()` 在非桌面返回 null → 只打日志 `doh_executableNotFound` 并返回 false。**需要在 `doh_proxy_service.start()` 最前面加 OHOS 早退**（返回 false + 友好错误），避免每次进设置页都尝试。DoH 解析自动落到纯 Dart `doh_resolver`（`dns_client` DoH），ECH 关闭；`NetworkSettingsService` 的 `_setWebViewProxy` 已自然 no-op。设置页保留 DoH 开关（Dart DoH 仍有效），**隐藏「ECH/公共 ECH 入口/证书安装/本地代理端口」等依赖 Rust 的区块**。
- **D2（彻底禁用）**：OHOS 上把 `pref_doh_enabled` 强制 false 并在网络设置页显示「当前平台暂不支持 DoH 网关」，全部走系统解析。仅当 D1 都不可行时使用（用户体验损失大，DoH 是产品卖点，不建议）。

### 3.6 对 lib/ 的改动点（精确到文件）

| 文件 | 改动 |
|------|------|
| `lib/services/network/doh_proxy/doh_proxy_ffi.dart` | ① `isAvailable` 增加 `Platform.isOhos`；② `_loadLibrary()` 增加 `else if (Platform.isOhos) return DynamicLibrary.open('libdoh_proxy.so');`；③ `canFallbackToProcess` 保持桌面三端（OHOS 不可进程回退）；④ 可选：`Platform.isLinux` 分支合并为 `isLinux \|\| isOhos` |
| `lib/services/network/doh_proxy/doh_proxy_service.dart` | ① `start()` 开头：`if (!DohProxyFfi.isAvailable && Platform.isOhos) { _lastError='OHOS 上需要 libdoh_proxy.so'; return false; }`（防止走进程模式）；② `stop()/checkAlive()` 已在 `isAvailable` 分支内，无需改；③ 可选：OHOS 上跳过 `_startWithProcess` 的日志噪音 |
| `lib/services/network/doh_proxy/proxy_certificate.dart` | OHOS 走非 Android 的 `_configureSecurityContext()`（加载 `assets/certs/proxy_ca.pem`）——无需改，但需保证资源存在；`_sendCaCertToNative` 仅在 iOS 调用，不影响 OHOS |
| `lib/services/network/doh_proxy/cert_preference_service.dart` | 无需改；`isPerDeviceRequired` 不含 OHOS → per-device 为可选项；建议 OHOS 默认关闭（嵌入式 CA + `SecurityContext` 已足够） |
| `lib/services/network/doh_proxy/per_device_cert_service.dart` | 无需改（依赖 `generate_ca` 符号，FFI 成功即可用） |
| `lib/services/network/doh_proxy/windows_cert_trust_service.dart` | 不改（Windows 专用） |
| `lib/pages/network_settings_page/**`（`doh_detail_settings_page.dart`、`widgets/doh_settings_card.dart`、`ios_cert_install_dialog.dart`） | 首版**不带 ECH** 时：ECH 区块按「平台能力」置灰/隐藏；`ios_cert_install_dialog` 仅 iOS；若走 D1，本地代理/证书区块隐藏 |
| `lib/services/network/doh/network_settings_service.dart` | 可选：OHOS 上跳过 `WebViewMitmPolicy` 相关告警与 `_setWebViewProxy`（现状已早退，仅减少无效调用）；若首版不带 ECH，`_effectiveEchServerUrl` 置 null |
| `lib/main.dart` | `ProxyCertificate.initialize()` 已在通用 futures 中，无需改；若 D1 则无需其他改动 |

---

## 4. 组件 2：`rhttp`（Rust HTTP 客户端，FRB 2.12）

### 4.1 现状

- `pubspec.yaml:196-200`：`rhttp: git url https://github.com/Lingyan000/rhttp_plus.git path rhttp`；`dependency_overrides: flutter_rust_bridge: 2.12.0`；锁文件 `rhttp 0.18.0`（git）、`flutter_rust_bridge 2.12.0`。
- `rhttp/rust/Cargo.toml`：`crate-type=["cdylib","staticlib"]`；`flutter_rust_bridge = "=2.12.0"`；`rustls 0.23 features=["aws_lc_rs","std"]`；`reqwest 0.13.4`（http2/http3/rustls/brotli/zstd/…）；`[target.'cfg(target_os="android")'.dependencies] jni/ndk-context/rustls-platform-verifier`（OHOS 不会命中，正好）。
- 构建：`rhttp/cargokit`（Android/iOS/macOS/Windows/Linux），无 OHOS；`flutter_rust_bridge.yaml` 为 codegen 配置。
- Dart 加载：`rhttp/lib/src/rust/frb_generated.dart` 的 `kDefaultExternalLibraryLoaderConfig(stem:'rhttp', ioDirectory:'rust/target/release/')`，实际加载由 `flutter_rust_bridge/src/loader/_io.dart` 完成：
  - Android → `lib$stem.so`；Windows/macOS/Linux → `rust/target/release/...`；**其他平台直接 `throw Exception('loadExternalLibrary failed: Unknown platform=...')`（2.12.0 `_io.dart:84-86`）**。OHOS 会命中这个 throw。
- App 侧：`lib/main.dart:126 _initRhttp() => rhttp.Rhttp.init()`，用 5s 超时包裹，失败 → `RhttpSettingsService.instance.forceDisable()`；`rhttp_enabled` 默认 **false**（`rhttp_settings_service.dart:19`），所以默认不会走到 rhttp。`lib/services/network/adapters/rhttp_adapter.dart` 是 Dio 适配器，依赖 `RhttpSettingsService.shouldUseRhttp`（enabled && !forceDisabled）。
- `Rhttp.init()` 之外的 FRB 调用（`RhttpClient` 创建等）也走同一加载器，一旦 `.so` 加载成功即可用。

### 4.2 OHOS 可行性判断：**可移植（P1）**

- Rust 侧可编：依赖里唯一「C 依赖」是 aws-lc-rs（OHOS 上游支持，需 CMake），其余（reqwest/quinn/rustls-pemfile/webpki-root-certs/tokio/FRB）纯 Rust。
- 无需重新 codegen：现有 `frb_generated.*.dart` 与 Rust 端 API 一一对应，只需为 OHOS 重新编译 Rust cdylib。
- 卡点只有两个：① FRB 2.12 Dart 加载器不认 `ohos`；② cargokit 无 OHOS（手工构建即可绕过）。

### 4.3 具体移植步骤

```powershell
# 1) vendored FRB：把 pub 的 flutter_rust_bridge 2.12.0 复制进仓库（packages/ohos/flutter_rust_bridge/）
#    修改 lib/src/loader/_io.dart，在 Platform.isLinux 分支后追加：
#    if (Platform.operatingSystem == 'ohos') {
#      final name = 'lib$stem.so';
#      return tryAssumingNonPackaged(name, (d) => ExternalLibrary.open(name, debugInfo: d));
#    }
#    pubspec.yaml 增加：
#      dependency_overrides:
#        flutter_rust_bridge:
#          path: packages/ohos/flutter_rust_bridge

# 2) 构建 rhttp Rust（在 rhttp_plus/rhttp/rust 下，使用 §2.4 环境）
cd C:\Users\iceblock\fluxdo\.cache\research\rhttp_plus\rhttp\rust   # 或 Lead 放到 repo/packages/ohos/rhttp
cargo build --release --lib --target aarch64-unknown-linux-ohos
cargo build --release --lib --target x86_64-unknown-linux-ohos
# 产物 librhttp.so
Copy-Item target\aarch64-unknown-linux-ohos\release\librhttp.so C:\Users\iceblock\fluxdo\repo\ohos\entry\libs\arm64-v8a\
Copy-Item target\x86_64-unknown-linux-ohos\release\librhttp.so C:\Users\iceblock\fluxdo\repo\ohos\entry\libs\x86_64\
```

注意：
- `rhttp` 的 `rustls` 用 `aws_lc_rs`，交叉编译需要 `CMAKE_TOOLCHAIN_FILE` + `OHOS_ARCH`（§2.4）。若 aws-lc 编译受阻，可临时把 rhttp 的 rustls feature 改为 `ring`（`rustls = { version="0.23", default-features=false, features=["ring","std"] }`，并去掉 `aws_lc_rs` 引用），功能等价（除部分 cipher/性能差异），改的是 **rhttp 的 Rust 源码**（vendored 一份即可）。
- 不需要给 rhttp 加 `ohos` platform：`.so` 手工落位 + 补 FRB 加载器即可；pub 仍按原 git 依赖解析。
- 若要求 `flutter run` 热重载也能加载（debug 模式），`tryAssumingNonPackaged` 会先找 `rust/target/release/librhttp.so`（Dart CWD 下），在 OHOS 上 CWD 不可写/不适用 → 直接 `DynamicLibrary.open('librhttp.so')` 走系统库路径（HAP libs），所以顺序要把 OHOS 判断放最前或允许 fallback 抛错后再 open。

### 4.4 最小验证

```powershell
# 设备/模拟器上，debug 构建，设置页临时把 rhttp 打开（或 main 里强制调用）
# 期望 hilog 出现 rhttp 初始化成功；再发一个 HTTP/2 请求（首页加载即走 rhttp）
hdc shell hilog -T rhttp
# 失败特征：'loadExternalLibrary failed: Unknown platform=ohos'（说明 FRB 未 patch）
# 或 'dlopen failed: library "librhttp.so" not found'（说明 .so 未进包/abi 不对）
```

### 4.5 降级方案

- **D1（首版默认，零改动）**：保持 `rhttp_enabled=false` 默认值；`_initRhttp()` 的异常已被捕获并 `forceDisable`，不会崩。OHOS 设置页隐藏「网络引擎（rhttp）」卡片（`engine_card.dart` 按 `Platform.isOhos` 隐藏/置灰），避免用户开启后报错。
- **D2（不隐藏但明确提示）**：允许打开，失败时 `forceDisable` 已有机制 + toast「当前平台 rhttp 不可用」，用户可继续用 dio/cronet 路径。
- 注意：rhttp 关闭时 `doh_resolver` 仍提供 DoH（纯 Dart），功能不致命。

### 4.6 对 lib/ 的改动点

| 文件 | 改动 |
|------|------|
| `pubspec.yaml`（Lead 统一改） | 新增 `packages/ohos/flutter_rust_bridge` path override（2.12.0 副本 + OHOS 分支） |
| `packages/ohos/flutter_rust_bridge/lib/src/loader/_io.dart`（新增 vendored 包） | 追加 `ohos` 分支（见 §4.3 代码） |
| `lib/main.dart` | 可选：OHOS 上跳过 `_initRhttp()`（省一次必然失败的加载）；`Platform.isOhos` 时直接 `forceDisable` |
| `lib/pages/network_settings_page/widgets/engine_card.dart` | `Platform.isOhos` 时隐藏或标注「HarmonyOS 暂不支持」 |
| `lib/services/network/rhttp/rhttp_settings_service.dart` | 可选：`shouldUseRhttp` 增加 `if (Platform.isOhos && !RhttpSupport.ohosBuilt) return false;`（用一个编译期/运行期能力开关） |
| `lib/services/network/adapters/rhttp_adapter.dart` | 不改（能力判断已在 settings 层） |

---

## 5. 组件 3：`flutter_js` + Discourse cook 渲染 + `render_backend_service`

### 5.1 现状

- `pubspec.yaml:49` `flutter_js: ^0.8.7`（锁 0.8.7）；用途：`lib/services/cook/cook_js_engine_io.dart` 里 `getJavascriptRuntime(xhr:false)` + `runtime.evaluate(code)` 同步取字符串；`cook_js_engine_stub.dart` 是 web 实现（恒不可用）。
- `lib/services/discourse_cook_service.dart`：条件导入 `if (dart.library.io) cook_js_engine_io.dart`；`_initialize()` 先判 `cookJsSupported`，再 `rootBundle.loadString('assets/cook/discourse-cook.js')`（567,475 B，IIFE，`globalThis.__fluxdoCook`），`eval` + `__fluxdoCook.init(json)` + 后续 `cook()/parseForEditor()`；**任何失败返回 null，调用方降级到 Dart 近似预览**（文件头注释明确）。
- `assets/cook/discourse-cook.js` 由 `tools/discourse-cook-bundle/build.mjs` 用 esbuild 打包 Discourse 官方管线，产物入仓，与 JS 引擎无关（只要引擎支持 ES2020 级别语法）。
- `assets/polyfill/compat-polyfill.js` 由 `tools/polyfill-bundle` 生成，**仅给老 WKWebView（iOS 15）用**，与 cook 无关；OHOS ArkWeb 是新 Chromium 内核，不需要注入。
- `lib/services/render_backend_service.dart`：`static bool get _supported => !kIsWeb && Platform.isAndroid;` → 所有方法在 OHOS 直接 return（Android GLES 兼容模式 / Mali 崩溃检测），**无需移植**。
- `flutter_js` 引擎实现：Android 走 prebuilt AAR `com.github.fast-development.android-js-runtimes:fastdev-jsruntimes-quickjs:0.3.6`（pub 包内没有 quickjs C 源码，`android/build.gradle` 里 externalNativeBuild 被注释），Dart 用 `DynamicLibrary.open('libfastdev_quickjs_runtime.so')`（`lib/quickjs/ffi.dart:116`）；iOS/macOS 用 JavaScriptCore；Windows/Linux 用随包 `.dll`/`.so`。**无 OHOS 平台、无 OHOS 二进制**。
- OHOS 已有可用替代：`fluttertpc_flutter_qjs`（`https://gitcode.com/CPF-Flutter/fluttertpc_flutter_qjs`，tag `0.3.7-ohos.1.0.0-beta.1`；`ohos/` HAR + `cxx/quickjs.cmake` 编出 `libqjs.so`；Dart 侧 OHOS 上 `DynamicLibrary.open('libqjs.so')`，`lib/src/ffi.dart:139-141`）。

### 5.2 OHOS 可行性判断

| 方案 | 判断 | 成本 |
|------|------|------|
| A. 首版降级：OHOS 上 `cookJsSupported=false` | **可行（推荐 v1）** | 1 行改动；编辑器预览退回 Dart 近似管线（`DiscourseCookService` 注释承诺的降级路径），阅读/渲染不受影响 |
| B. 用 `fluttertpc_flutter_qjs` 替换 `flutter_js` | **可行（推荐 v2）** | `cook_js_engine_io.dart` 只有 40 行，重写 `CookJsEngine` 用 `FlutterQjs().evaluate()`（同步、异常抛 `JSException`），并把 `cookJsSupported` 在 OHOS 置 true；注意 flutter_qjs 的 JSValue→Dart 转换与 flutter_js 不同，但 cook 只取 `String` 返回值 |
| C. 自编译 QuickJS `.so` 继续用 `flutter_js` | 可行但最贵 | 需要拿到 fastdev-jsruntimes-quickjs 的 C++ 包装层 + quickjs 源码，用 OHOS CMake 编 `libfastdev_quickjs_runtime.so`，并补 `lib/quickjs/ffi.dart` 的 OHOS 分支；不如方案 B |

### 5.3 具体步骤

**A（v1 降级，必做）**：`lib/services/cook/cook_js_engine_io.dart`

```dart
import 'dart:io' show Platform;
// ...
/// OHOS 首版没有 QuickJS 二进制；返回 false 让 DiscourseCookService 走 Dart 降级。
final bool cookJsSupported = !Platform.isOhos;
```

并把 `CookJsEngine` 构造函数里的 `getJavascriptRuntime()` 也包一层（防被其他路径调用）——更稳妥的是 `DiscourseCookService` 已先判 `cookJsSupported`，无需改。

**B（v2 真移植）**：

```yaml
# pubspec.yaml（Lead 改）
dependencies:
  flutter_qjs:
    git:
      url: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_qjs
      ref: 0.3.7-ohos.1.0.0-beta.1
```

```dart
// lib/services/cook/cook_js_engine_io.dart（OHOS 版实现草图）
import 'package:flutter_qjs/flutter_qjs.dart';
import 'dart:io' show Platform;

final bool cookJsSupported = true; // OHOS 上也可用

class CookJsEngine {
  final FlutterQjs _runtime = FlutterQjs();
  String? evaluate(String code, {void Function(String error)? onError}) {
    try {
      final r = _runtime.evaluate(code);
      return r is String ? r : r?.toString();
    } catch (e) { onError?.call(e.toString()); return null; }
  }
}
```

注意：
- flutter_qjs 的 `evaluate` 返回 Dart 原生值（String/num/bool/List/Map），cook 管线全返回 String，兼容。
- `FlutterQjs()` 内部会创建 isolate/引擎，`dispatch()` 用于事件循环；cook 是同步纯计算，可不 dispatch。
- 引擎内存：QuickJS 实例常驻，与 flutter_js 行为一致。
- 若同时保留 `flutter_js`（Android/iOS/桌面）和 `flutter_qjs`（OHOS），用条件导入拆文件：`cook_js_engine_quickjs.dart` vs `cook_js_engine_flutter_js.dart`，按 `Platform.isOhos` 选择（编译期无法区分，只能运行期分支 + 两个包都依赖；或 pubspec 同时依赖两包，包体增量可接受）。

### 5.4 最小验证

- 降级路径：OHOS 上打开「写回复 → 预览」，日志应出现 `[DiscourseCook] 站点数据未就绪` 或直接走 Dart 预览，**不崩溃、预览可用**（近似排版）。
- 真移植路径：日志出现 `[DiscourseCook] 初始化完成`；对比同一篇帖子在 Android 与 OHOS 的预览 HTML 差异（`__fluxdoCook.cook` 输出）。
- 快速引擎自检（不依赖站点数据）：debug 页面临时 `CookJsEngine().evaluate('1+2')` 应返回 `"3"`。

### 5.5 降级方案

- 已内建：`DiscourseCookService.cook()` 返回 null → 调用方用 Dart 近似预览；`ensureInitialized` 失败后本次进程不再重试大 bundle（`_unavailable=true`）。
- OHOS 额外保护：`_initialize()` 的 `try/catch` 已覆盖 `getJavascriptRuntime()` 抛错（MissingPluginException/ArgumentError），但 `cook_js_engine_io.dart` 顶层 `getJavascriptRuntime` 是构造函数内调用 → 已被 `_initialize` 的 try 包住，不会崩启动。

### 5.6 对 lib/ 的改动点

| 文件 | 改动 |
|------|------|
| `lib/services/cook/cook_js_engine_io.dart` | v1：`cookJsSupported = !Platform.isOhos`（或 try/catch 包住 runtime 创建）；v2：OHOS 分支改用 `FlutterQjs` |
| `lib/services/cook/cook_js_engine_stub.dart` | 不改（web 用） |
| `lib/services/discourse_cook_service.dart` | v1 不改（已有 `cookJsSupported` 判断 + 降级）；v2 可选：增加 OHOS 日志 |
| `lib/services/render_backend_service.dart` | 不改（`_supported` 已排除 OHOS） |
| `pubspec.yaml` | v2 增加 `flutter_qjs` git 依赖（或换掉 flutter_js 的 OHOS 平台） |
| `tools/polyfill-bundle`、`assets/polyfill/compat-polyfill.js` | 不改；OHOS WebView 不需要（可在 `WebViewSettings.preloadPolyfill` 里按 `Platform.isOhos` 跳过注入，省 30-60KB 解析） |
| `tools/discourse-cook-bundle` | 不改（引擎无关产物） |

---

## 6. 组件 4：`native_animated_image` 与 `flutter_avif`

### 6.1 `native_animated_image`（Rust 动图解码）

**现状**
- `pubspec.yaml:53` `native_animated_image: ^0.3.4`（锁 0.3.4）；用于 `lib/widgets/common/cached_image.dart`、`lib/services/discourse_cache_manager.dart`、`lib/services/sticker_thumbnail_provider.dart`、`lib/main.dart`（首帧 gate）。
- 包结构：`native_animated_image` 是联邦式「壳包」，依赖 `native_animated_image_{android,ios,macos,windows,linux}`；FFI 逻辑在壳包 `lib/src/ffi/`，**6 个 C 符号**：`native_animated_image_decode/get_metadata_json/get_frame_rgba/release/free_string/version`。
- 加载器（`lib/src/ffi/native_animated_image_bindings.dart:81-97`）：iOS `process()`、macOS `.dylib`、`isAndroid || isLinux` → `libnative_animated_image_codec.so`、Windows `.dll`、**其他平台 `throw UnsupportedError`**。
- Rust crate（`crates/native_animated_image_codec`）：`gif 0.13` + `png 0.18` + `image-webp 0.2` + serde + parking_lot，**纯 Rust、无 C/asm/网络**；`release panic="unwind"` + FFI 内 `catch_unwind`（注释明确说明避免 abort 杀进程）；AVIF 在 v0.3.0 已移除（避免 rav1d ARM SIMD panic）。
- 说明：v0.3.4 的壳包 pubspec 里没有 ohos 平台，`flutter pub get` 不会为 OHOS 注册任何实现，但 FFI 逻辑与平台包无关（平台包只负责把 `.so` 塞进各平台构建系统）。

**OHOS 可行性：可行且成本最低（P1）**
- 纯 Rust，`cargo build --target *-unknown-linux-ohos` 即可（无 CC/CMake 依赖）。
- 只需：编译 `.so` + 给加载器加 OHOS 分支；无需联邦平台包。

**步骤**

```powershell
. C:\Users\iceblock\fluxdo\tools\env.ps1
cd C:\Users\iceblock\fluxdo\.cache\research\native_animated_image   # 或 vendored 到 repo/packages/ohos/native_animated_image
cd crates\native_animated_image_codec
cargo build --release --target aarch64-unknown-linux-ohos
cargo build --release --target x86_64-unknown-linux-ohos
Copy-Item target\aarch64-unknown-linux-ohos\release\libnative_animated_image_codec.so C:\Users\iceblock\fluxdo\repo\ohos\entry\libs\arm64-v8a\
Copy-Item target\x86_64-unknown-linux-ohos\release\libnative_animated_image_codec.so C:\Users\iceblock\fluxdo\repo\ohos\entry\libs\x86_64\
```

Dart 侧二选一：
1. **推荐**：vendored `native_animated_image`（path override），加载器加：
   ```dart
   if (Platform.operatingSystem == 'ohos') {
     return DynamicLibrary.open('libnative_animated_image_codec.so');
   }
   ```
2. 不改包：在 `lib/main.dart` 早期用 `NativeAnimatedImageProvider` 之前设置自定义 loader —— 但该包没有 loader 注入点，只能改包/改源码。→ 用 vendored 包。

**降级方案**：OHOS 上不使用 `NativeAnimatedImageProvider`，改用 Flutter 内置 `Image.network`/`ImageProvider`（会重新暴露 Skia multi-frame codec 的 `#85831` 问题：部分 disposal/透明 GIF 出现 `Could not getPixels for frame N`）。实现方式：`cached_image.dart` 里 `Platform.isOhos` 分支返回普通 provider；或让 FFI 加载失败时 `NativeAnimatedImageProvider` 抛错 → 外层 `errorBuilder` 已有兜底则直接显示静态首帧。**不推荐 v1 不做**（体验差距明显，但成本仅几小时）。

**验证**：打开含动画 GIF/APNG/WebP 的帖子与表情包（sticker 网格），观察是否逐帧播放、无 crash；`hilog` 中 `NativeAnimatedImageProvider` 不应抛 `UnsupportedError`。

### 6.2 `flutter_avif`（libavif + dav1d）

**现状**
- `pubspec.yaml:143` `flutter_avif: ^3.1.0`（锁 3.1.0）+ 显式 `flutter_avif_platform_interface: ^3.1.0`（`lib/services/avif_fast_bridge.dart` 直连其 FFI 符号表）。
- 联邦结构：`flutter_avif`（壳）→ `flutter_avif_{android,ios,macos,linux,windows,web}`；每个平台包**内置预编译 `libflutter_avif.so`/`.dylib`/`.dll`**（Android `jniLibs/*/libflutter_avif.so`；Linux `linux/libflutter_avif.so`）。native 源码在 `fluttertpc_flutter_avif/rust/`：Rust cdylib 依赖 `libavif-sys`/`libdav1d-sys`（C，CMake 构建）+ protobuf FFI。
- CPF-Flutter 的 `fluttertpc_flutter_avif` 仓库**没有任何 `ohos/` 目录或分支**（只有 upstream 3.1.0 的 main），即 OHOS 适配**不存在**。
- App 侧（`lib/services/avif_image_provider.dart`）是两级后端：
  1. 静态 AVIF 先试**引擎内置 codec**（`_tryPlatformAvifCodec` → `ui.ImageDescriptor.encoded(...).instantiateCodec()`）；OHOS 引擎有 `OHOSImageGenerator`（`engine/src/flutter/shell/platform/ohos/ohos_image_generator.cpp`，基于 `OH_ImageSourceNative`/`OH_PixelmapNative`）作为平台图像解码兜底，**AVIF 能否解取决于系统 Image Kit**（Image Kit 文档明确列 HEIF/JPEG/PNG/WebP，「等主流格式」，未明确列 AVIF → **必须实测**）。
  2. 动画 AVIF / 平台不支持 → `AvifFastBridge`（`libflutter_avif.so` 符号直连）或 `fa.MultiFrameAvifCodec`。

**OHOS 可行性：高成本（P2）；v1 建议降级**
- 真移植需要：① 用 OHOS CMake 工具链交叉编译 dav1d + libavif（`ohos.toolchain.cmake`，`OHOS_ARCH=arm64-v8a/x86_64`）；② 用 `libavif-sys`/`libdav1d-sys` 的 CMake 集成把上述静态库链进 Rust cdylib（设置 `CMAKE_TOOLCHAIN_FILE`、`CMAKE_PREFIX_PATH`）；③ 编 `libflutter_avif.so`；④ 写一个 `flutter_avif_ohos` 平台包（`FlutterAvifPlatform` 实现，`DynamicLibrary.open('libflutter_avif.so')`）+ 壳包 pubspec 增加 `ohos: default_package`。估 1-2 人日，风险集中在 dav1d 的 asm/neon 与 CMake 交叉编译。
- 降级：v1 禁用 flutter_avif；静态 AVIF 若引擎能解则体验无损（且 `AvifImageProvider` 已优先走引擎），动画 AVIF 显示首帧/错误占位。

**v1 降级步骤（lib 改动）**

`lib/services/avif_image_provider.dart`：
```dart
// 在 _createCodec / decodeFirstFrame 的 flutter_avif 回退前加 OHOS 保护
if (Platform.isOhos) {
  // 引擎 codec 已失败 → OHOS 首版没有 libflutter_avif.so，直接抛可捕获错误，
  // 由 ImageProvider 的 errorBuilder 显示占位，避免 DynamicLibrary.open 抛未捕获异常。
  throw UnsupportedError('AVIF decoder not available on OHOS');
}
```
（`AvifFastBridge.available` 也应加 `!Platform.isOhos`，否则 `FlutterAvifFFI(DynamicLibrary.open(...))` 在静态初始化时抛错。）

**验证**：打开含 `.avif` 的帖子（静态 + 动画各一）。静态图能显示 → 说明 OHOS ImageSource 支持 AVIF，v1 可接受；不能显示 → 需 P2 真移植或产品层降级（发帖端避免 AVIF）。

**真移植步骤（P2，概要）**
```powershell
# dav1d
git -c http.sslBackend=openssl clone https://code.videolan.org/videolan/dav1d.git
cmake -S dav1d -B dav1d/build-ohos-arm64 -G Ninja ^
  -DCMAKE_TOOLCHAIN_FILE="D:/DevEco Studio/sdk/default/openharmony/native/build/cmake/ohos.toolchain.cmake" ^
  -DOHOS_ARCH=arm64-v8a -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTS=OFF
cmake --build dav1d/build-ohos-arm64
# libavif：-DAVIF_CODEC_DAV1D=ON -DDAVIF_BUILD_APPS=OFF，CMake 同样指定 toolchain
# 然后 rhttp 风格：libavif-sys 的 build.rs 通过 CMAKE_TOOLCHAIN_FILE 找到 dav1d；最后 cargo build --target aarch64-unknown-linux-ohos
```
（详细命令在实施时以 `libavif-sys` 的 `build.rs` 实际变量名为准。）

**对 lib/ 的改动点**

| 文件 | 改动 |
|------|------|
| `lib/services/avif_image_provider.dart` | OHOS 上跳过 flutter_avif 回退（抛 `UnsupportedError`），保留引擎 codec 优先路径 |
| `lib/services/avif_fast_bridge.dart` | `available` 增加 `!Platform.isOhos`（v1）；P2 改为从 `flutter_avif_ohos` 取 `DynamicLibrary` |
| `pubspec.yaml` | v1 不改（flutter_avif 仍作为其他平台依赖）；P2 增加 `flutter_avif_ohos` 或 vendored 平台包 |

---

## 7. 组件 5：视频/音频/相机/WebView 链路

### 7.1 现状与 OHOS 对应物（版本对照）

| 包 | 锁定版本 | OHOS 实现（已核实） | 版本差 |
|----|----------|---------------------|--------|
| `video_player` | 2.14.0 | `openharmony-tpc/flutter_packages` 分支 `br_video_player-v2.11.1_ohos`（tag `video_player-v2.11.1-ohos-1.0.0`），含 `video_player_ohos`（Pigeon + ArkTS AVPlayer） | 2.14.0 → 2.11.1 |
| `just_audio` | 0.10.6 | `CPF-Flutter/fluttertpc_just_audio` 分支 `br_v0.10.6_ohos`（**实际 pubspec 版本 0.10.5**，`just_audio/ohos`） | 0.10.6 → 0.10.5 |
| `record` | 7.1.1 | `CPF-Flutter/fluttertpc_record` 分支 `br_3.41_dev`（**版本正好 7.1.1**，联邦包 `record_ohos`） | 一致 |
| `mobile_scanner` | 7.4.2 | `CPF-Flutter/fluttertpc_mobile_scanner` 分支 `br_v7.1.4_ohos`（版本 7.1.4，`ohos/` 存在） | 7.4.2 → 7.1.4 |
| `flutter_inappwebview` | 6.2.0-beta.3 | `CPF-Flutter/flutter_inappwebview` 分支 `br_v6.1.5_ohos`（版本 6.1.5，联邦包 `flutter_inappwebview_ohos`） | 6.2.0-beta.3 → 6.1.5 |
| `pro_image_editor` | 11.23.0 | 无原生实现需求（纯 Dart + shared_preferences；pubspec 仅声明 android 平台用于可选原生能力） | — |
| `video_player_media_kit` / `just_audio_media_kit` | 2.0.0 / 2.1.0 | 桌面（Windows/Linux）桥接；`ensureInitialized` 用 `universal_platform` 判断，OHOS 上**自动 no-op**（已读源码确认） | 不改 |
| `media_kit` / `media_kit_video` | 1.2.6 / 2.0.1 | `CPF-Flutter/fluttertpc_flutter_media_kit` 有 OHOS 适配，但需 libmpv；本仓库仅在 Windows/Linux 使用 | 不用 |

### 7.2 视频：`video_player`

**现状**：`lib/widgets/media_player/video/{discourse_video_player,video_playback_surface,video_player_session,fullscreen_video_page}.dart`、`controls/*` 使用 `VideoPlayerController`（`value.isPlaying/isCompleted/isBuffering/position/duration/buffered/volume/playbackSpeed`、`setVolume/setPlaybackSpeed/seekTo/setLooping`）——这些 API 在 2.11.1 全部存在，降级可行。
`main.dart:183-185`：仅 Windows/Linux 注册 `VideoPlayerMediaKit`；OHOS 上不注册 → 使用平台默认实现（需要 `video_player_ohos` 存在，否则 `VideoPlayerPlatform.instance` 仍是 MethodChannel 默认实现 → 运行时报 MissingPluginException）。

**步骤**
```yaml
# pubspec.yaml（Lead 改；用 git 覆盖，版本降到 2.11.1）
dependency_overrides:
  video_player:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/video_player/video_player
      ref: video_player-v2.11.1-ohos-1.0.0
  video_player_ohos:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/video_player/video_player_ohos
      ref: video_player-v2.11.1-ohos-1.0.0
```
注意：
- 该 fork 的 `video_player/pubspec.yaml` 已声明 `ohos: default_package: video_player_ohos`，并把 `video_player_ohos` 以 git 依赖指向同仓库分支；`video_player_platform_interface ^6.6.0` 与本仓库锁定的 6.9.0 兼容。
- 2.14.0 → 2.11.1 的差异需 `flutter analyze` 全量验证（目前看用到的 API 都在）；若 2.14 专属 API 被用到，需在 fork 上 cherry-pick。
- 权限：`module.json5` 加 `ohos.permission.INTERNET`（模板已有）。
- README 的兼容性声明到 Flutter 3.41.10-ohos；3.47.7 需实测（Pigeon 通道/引擎 API 一般稳定）。

**降级**：OHOS 上视频卡片显示「用浏览器打开」错误卡（`discourse_video_player.dart` 已有 initialize 失败的 error 分支）；不阻塞其他功能。

**改动点**：仅 pubspec（Lead）；`main.dart` 的 `VideoPlayerMediaKit` 注册条件保持不变（OHOS 不注册，正确）。

### 7.3 音频：`just_audio`

**现状**：`lib/widgets/content/audio/discourse_audio_player.dart`、`lib/widgets/markdown_editor/voice_recorder_sheet.dart`（播放录音）、`lib/services/audio/just_audio_gst.dart`（Linux 专用 GStreamer 桥，`main.dart:173-177` 仅 Linux 注册）。
`main.dart:173-177`：`if (Platform.isLinux) JustAudioGst.registerWith(); else JustAudioMediaKit.ensureInitialized(linux:false);` —— OHOS 走 else，但 `just_audio_media_kit` 的 `ensureInitialized` 用 `universal_platform` 判定 Windows/Linux/Android/iOS/macOS，OHOS 全部 false → **no-op**（已核实源码），所以不会错误覆盖 OHOS 实现。

**步骤**
```yaml
dependency_overrides:
  just_audio:
    git:
      url: https://gitcode.com/CPF-Flutter/fluttertpc_just_audio.git
      ref: br_v0.10.6_ohos
```
- 注意该分支实际版本 0.10.5；仓库锁 0.10.6。若 0.10.6 的新 API 被使用需检查（当前用法是标准 `AudioPlayer` API，风险低）。
- fork 的 `just_audio/pubspec.yaml` 已声明 `ohos` 平台，并依赖 `audio_session`（gitcode 分支）与 `path_provider`（gitcode），`flutter pub get` 会自动解析；若 Lead 统一改 pubspec，注意这些 git 依赖也要可达。

**降级**：OHOS 上音频条显示错误态（`discourse_audio_player` 初始化失败提示），语音录制失败会显示 `_error`（`voice_recorder_sheet` 已捕获 MissingPluginException）。**不会崩溃**。

### 7.4 录音：`record`

**步骤**
```yaml
dependency_overrides:
  record:
    git:
      url: https://gitcode.com/CPF-Flutter/fluttertpc_record.git
      ref: br_3.41_dev     # 版本 7.1.1，联邦 record_ohos
```
- 权限：`ohos.permission.MICROPHONE`（`module.json5`）。
- `record_ohos` 的 `RecordConfig` 支持 `aacLc`（仓库用 AAC-LC 32kbps/16kHz/mono）需实测；若不支持则降级为 `wav`（文件变大，可接受）。

**降级**：`voice_recorder_sheet` 已捕获异常并显示错误；不崩溃。首版若不想接，OHOS 上隐藏语音录制按钮。

### 7.5 图片编辑：`pro_image_editor`

- 纯 Dart（`http/shared_preferences/vector_math/web`），pubspec 只声明 android 平台（某些可选原生能力）。OHOS 上直接可用，需验证：裁剪/旋转/滤镜/导出 PNG、与 `image_picker`/`file_picker` OHOS 实现的协作。
- 无降级需求；若导出路径不可写，检查 `path_provider` OHOS 实现（`getTemporaryDirectory` 必须可用——这是 OHOS 必接插件，见 task-1）。

### 7.6 扫码：`mobile_scanner` 与相机

**现状**：`lib/pages/qr_login_scan_page.dart:46-47` `_supportsCamera = !kIsWeb && (isAndroid || isIOS || isMacOS)` → OHOS 为 false，页面自动走「相册选图 + `zxing2` 解码」路径（纯 Dart，全平台兜底，注释已写明）。
**步骤（真移植）**
```yaml
dependency_overrides:
  mobile_scanner:
    git:
      url: https://gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner.git
      ref: br_v7.1.4_ohos
```
并把 `_supportsCamera` 改为 `... || Platform.isOhos`（配合 fork 使用）。权限：`ohos.permission.CAMERA`。
**降级（v1）**：不改代码——相册扫码可用，登录流程不受阻；UI 上相机入口自然隐藏（`_supportsCamera=false`）。

### 7.7 WebView：`flutter_inappwebview`（P0）

**现状**：24 个文件 import；承担登录、CF 验证、Cookie 同步（`lib/services/network/cookie/*`）、Mermaid/iframe 渲染、Eruda。`pubspec.yaml:210-215` 已有 `flutter_inappwebview_linux/windows` 的 path override。
**步骤**
```yaml
dependency_overrides:
  flutter_inappwebview:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git
      ref: br_v6.1.5_ohos
  flutter_inappwebview_ohos:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git
      path: flutter_inappwebview_ohos
      ref: br_v6.1.5_ohos
```
- 版本 6.2.0-beta.3 → 6.1.5：`flutter analyze` 全量验证；重点检查仓库用到的 beta API（`InAppWebViewSettings` 新字段、`WebViewEnvironment`、`PlatformWebView` 等）。
- 能力核对（已看 fork 源码文件树）：
  - ✅ `CookieManager`（`flutter_inappwebview_ohos/lib/src/cookie_manager.dart`）→ Cookie 同步链路可移植。
  - ✅ `HeadlessInAppWebView`、`InAppBrowser`、`evaluateJavascript`。
  - ❌ **无 `ProxyController`/`setProxyOverride`**（fork 里没有 proxy 相关文件）→ OHOS WebView 无法走本地 DoH 网关/MITM。
- 因此 OHOS 上：**App API 流量走 DoH（rhttp/dio + doh_resolver），WebView 流量走系统解析**。在 DNS 污染环境下 WebView 登录/CF 可能更易失败，需产品层提示；后续若 ArkWeb 提供应用级代理能力再补。

**降级**：WebView 登录页失败时已有「用系统浏览器登录」/手动 Cookie 兜底路径（`browser_trust_coordinator`、`raw_cookie_writer_fallback`）；不崩溃。

---

## 8. 组件 6：通知/后台/更新/剪贴板/桌面专用插件

### 8.1 本地通知：`flutter_local_notifications`

- 现状：`lib/services/local_notification_service.dart`，`InitializationSettings(android/iOS/macOS/linux/windows)` + `NotificationDetails`；用于聊天通知、APK 更新进度、iOS 后台拉取。
- OHOS fork：`CPF-Flutter/fluttertpc_flutter_local_notifications` 分支 `br_3.41_dev`（版本 **22.0.1**，含 `flutter_local_notifications/ohos/`，Dart API 提供 `OhosInitializationSettings(defaultIcon)`、`OhosNotificationDetails`）。
- 步骤：
  ```yaml
  dependency_overrides:
    flutter_local_notifications:
      git:
        url: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_local_notifications.git
        ref: br_3.41_dev
  ```
  ```dart
  // local_notification_service.dart
  const ohosSettings = OhosInitializationSettings('app_icon'); // 图标放 resources/base/media
  const settings = InitializationSettings(
    android: androidSettings, iOS: darwinSettings, macOS: darwinSettings,
    linux: linuxSettings, windows: windowsSettings,
    ohos: ohosSettings,
  );
  // NotificationDetails 里同样补 ohos: OhosNotificationDetails(...)
  ```
- 版本 21.0.0 → 22.0.1：`initialize(settings:)` 命名参数已在仓库使用，兼容性较好；`flutter analyze` 验证。
- 权限：通知授权由插件调用 `notificationManager.requestEnableNotification()`；`module.json5` 无需特殊权限（普通通知）。
- 降级：插件不可用时 `initialize()` 抛错 → 包 try/catch（当前无 try/catch，**需加**，否则启动崩溃风险）；通知功能失效但不阻塞。

### 8.2 后台保活：`flutter_foreground_task` + `workmanager`

- 现状：`lib/services/background/background_notification_service.dart`：Android → 前台服务（`flutter_foreground_task`）+ 主 isolate MessageBus 长轮询；iOS → `workmanager` BGTaskScheduler；桌面 → 无操作。`enable()` 只在 `Platform.isAndroid/isIOS` 分支动作 → OHOS 天然 no-op。
- OHOS 判断：**均不可用**。`flutter_foreground_task` 的 CPF 仓库（`fluttertpc_flutter_foreground_task`）master 与 `br_3.35_dev` 分支均**没有 `ohos/` 目录**（未逐一验证 `dev`）；`workmanager` 只支持 Android/iOS/macOS（pub.dev 平台声明）。
- 降级：OHOS 保持「前台通知轮询」（App 在前台时 MessageBus 工作）；切后台后不再有实时通知。后续可选：用 ArkTS 写 `ohos` 平台包（ContinuousTask 长时任务 + `backgroundTaskManager` 申请），或使用推送（厂商推送）——不在首版范围。
- 改动点：`background_notification_service.dart` 无需改（分支天然跳过）；设置页「后台通知」开关在 OHOS 上隐藏或标注「HarmonyOS 暂不支持后台保活」。

### 8.3 应用更新：`ota_update`

- 现状：`lib/services/apk_download_service.dart`（APK 下载 + 安装）、`lib/services/update_service.dart`（检查 GitHub release）。
- OHOS 判断：fork `CPF-Flutter/fluttertpc_ota_update` 有 `ohos/`（`br_3.41_dev` 版本 7.1.0，与仓库一致），但 **OHOS 普通应用没有「静默下载 APK 并安装」等价能力**：HAP 更新需应用市场或用户手动安装，`bundleManager` 不允许应用自更新（系统应用除外）。
- 降级（v1）：
  - OHOS 上隐藏「检查更新/下载安装」入口（`update_service` 平台判断）；
  - 或改为「打开应用市场详情页 / 打开浏览器下载页」（`url_launcher` OHOS 实现 + `AppLinking` 到 AppGallery）。
  - `ApkDownloadService` 只在 Android 调用（检查调用点，`Platform.isAndroid` 门控），确认 OHOS 不会进入。

### 8.4 深链：`app_links`

- fork `CPF-Flutter/fluttertpc_app_links` 分支 `br_7.2.2_ohos_dev`（版本 7.2.2，`app_links/ohos`）。
- 步骤：git 覆盖 + `ohos/entry/src/main/module.json5` 的 `EntryAbility.skills` 增加：
  ```json5
  { "actions": ["ohos.want.action.viewData"],
    "uris": [{ "scheme": "fluxdo" }, { "scheme": "discourse" }] }
  ```
- 降级：不接则冷启动深链失效（App 内链接解析仍可用）；`DeepLinkService._handleInitialLink()` 已有 try/catch，但 `_appLinks.uriLinkStream.listen(_handleLink)` **没有 onError**，插件缺失时流错误会成为未捕获异步异常——建议 `listen(_handleLink, onError: (e) => debugPrint(...))`。

### 8.5 剪贴板：`super_clipboard`

- 现状：6 处使用（富文本粘贴/复制 HTML、图片粘贴、AI 分享预览）。依赖 `super_native_extensions`（Rust + 平台原生），**无 OHOS 实现**。
- 降级（v1）：OHOS 上改用 Flutter 内置 `Clipboard`（纯文本）+ `html2md`（纯 Dart）做「粘贴文本 → markdown」；富 HTML/图片粘贴不可用。改动点：
  - `lib/widgets/markdown_editor/rich_composer/rich_composer_editor.dart`：按平台分支（`Platform.isOhos` → `Clipboard.getData(Clipboard.kTextPlain)`）；
  - `lib/widgets/common/image_context_menu.dart`、`lib/pages/image_viewer_page.dart`：图片复制到剪贴板禁用（OHOS 剪贴板图片需要 PixelMap，可后续用 ArkTS 桥）；
  - `lib/widgets/markdown_editor/markdown_toolbar.dart`、`lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart`、`lib/widgets/share/ai_share_image_preview.dart`：同上。
- 注意：`super_clipboard` 的 import 在 OHOS 上仍可编译（插件不注册而已），运行期调用会抛 `MissingPluginException` → 必须分支，否则粘贴时崩溃（不是启动崩溃）。

### 8.6 桌面专用：`window_manager` / `screen_retriever` / `flutter_acrylic` / `win32_registry`

- 现状：`main.dart:282-350` 全部在 `if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)` 内 → OHOS 不执行；`lib/services/window_state_service.dart` 被 `main.dart` 桌面分支调用；`win32_registry` 在 `windows_protocol_registrar_io.dart` / `system_proxy_detector.dart` 里用 `Platform.isWindows` 门控。
- 判断：**OHOS 不适用，无移植必要**；只需确认没有遗漏的非门控调用（`WindowStateService` 的 `startListening/attach/restore` 只在桌面分支；`AdaptiveNavigation`/`fullscreen_coordinator` 里若直接调 `windowManager` 需检查——`fullscreen_coordinator` 可能在任何平台调用 `windowManager.setFullScreen`，OHOS 会 MissingPluginException）。
- 改动点：`lib/widgets/media_player/video/fullscreen_coordinator.dart`、`lib/widgets/layout/adaptive_navigation.dart` 若有无条件 `windowManager` 调用，加 `Platform.isMacOS||isWindows||isLinux` 判断或 try/catch。

---

## 9. 交叉事项

### 9.1 证书资源同步（`assets/certs`）

- 生成链：`core/doh_proxy/build.rs` / `gen_ca` → `core/doh_proxy/certs/{ca.crt,ca.key,ca.der}` + `repo/assets/certs/proxy_ca.pem` + `android/app/src/main/res/raw/proxy_ca.der`。
- OHOS 需要：`assets/certs/proxy_ca.pem`（Dart `SecurityContext` 信任 + pubspec asset 声明）；若将来 ArkWeb 需要信任，再同步 `ohos/entry/src/main/resources/rawfile/proxy_ca.pem`（当前 flutter_inappwebview_ohos 没有 CA 注入 API，不需要）。
- **必须在 `flutter build hap` 之前生成**，否则：`ProxyCertificate.initialize()` 的 `rootBundle.load` 失败（catch 后仅 debugPrint，不崩），但 DoH 网关的 MITM 会因缺 CA 失败。
- 沙箱注意：本工作区 MSYS `openssl.exe` 不可用 → 建议改 `build.rs` 用 `rcgen`（见 §3.3），或在本机/CI 生成后提交到构建缓存（不入 git）。

### 9.2 `module.json5` 权限清单（OHOS 首版）

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },                       // 模板已有，必需
  { "name": "ohos.permission.GET_NETWORK_INFO" },               // connectivity 检测
  { "name": "ohos.permission.MICROPHONE" },                     // record（语音消息）
  { "name": "ohos.permission.CAMERA" },                         // mobile_scanner（若接 fork）
  { "name": "ohos.permission.READ_MEDIA" },                     // image_picker/gal/file_picker（按插件要求）
  { "name": "ohos.permission.WRITE_MEDIA" },                    // 保存图片/视频
  { "name": "ohos.permission.KEEP_BACKGROUND_RUNNING" },        // 仅当后续做 ContinuousTask
  { "name": "ohos.permission.VIBRATE" }                         // 通知/提示
]
```
（以各 OHOS 插件 README 的权限要求为准；`INTERNET` 缺失会导致所有网络请求失败，是首版最容易踩的坑。）

### 9.3 构建与签名

```powershell
. C:\Users\iceblock\fluxdo\tools\env.ps1
cd C:\Users\iceblock\fluxdo\repo
flutter create --platforms ohos .        # 生成 ohos/（工程已存在时只补平台目录）
flutter pub get
flutter build hap --debug --target-platform ohos-x64      # 模拟器（x86_64）
flutter build hap --release --target-platform ohos-arm64  # 真机
# 安装/运行（需 hdc 连接；模拟器先在 DevEco 里启动）
& "D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets
flutter run -d <deviceId>
# 日志
& "...\hdc.exe" shell hilog | Select-String 'flutter|DOH|rhttp|DiscourseCook'
```
签名：`build-profile.json5` 的 `signingConfigs` 需在 DevEco 里生成（自动签名）或 CI 注入证书；`flutter build hap --codesign=false` 仅用于 debug 分析。

### 9.4 版本/API 26 配置

- `ohos/build-profile.json5`：`compatibleSdkVersion` / `targetSdkVersion` 设为 `7.0.0(26)`（模板默认 `5.0.5(17)`，需改）。
- `ohos/entry/build-profile.json5`：`runtimeOS: "HarmonyOS"`；`buildOption.nativeLib` 默认会打包 `entry/libs/<abi>/`，无需额外配置（用 `tar -tf *.hap | Select-String libs/` 验证）。
- 模拟器是 x86_64 → 必须同时产出 `ohos/entry/libs/x86_64/*.so`，否则模拟器上所有 FFI 组件（doh_proxy/rhttp/native_animated_image）都会 `dlopen` 失败。

---

## 10. 验证计划（按依赖顺序）

| 阶段 | 验证内容 | 通过标准 |
|------|----------|----------|
| V0 | `flutter build hap --debug --target-platform ohos-x64` 能出包 | HAP 生成、可安装、能启动到首页 |
| V1 | 网络栈（dio/DoH 纯 Dart、shared_preferences/path_provider/secure_storage） | 登录态恢复、首页加载、图片显示 |
| V2 | `libdoh_proxy.so` FFI（§3.4） | 符号加载成功；DoH 缓存统计有数据；开关 DoH 不崩 |
| V3 | inappwebview OHOS | 打开登录页/CF 验证页，Cookie 同步正常 |
| V4 | `libnative_animated_image_codec.so` | GIF/APNG/WebP 动图逐帧播放、无 crash |
| V5 | video_player/just_audio/record | 视频播放、音频播放、录音上传各一次 |
| V6 | `librhttp.so` + FRB patch | rhttp 开启后 HTTP/2 请求成功；关闭后回退 dio |
| V7 | AVIF | 静态 AVIF 显示（引擎）→ 动画 AVIF 有占位不崩 |
| V8 | cook | 编辑器预览走降级管线不崩；v2 接 flutter_qjs 后 HTML 对齐 Android |
| V9 | 通知/深链/剪贴板/更新 | 通知可弹、深链可跳、粘贴不崩、更新入口隐藏 |
| V10 | 真机 arm64 全量回归 | 同 V1-V9；另测 x86_64 模拟器与 arm64 真机 `.so` 均存在 |

每阶段失败时的排查命令：
```powershell
# 缺失插件
& hdc.exe shell hilog | Select-String 'MissingPluginException|Unhandled Exception'
# .so 缺失/ABI 错
& hdc.exe shell hilog | Select-String 'dlopen|library .* not found|incompatible'
# 进包检查
tar -tf build\ohos\...\*.hap | Select-String 'libs/'
```

---

## 11. 未验证/待实测项（明确标注，不要当成已证事实）

1. **Rust 交叉编译未实际执行**（本机无 Rust 工具链）：ring 0.17.14 / aws-lc-rs / tokio 在 `aarch64-unknown-linux-ohos` 的编译结论来自上游文档/issue/源码分析，需按 §2/§3 实测。
2. **`aarch64-unknown-linux-ohos` 的 `rustup target add` 在 Windows 宿主是否直接可用**：Tier 2 with host tools 理论上可用，若 rustup 报错则用 `-Z build-std`（nightly）或 OHOS SIG 提供的 Rust 发行版。
3. **OHOS 系统 Image Kit 是否支持 AVIF**（静态/动画）：Image Kit 文档未明确列出 AVIF → 必须真机/模拟器实测（`_tryPlatformAvifCodec` 路径）。
4. **`video_player_ohos` 在 Flutter 3.47.7-ohos 上的兼容性**：README 只声明到 3.41.10；Pigeon/ArkTS AVPlayer 需实测。
5. **`flutter_inappwebview_ohos` 6.1.5 与仓库 6.2.0-beta.3 API 差异**：需 `flutter analyze` + 逐页回归（登录、CF、Mermaid、Eruda）。
6. **`just_audio` fork 实际 0.10.5 与仓库 0.10.6 的 API 差异**：当前用法标准，风险低但需 analyze。
7. **`flutter_local_notifications` 22.0.1 与 21.0.0 的 API 差异**：`initialize(settings:)` 命名参数兼容性较好，仍需 analyze。
8. **OHOS WebView 应用级代理能力**：当前 fork 无 `ProxyController`；ArkWeb 未来是否提供、或是否可用 `net.connection` 设置应用代理（需系统权限），待查。
9. **doh_proxy 的 ECH（aws-lc-rs）在 OHOS 的编译**：上游支持，但 CMake 交叉编译在 Windows 宿主上可能踩坑（建议先用 `default`（ring）发版，再单独试 `--features ech`）。
10. **`assets/certs` 生成链在沙箱内的可用性**：MSYS openssl 被拦，需要改 build.rs 或换生成方式（§3.3）。

---

## 12. 对 lib/ 的改动汇总（供 Lead 统一排期）

| 优先级 | 文件 | 改动摘要 |
|--------|------|----------|
| P0 | `lib/services/network/doh_proxy/doh_proxy_ffi.dart` | `isAvailable`/`_loadLibrary` 增加 OHOS |
| P0 | `lib/services/network/doh_proxy/doh_proxy_service.dart` | OHOS 禁止走进程模式，给出明确错误 |
| P0 | `lib/services/cook/cook_js_engine_io.dart` | OHOS `cookJsSupported=false`（v1） |
| P0 | `lib/services/avif_fast_bridge.dart` + `lib/services/avif_image_provider.dart` | OHOS 跳过 flutter_avif（v1） |
| P0 | `lib/services/local_notification_service.dart` | `initialize()` 加 try/catch；补 `ohos:` 配置（接 fork 后） |
| P0 | `lib/services/deep_link_service.dart` | `uriLinkStream.listen` 补 `onError`（`_handleInitialLink` 已有 try/catch） |
| P0 | `lib/widgets/markdown_editor/rich_composer/rich_composer_editor.dart` 等 6 处 `super_clipboard` | OHOS 分支改 `Clipboard`/禁用 |
| P0 | `lib/pages/network_settings_page/widgets/engine_card.dart` | OHOS 隐藏 rhttp 卡片 |
| P0 | 设置页（更新/后台/相机/窗口相关） | OHOS 隐藏或标注不可用 |
| P1 | `packages/ohos/flutter_rust_bridge/lib/src/loader/_io.dart`（新增 vendored） | 增加 `ohos` 分支 |
| P1 | `lib/services/network/doh_proxy/cert_preference_service.dart` | 可选：OHOS 默认 per-device=false（现状已满足） |
| P1 | `lib/main.dart` | OHOS 跳过 `_initRhttp()`；可选：`Platform.isOhos` 时关闭 ECH 相关初始化 |
| P1 | `lib/services/network/doh/network_settings_service.dart` | 可选：OHOS 上 ECH/本地代理相关分支置空 |
| P2 | `lib/services/cook/cook_js_engine_io.dart` | 接 `flutter_qjs` 真实现 |
| P2 | `lib/pages/qr_login_scan_page.dart` | `_supportsCamera` 增加 OHOS（接 mobile_scanner fork 后） |
| P2 | `lib/services/avif_image_provider.dart` | 接 `flutter_avif_ohos`（若真移植） |
| P2 | `lib/services/background/*` | 后续接 ArkTS ContinuousTask 平台包 |
| — | `lib/services/render_backend_service.dart`、`lib/services/window_state_service.dart`、`lib/services/windows_*.dart`、`lib/services/network/cookie/strategy/*` | 不改（已平台门控/OHOS 走 Default 策略） |

---

## 13. 参考（本次核实过的关键来源）

- Rust 平台支持（OHOS Tier 2、clang 包装脚本、rustup target）：<https://doc.rust-lang.org/nightly/rustc/platform-support/openharmony.html>
- rustc target spec（`os=linux`、`env=ohos`、`has_thread_local=false`）：`rust-lang/rust` `compiler/rustc_target/src/spec/base/linux_ohos.rs`
- ring 不能编 OHOS 的根因（缺 TARGET_CC，已关闭）：<https://github.com/briansmith/ring/issues/2122>
- aws-lc-rs OHOS 支持：<https://github.com/aws/aws-lc-rs/pull/434>（+ #456）
- OHOS Flutter 三方库适配清单（`flutter_qjs`/`mobile_scanner`/`record`/`just_audio`/`inappwebview`/`local_notifications`/`app_links` 等）：<https://raw.gitcode.com/OpenHarmony-Flutter/docs/raw/main/ThirdpartyLibrarites.md>
- `video_player_ohos`（2.11.1，Flutter 3.41 支持矩阵）：<https://gitcode.com/openharmony-tpc/flutter_packages>（分支 `br_video_player-v2.11.1_ohos`）
- `flutter_qjs` OHOS：<https://gitcode.com/CPF-Flutter/fluttertpc_flutter_qjs>
- 本仓库相关文件：`repo/pubspec.yaml`、`repo/pubspec.lock`、`repo/lib/services/**`、`repo/tools/discourse-cook-bundle/README.md`、`repo/.gitmodules`、`repo/core/doh_proxy`（submodule）、`tools/flutter/packages/flutter_tools/lib/src/{ohos,build_info.dart}`、`tools/flutter/engine/src/flutter/shell/platform/ohos/ohos_image_generator.*`

## 0.1 rhttp（flutter_rust_bridge）交叉编译：已打通

`rhttp` 是 flutter_rust_bridge 2.12.0 绑定的 Rust HTTP 客户端（rustls + reqwest + tokio）。
移植要点：

| 项 | 做法 |
|---|---|
| 编译 | `tools/build-rhttp-ohos.sh`（WSL 内）→ `librhttp.so` x86_64 7.1 MB / arm64-v8a 5.9 MB |
| reqwest http3 | rhttp 启用了 reqwest 的不稳定特性，需 `RUSTFLAGS="--cfg reqwest_unstable"` |
| **libunwind（关键）** | NDK 只给 aarch64 带 `libunwind.a`，**x86_64 没有**。不加处理时 `dlopen` 报 `_Unwind_Resume: symbol not found`。解决：`tools/ohos-unwind-stub.c` 生成符号桩，x86_64 链接桩（配合 `-C panic=abort`），aarch64 链接 NDK 真实 `libunwind.a`；两库未解析 `_Unwind` 符号数均为 0 |
| Dart 侧加载 | FRB 默认加载器不认识 `ohos`；厂商化 `packages/rhttp` 后给 `Rhttp.init({String? externalLibraryPath})`，OHOS 传 `librhttp.so` |
| 验证 | 设备日志：`{"type":"rhttp","event":"rhttp_init","result":"ok","platform":"ohos"}` |

> 同一 unwind 修复也应用到 `libdoh_proxy.so`（此前用空归档占位，属潜在运行时加载失败点）。

## 0.2 native_animated_image（Rust 动图解码）：已打通

| 项 | 做法 |
|---|---|
| 编译 | `tools/build-native-animated-image-ohos.sh`（源码：github.com/Lingyan000/native_animated_image，crate `native_animated_image_codec` 0.3.2，依赖 gif/png/image-webp，**纯 Rust，无 cmake**，17 秒编完） |
| 产物 | `libnative_animated_image_codec.so`：x86_64 588 KB / arm64-v8a 562 KB，6 个 API 符号，未解析 `_Unwind` 为 0 |
| Dart 侧 | 厂商化 `packages/native_animated_image`，bindings 增加 `Platform.operatingSystem == 'ohos'` 分支（注意：ohos 下 `Platform.isLinux` 为 false，必须单独判断） |
| 验证 | 启动探测写 JSONL：`{"type":"image","event":"native_animated_codec","result":"ok","version":"0.3.2"}` |

> 注意：pub 包 0.3.4 的 crate 版本号是 0.3.2（上游未同步版本号），FFI 符号完全匹配。

## 0.3 AVIF：系统 ImageKit 方案已实测不可行（2026-10-21）

思路：flutter_avif 无 OHOS 平台实现，但若系统 ImageKit 能解 AVIF，就能用
ArkTS 桥把 AVIF 解成 RGBA 再交给 Flutter 引擎（`ImageDescriptor.raw`）。

实测结果（API 26 模拟器，样本 `fox.profile0.8bpc.yuv420.avif`）：

| 步骤 | 结果 |
|---|---|
| `image.createImageSource(bytes).getImageInfo()` | ✅ `mime=image/avif, 1204x800`（容器头可解析） |
| `createPixelMap({desiredPixelFormat: RGBA_8888})` | ❌ `Decode failed. e.g.,Decode image header failed.` |
| `createPixelMap()` 默认参数 | ❌ 同上 |
| `createPixelMapList()` | ❌ `Create PixelMap List error` |

结论：该设备/该 API 版本的 ImageKit **只做容器解析，不含 AVIF 像素解码器**。
因此 `OhosCompat.supportsAvif` 保持 `false`（AVIF 走引擎内建兜底/占位）。

代码保留：`FluxdoBridgePlugin.probeAvif/decodeAvif` + `avif_image_provider.dart`
里的 `_tryOhosAvifCodec`（`supportsAvif` 为 false 时不会走到），
启动时仍会探测一次并写日志（`avif_probe`），便于真机验证是否有差异。

**下一步（真正可行的方案）**：在 WSL 内自编 `libavif + dav1d`（C/C++，cmake/meson），
导出 `avif_decode(bytes) -> RGBA` 的 FFI，再按 native_animated_image 的方式接进 Dart。

## 0.4 AVIF：自编 libavif + dav1d 成功（2026-10-22）

上一轮证明系统 ImageKit 不能解 AVIF，故改自编解码器：

| 步骤 | 做法 |
|---|---|
| dav1d 1.5.4 | meson 交叉编译（`--cross-file` 指向 OHOS clang 包装器），`-Denable_asm=false`（规避 nasm/汇编的 OHOS 适配），`--default-library=static` |
| libavif | cmake 交叉编译，`-DAVIF_CODEC_DAV1D=SYSTEM`（**必须用 SYSTEM，`ON` 会被静默忽略**）+ `DAV1D_LIBRARY`/`DAV1D_INCLUDE_DIR` 指向 dav1d 前缀 |
| 包装 | `tools/ohos-avif-decode.c`：`ohos_avif_decode(bytes,size,&rgba,&w,&h,&err,maxDim)` + `ohos_avif_free`，静态链接 libavif+dav1d |
| 产物 | `libohos_avif.so`：x86_64 1.07 MB / arm64-v8a 897 KB，仅依赖 `libc.so` |
| Dart | `lib/services/avif_ohos_codec.dart`（dart:ffi）→ `ImageDescriptor.raw` → 引擎 codec |
| 接入 | `avif_image_provider.dart` 的 `_tryOhosAvifCodec`：原生库优先，ImageKit 兜底 |
| 验证 | `{"event":"avif_probe","result":"native-ok","detail":"w=1204 h=800 rgba=3852800"}` |

**两个关键坑（已记录）**：
1. meson 编译用 `-Werror=unused-command-line-argument` → clang 包装器必须区分「编译/链接」调用，
   只在链接时注入 `-L/-unwindlib/-fuse-ld`；否则 configure 阶段直接失败。
2. `-DAVIF_CODEC_DAV1D=ON` 不生效（合法值是 `OFF/LOCAL/SYSTEM`），必须用 `SYSTEM`。

脚本：`tools/build-avif-ohos.sh`（dav1d → libavif → 包装 .so，两 ABI 一键构建）。

## 0.5 cook JS：自编 QuickJS 成功（2026-10-22）

`flutter_js` 只发布预编译 `.so`、不带 QuickJS 源码与 C 桥，故自建最小桥：

| 项 | 做法 |
|---|---|
| QuickJS | quickjs-ng **0.17.0**，源码直编（quickjs.c / dtoa.c / libregexp.c / libunicode.c） |
| 桥接 | `tools/ohos-quickjs-bridge.c`：`ohos_js_new()` / `ohos_js_eval(handle,...)` / `ohos_js_dispose()` / `ohos_js_free()` / `ohos_js_version()` |
| 关键设计 | **持久上下文**：cook 先 eval 整个 bundle 定义 `__fluxdoCook` 等全局，之后逐次渲染复用同一 context；若每次新建 runtime 会丢全局 |
| 产物 | `libohos_quickjs.so`：x86_64 1.27 MB / arm64-v8a 1.19 MB，仅依赖 libc |
| Dart | `lib/services/cook/ohos_quickjs.dart`（FFI）+ `cook_js_engine_io.dart` 按平台分流 |
| 验证 | `ohos_quickjs_probe ok (0.17.0, 1+1=2)`；`cook_bundle_eval ok (567,467 B / 48 ms)`；`cook_global_probe ok (typeof __fluxdoCook = object)` |

**顺带修掉一个既有 bug**：`cook_js_engine_io.dart` 里
`final bool cookJsSupported = !OhosCompat.supportsCookJs;` 取反写错，
导致 cook 渲染在所有平台都被关闭（supportsCookJs 为 true 时反而禁用）。
已改为 `= OhosCompat.supportsCookJs`。

脚本：`tools/build-quickjs-ohos.sh`。

## 0.6 后台保活：长时任务（backgroundTaskManager）已打通（2026-10-22）

`flutter_foreground_task` / `workmanager` 都没有 OHOS 实现，改用系统长时任务自建：

| 项 | 做法 |
|---|---|
| ArkTS | `FluxdoBridgePlugin.startContinuousTask/stopContinuousTask`：`backgroundTaskManager.startBackgroundRunning(ctx, BackgroundMode.DATA_TRANSFER, wantAgent)` |
| Context | `startBackgroundRunning` 需要 UIAbilityContext → EntryAbility 在注册插件前写入 `FluxdoBridgePlugin.abilityContext` |
| 清单 | `module.json5` 的 EntryAbility 增加 `"backgroundModes": ["dataTransfer"]` |
| Dart | `lib/services/background/ohos_background_task.dart`（幂等 + 失败兜底）；`BackgroundNotificationService` 在切后台时申请、回前台释放 |
| 限制 | 数据同步类长时任务单次最长约 10 分钟，需在每次切后台重新申请（已如此实现） |
| 验证 | `{"event":"ohos_continuous_task_probe","state":"started"}` / `"stopped"` |

**踩坑记录**：
1. `startBackgroundRunning(ctx, bgModes: string[], wantAgent)` 的数组重载要 **string[]**，
   传 `BackgroundMode[]`（枚举是 number）会 ArkTS 编译报 "No overload matches"；
   改用单模式重载 `(ctx, BackgroundMode.DATA_TRANSFER, wantAgent)`。
2. DevEco 打开工程后会往 `build-profile.json5` 自动写入 `signingConfigs`（含加密密码），
   之后脚本构建会在 SignHap 阶段报 `11012003 No permission write to signConfigCheckJson.json`。
   解决：把 `signingConfigs` 恢复成 `[]`（脚本用 `tools/ohos-sign.ps1` 手工签名）。

## 0.7 富文本剪贴板：写图片已打通，读 HTML 受权限限制（2026-10-22）

`super_clipboard`（super_native_extensions）没有 OHOS 实现，改由 ArkTS `@ohos.pasteboard` 补：

| 能力 | 实现 | 状态 |
|---|---|---|
| 复制图片到系统剪贴板 | `writeImageToPasteboard`：PNG → ImageKit `createPixelMap` → `pasteboard.createData(MIMETYPE_PIXELMAP, …)` → `setData` | ✅ 设备日志 `write-ok` |
| 读取剪贴板 HTML（富文本粘贴） | `readClipboardHtml`：`getData().getPrimaryHtml()` | ⚠️ 无 `READ_PASTEBOARD` 权限时返回 null，自动回退纯文本粘贴 |
| 读取剪贴板图片 | 未实现（移动端场景极少，保持原降级） | ⚠️ 降级 |

**权限限制（重要）**：`ohos.permission.READ_PASTEBOARD` 属 **system_basic** 级，
普通应用证书安装期直接失败：
`install failed due to grant request permissions failed. PermissionName: ohos.permission.READ_PASTEBOARD`
→ 不声明该权限；读剪贴板 HTML 尽力而为（`getPrimaryHtml` 无权限时抛错被 catch，返回 null）。
写剪贴板不需要权限，因此「复制图片」在普通应用上可用。

Dart 侧：`ClipboardUtils`（`copyPngImage` OHOS 分支、`readHtml()`）；
`rich_composer_editor._importRichPaste` OHOS 先试 readHtml，失败回退纯文本。
