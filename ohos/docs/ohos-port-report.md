# FluxDO → HarmonyOS 7 移植报告
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从应用侧 `module.json5` 删除（最终包仍由依赖 HAR 带入，见 README.md）。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 目标：把 [Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo)（Linux.do 第三方 Flutter 客户端，v0.2.29）移植到 HarmonyOS 7，要求功能可用。
> 环境：Windows 11 + DevEco Studio 26.0（HarmonyOS SDK **API 26 / HarmonyOS 7.0.0**）+ Flutter **3.47.7+ohos-0.0.1-pre**（Dart 3.13.5，OHOS 分支 `oh-3.47.7-preview`）+ HarmonyOS 7 模拟器（x86_64，`Pura 90 Pro`）。
> 产物：`com.fluxdo.app` HAP（debug，约 344 MB），可在模拟器安装启动。

## 1. 结论摘要

| 维度 | 状态 |
|---|---|
| 构建链路（Flutter→ArkTS→HAP→签名→安装→启动） | ✅ 全通，一条命令可复现 |
| 首屏 / 登录页 / 我的页 / 游客入口 | ✅ 实测截图 |
| 话题列表、话题详情（HTML 渲染）、搜索、深链 | ✅ 实测截图 |
| 图片（CDN 头像）、系统输入法 | ✅ 实测截图 |
| Cloudflare 403（linux.do 前置盾） | ✅ 已解决（挑战真实执行 + OHOS 默认走 WebView 网络栈 + ArkWeb cf_clearance 判据；**冷启动零点击直接出列表**，证据 `.cache/shot-cold-r5.jpeg`） |
| 插件原生能力 | 26 个 OHOS 插件模块编译注册（含 path_provider/shared_preferences/url_launcher/secure_storage/record/video_player/just_audio/wakelock/inappwebview/local_notifications/sqflite/app_links/ota/mobile_scanner/open_filex/volume_controller/saver_gallery/image_picker/package_info/share_plus/file_picker…） |
| 已降级能力 | cook JS、AVIF、后台保活、应用内更新、富剪贴板（见 §6）；DOH/rhttp/原生动图解码 已接入原生库 |

## 2. 工程结构（新增/改动）

```
fluxdo/
├── ohos/                                  # 新增：HarmonyOS 工程（API 26，bundle com.fluxdo.app）
│   ├── AppScope/app.json5                 # 版本号/包名/图标
│   ├── build-profile.json5                # compatibleSdkVersion "26.0.0"，signingConfigs 留空（构建后手工签名）
│   ├── entry/src/main/module.json5        # 权限 + fluxdo:// discourse:// 深链 skills
│   └── entry/src/main/ets/
│       ├── entryability/EntryAbility.ets  # 注册 GeneratedPluginRegistrant + FluxdoBridgePlugin
│       └── plugins/FluxdoBridgePlugin.ets # 时区等自研 ArkTS 桥
├── packages/                              # vendored（含 VENDOR.md：来源/TAG/许可证/回滚）
│   ├── flutter_math_fork/                 # 补 TargetPlatform.ohos（上游 0.7.4 缺失）
│   ├── just_audio_harmonyos/              # 补 API 26 MediaSource.enableOfflineCache()/getID()
│   ├── share_plus/ + share_plus_platform_interface/   # OHOS 实现，去掉嵌套 git 依赖
│   └── file_picker/                       # CPF 10.3.8-ohos-1.0.0，改名 + re-export 无缝替换
├── lib/utils/platform_utils.dart          # + isOhos；isMobile 纳入 OHOS
├── lib/utils/ohos_compat.dart             # 新增：OHOS 能力开关
├── lib/utils/clipboard_utils.dart         # 新增：OHOS 富剪贴板 → 纯文本兜底
├── lib/constants.dart                     # OHOS 移动端 UA
└── docs/ohos-*.md                         # 调研/构建/CF/验收/依赖改动 文档
```

工具脚本（工作区 `tools/`）：
- `env.ps1`：一键环境（FLUTTER_ROOT/DEVECO_SDK_HOME/PUB_CACHE/NODE_OPTIONS/TEMP 等）
- `build-ohos.ps1`：构建 → 定位 unsigned HAP → 签名 → 可选安装/启动
- `ohos-sign.ps1`：用 OpenHarmony 默认证书链生成 profile 并签名（**无需华为账号/DevEco GUI**）
- `node-symlink-fallback.js`：把 hvigor/pnpm 的 symlink 调用降级为 junction（Windows 未开开发者模式）

## 3. 构建与运行（复现）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
# 构建 + 签名 + 安装 + 启动（需完整权限会话：沙箱禁止 Dart 创建子进程）
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1 -Install -Launch
# 截图
hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/x.jpeg
hdc -t 127.0.0.1:5555 file recv /data/local/tmp/x.jpeg .\x.jpeg
```

## 4. 关键技术问题与解法（移植中真实踩到）

| # | 问题 | 解法 |
|---|---|---|
| 1 | 本机 `git`/`curl`/`Invoke-WebRequest` 的 schannel TLS 不可用 | git 用 `-c http.sslBackend=openssl`（写进 `.home/.gitconfig`）；下载用 Node 原生 TLS |
| 2 | Flutter OHOS SDK 首次运行需下载 Dart SDK，但脚本用 PowerShell 下载（schannel 失败） | 用 Node 预下载 Dart SDK 解压到 `bin/cache/dart-sdk` 并写 stamp 跳过 |
| 3 | 沙箱禁止 Dart 创建带管道的子进程 | 工具链命令必须在 `danger-full-access` 下运行（子代理做不到，故构建由 Lead 执行） |
| 4 | hvigor 用 symlink，Windows 无开发者模式 → EPERM | `NODE_OPTIONS` 注入 `node-symlink-fallback.js`，symlink 降级 junction |
| 5 | API 26 的 `compatibleSdkVersion` 格式 | 必须 `"26.0.0"`（10–25 才是 `5.0.0(12)` 形式） |
| 6 | hvigor 拒绝明文签名密码（要求 ≥32 字符密文） | `signingConfigs: []`，构建后用 `hap-sign-tool` 手工签名（默认证书链 + 按 bundle 生成 debug profile，UDID 绑定模拟器） |
| 7 | `module.json5` 的 `backgroundModes` 放 module 根 → schema 校验失败 | 移除（属 ability 级配置，首版不用后台保活） |
| 8 | 含中文的 .ps1 被 Windows PowerShell 按 GBK 解析 → 语法错误 | 脚本存 UTF-8 **BOM**；Dart 文件只用编辑工具改，禁用 `Get-Content/Set-Content` |
| 9 | `assets/certs/` 目录缺失 → flutter 资源打包失败 | 补 `.gitkeep` |
| 10 | 子模块 `packages/fluxdo_render`、`core/doh_proxy` 未 checkout | `git submodule update --init --recursive`（+ `core.longpaths=true`） |
| 11 | 插件 `TargetPlatform` switch 未覆盖 `TargetPlatform.ohos` → kernel 编译失败 | app 包与 vendored 第三方包统一补 `ohos` 分支 |
| 12 | `flutter_inappwebview_windows/_linux` 本地 fork 与 6.1.5 平台接口冲突 | 移除这两个 path override（OHOS 构建不需要） |
| 13 | 手机设备 + 桌面 UA 被 Cloudflare 直接 403 | OHOS 分支改用 Android 移动端 UA |
| 14 | CF 挑战「看似完成」但从未执行（插件伪造 200 响应） | OHOS 关闭 `useOnNavigationResponse`/`useShouldOverrideUrlLoading`，让 ArkWeb 真跑挑战；失败自动切 WebView 网络栈重放 |
| 15 | ArkWeb 的 HttpOnly `cf_clearance` 无法导出给 dio | 走 WebView 网络栈（JS fetch 自带 cookie）作为兜底路径 |
| 16 | 「另存为」无响应：file_picker 的 OHOS 端 `saveFile` 只复用「选文件流程」的 `bytesList/savaFilePath`，应用直接传 `bytes` 时被判定为空 → `PlatformException(Bytes are required on HarmonyOS...)` | 在 vendored `packages/file_picker/ohos` 增加 `setSavePayload(fileName, bytes)` 注入本次内容，并传不带后缀的主文件名（避免 `xx.md.md`）；修复后系统文件保存器正常弹出 |

## 5. 依赖层改动（详见 docs/ohos-pubspec-changes.md）

- 新增 12 个 OHOS 实现包 + 12 条 git override（device_info_plus / connectivity_plus / open_filex / mobile_scanner / volume_controller / app_links / flutter_local_notifications / sqflite / inappwebview(+PI) / ota_update / flutter_secure_storage_ohos / record_ohos）。
- 5 个 vendored 包（见 §2），每个带 `VENDOR.md`；`packages/fluxdo_render` 的 OHOS 补丁导出为 `docs/patches/fluxdo_render-ohos.patch`。
- `flutter pub get` 成功（372 包）；插件注册 26 个。

## 6. OHOS 上降级/禁用的能力（首版策略）

| 能力 | 现状 | 后续路径 |
|---|---|---|
| DOH 代理（Rust，core/doh_proxy） | **已接入**：交叉编译出 libdoh_proxy.so（x86_64 7.5 MB / arm64-v8a 6.6 MB），打进 HAP 的 libs/<abi>/，网络设置恢复「DNS over HTTPS」项 | 运行时开关需人工点一次确认（模拟器注入受限） |
| rhttp（Rust TLS 指纹） | **已接入**：librhttp.so 随 HAP 打包，设备日志 rhttp_init=ok | 引擎切「高性能」需人工点一次 |
| cook JS 1:1 预览（flutter_js） | 降级 Dart 近似预览 | 换 flutter_qjs 的 OHOS 适配 |
| AVIF / 动图（flutter_avif / native_animated_image） | 引擎内建解码 | 原生库交叉编译 |
| 后台保活/后台通知 | 仅前台 | 长时任务 + 通知 |
| 相机扫码（mobile_scanner） | **已启用**（CPF fork 的 OHOS 实现）：扫码登录页显示相机预览并请求 CAMERA 权限；相机不可用时自动降级为相册 + zxing2 | 真机确认相机预览效果 |
| 应用内更新（ota_update） | 引导外部（HAP 不能静默安装） | 应用市场链接 |
| 富文本/图片剪贴板（super_clipboard） | 纯文本兜底 | ArkTS pasteboard 桥 |

## 7. 待办（下一轮）

1. 游客态点回复的登录提示（注入点击在部分 Flutter 面板上不稳定，需换方式验证）。
2. 提交卫生：`git add` 5 个 vendored 目录 + `ohos/` + submodule 补丁固化。
3. 可选 P1/P2 原生移植：DOH 代理、rhttp、cook JS、AVIF/动图、后台保活、相机扫码。

## 7.1 已验证完成（本轮补充）

- **时区**：应用落盘日志确认 `timezone_resolved: Asia/Shanghai (platform=ohos)`，并新增 `type=timezone` 诊断日志便于后续排查。
- **静态分析**：`dart analyze lib` → 0 error / 0 warning。
- **file_picker 另存为**：修复 OHOS 端 bytes 注入缺失，系统文件保存器可正常唤起。
- **代码已提交**：`repo` 仓库单次提交 `674a99f feat(ohos): 适配 HarmonyOS 7（API 26）移植`（656 文件，含 `ohos/` 工程、5 个 vendored 插件、lib 适配、pubspec 改动；`oh_modules/` 构建产物已加入 .gitignore 排除）；`packages/fluxdo_render` submodule 的 OHOS 补丁提交为 `8c18e80`，外层指针已随主提交更新。
- **最终回归**：从干净工作区重新执行 `tools\build-ohos.ps1 -Install -Launch` → assembleHap 成功（80.8s）→ 签名 → 安装 → 启动，全部通过。
- **release 构建**：`tools\build-ohos.ps1 -Mode release -Install` → HAP 86.5 MB（签名后 91.3 MB；debug 为 344 MB），AOT 运行正常、冷启动零点击出话题列表、无 DEBUG 角标（证据 `.cache/shot-release.jpeg`）。
- **平台守卫**：HarmonyOS 上隐藏依赖 Rust 本地网关的「DNS over HTTPS」设置项（提交 `d2dce01`），避免失效入口。

## 8. 相关文档

- [ohos-port-status.md](ohos-port-status.md)：状态、坑、复现命令
- [ohos-acceptance.md](ohos-acceptance.md)：验收清单与证据截图
- [ohos-build-notes.md](ohos-build-notes.md)：构建/签名/安装细节
- [ohos-cf-fix.md](ohos-cf-fix.md)：Cloudflare 403 根因与三轮修复
- [ohos-plugin-matrix.md](ohos-plugin-matrix.md)：56 个插件 OHOS 适配矩阵
- [ohos-native-strategy.md](ohos-native-strategy.md)：Rust/FFI/原生组件移植策略
- [ohos-pubspec-changes.md](ohos-pubspec-changes.md)：依赖改动逐条说明与回滚
- [ohos-arkts-bridges.md](ohos-arkts-bridges.md)：ArkTS 桥实现与验证方法
