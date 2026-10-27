# fluxdo × HarmonyOS 7：pubspec 依赖改写记录（task-4 交付）

> 执行者：pubspec-ohos（task-4）；执行时间：2026-10-21。
> 依据：`docs/ohos-plugin-matrix.md`（task-1）+ `docs/ohos-native-strategy.md`（task-2）。
> 目标 SDK：OHOS Flutter `3.47.7-ohos-0.0.1-canary1`（`tools/flutter`）+ HarmonyOS 7 / API 26。
> 策略：按 Lead 决定，**单 `pubspec.yaml` + `dependency_overrides` 临时打通**（不新增 `pubspec.ohos.yaml`），
> 所有改动均集中在 `repo/pubspec.yaml`，`repo/pubspec.lock` 与代码零改动（lib/ohos 归其他任务）。

---

## 0. 一句话结论 / 交接状态

> **2026-10-21 13:50 更新（Lead 完整权限会话实跑）**：`flutter pub get` ✅ 成功（`pubspec.lock` 已重生成，
> 94.7 KB，其中 22 条 git source 条目）；`flutter build hap` ✅ 打通，**25 个 OHOS 插件模块全部参与编译**，
> HAP 已安装并在 HarmonyOS 7 模拟器启动渲染（证据见 `docs/ohos-port-status.md` §1）。
> 依赖层验收项「pub get 成功 + build 不再因依赖解析失败」**已达成**。
> 构建期在依赖层追加了 2 处 vendored 本地修复 + 1 处 override 移除，见本文 §9。
>
> **2026-10-21 晚追加（本 agent）**：补齐最后两条未接 OHOS 的高频链路
> —— **share_plus（7 处调用）** 与 **file_picker（6 处调用）**，均用 vendored path 依赖实现、
> 业务代码零改动（详见 §10）；同时固化 submodule 补丁与 vendored 包说明（§11）。
> ✅ 已用 Lead 会话 15:43–15:45 的真实构建验证：`flutter pub get` 成功（3 项 path 依赖入 lock）、
> `plugins.ohos` 24 → 26、`assembleHap` 108.9s 成功并签名产出 HAP（证据见 §10.3）。
> 仅剩 UI 层「实际点分享 / 选文件」的人工回归。

| 项目 | 结果 |
|---|---|
| 依赖组合（hosted + git + path）能否解析 | ✅ 首轮 13:50 真实解析成功；本轮 share_plus/file_picker path 改动已用 `dart pub get` 预验证（§10.3） |
| `repo/pubspec.yaml` 是否已改好 | ✅ 新增 12 条 OHOS 实现依赖 + 11 条 git override + 2 条 vendored path override + 2 条 path 依赖替换（§2/§3/§9/§10） |
| `repo/pubspec.lock` | ✅ 已由 Lead 重生成（2026-10-21 13:50） |
| `flutter pub get` 是否已在本机真实跑通 | ✅ 已跑通（本 agent 沙箱限制见 §1，最终由 Lead 执行） |
| `flutter build hap` 依赖层 | ✅ 依赖解析/平台声明不再失败；lib 层问题另见 §6 |

---

## 1. 本机执行限制（重要，Lead 必读）

本 agent 的 DSH 沙箱为 `workspace-write`，**禁止任何进程创建子进程**：`flutter ...`、`dart analyze` 都会因
`dart` 内部 spawn `git`/`analysis_server` 而失败（`CreateFile failed 5` / `process_win.cc:744: 拒绝访问`）。
本会话不允许提权，因此：

1. 真实 `flutter pub get` / `flutter build hap` **必须在 Lead 的会话里执行**（已于 2026-10-21 13:50 完成）；
2. 我在本地用了两条可行替代校验（均成功）：
   - `dart pub get`（dart 不 spawn 子进程时可用）——用 `repo/pubspec.yaml.validation`（把 14 个 git 依赖
     换成 `.cache/ohos-pkgs/` 下同 ref 的本地 clone path）跑通，验证**版本约束/联邦解/collision**；
   - 自写 analyzer 脚本（`analyzer 10.1.0`，进程内分析）对 `repo/lib` 出错误清单，用于区分「依赖降级
     导致的 API 破坏」与「与本任务无关的既有错误」。
3. 临时文件（不提交）：`repo/pubspec.yaml.validation` 已删除；生成器与最终版快照在
   `.tmp/make_validate2.mjs`、`.cache/ohos-pubspec-final.yaml`；clone 副本在 `.cache/ohos-pkgs/`。

### 1.1 给 Lead 的执行前置（必须）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
# 1) git 依赖 TLS：env.ps1 已把 HOME 指到 <ws>\.home，该目录下的 .gitconfig 已有 [http] sslBackend=openssl
#    （若另行设置 GIT_CONFIG_GLOBAL，请指向含同样内容的文件）
# 2) PUB_CACHE 已在 env.ps1 指到 <ws>\.pub-cache
cd C:\Users\iceblock\fluxdo\repo
flutter pub get          # 首次会 clone 12 个 git 仓库到 PUB_CACHE，耗时数分钟
```

> 注意：`repo` 的两个 submodule 原本未 checkout，会直接导致 pub get 失败（`packages/fluxdo_render` 是
> path 依赖）。本任务已补：`packages/fluxdo_render` 已 clone 到 gitlink 提交
> `5bfd16be83d7b7cb89740bef0b97ca4f95168aaf`；`core/doh_proxy` 已由其他任务补好
> （`660a19b3ba49d26933f25486705ba85c0e74292b`）。**这两个不是代码改动，是环境补齐，请随任务一并记录。**

---

## 2. 改动一：`dependencies` 新增 12 条「OHOS 平台实现」

原则：**不替换官方 app-facing 包**（Dart API、其他五端行为不变），只额外挂上 OHOS 实现包。
其中 `*_ohos` / `*_harmonyos` / `*_ohos(record_ohos)` 只声明 `ohos` 平台，其他平台构建会忽略。

| 新增依赖 | 版本 | 提供方 / ref | 对应官方包 | 说明 |
|---|---|---|---|---|
| path_provider_ohos | ^2.2.1 | pub.dev | path_provider 2.1.6 | dartPluginClass 注册，零改动 |
| shared_preferences_ohos | ^2.2.0 | pub.dev | shared_preferences 2.5.5 | 同上 |
| url_launcher_ohos | ^6.3.0 | pub.dev | url_launcher 6.3.2 | 同上 |
| image_picker_harmonyos | 0.0.1 | pub.dev（Wayaer） | image_picker 1.2.3 | PhotoViewPicker / CAMERA |
| video_player_harmonyos | 0.0.1 | pub.dev（Wayaer） | video_player 2.14.1 | AVPlayer + 外接纹理，高风险 |
| just_audio_harmonyos | 0.0.1（**vendored path**：`packages/just_audio_harmonyos`） | pub.dev（Wayaer）+ 本地修复 | just_audio 0.10.6 | 配套 audio_session_harmonyos；上游 0.0.1 的 `MediaSource.ets` 未实现 API 26 新增的 `enableOfflineCache()/getID()`，ArkTS 报 `incorrectly implements media.MediaSource`，已 vendored 补齐（见 §9） |
| audio_session_harmonyos | 0.0.1 | pub.dev（Wayaer） | audio_session 0.2.4 | just_audio 传递依赖，显式声明锁版本 |
| wakelock_plus_harmonyos | 0.0.1 | pub.dev（Wayaer） | wakelock_plus 1.3.3 | 播放防熄屏 |
| package_info_plus_harmonyos | 0.0.1 | pub.dev（Wayaer） | package_info_plus 8.3.1 | 与项目锁定 8.x 兼容（PI 3.2.1） |
| flutter_secure_storage_ohos | 1.0.0 | `github.com/ClosedHarmony/flutter_secure_storage_ohos` ref `main` → 锁定 `545fb02` | flutter_secure_storage 10.3.4 | 原生-only，通道名与官方一致；注：pub.dev 上同名 1.0.0 要求 Dart <3.0，不可用 |
| record_ohos | 1.0.0 | `github.com/ClosedHarmony/record_ohos` ref `main` → 锁定 `851a667` | record 7.1.1 | 原生-only；注：pub.dev 同名包只配 record PI 1.x，不可用 |
| saver_gallery | ^5.1.0 | pub.dev | 替代 gal 2.3.3 | OHOS 用 SaveButton/授权弹窗，**无需媒体库权限**；lib 侧由 task-5 切换 |

其他端影响：除 `saver_gallery`（android/ios/ohos 三平台，与 gal 并存不冲突）外，其余包只声明 ohos，
Android/iOS/Windows/macOS/Linux 构建不会注册它们，`flutter pub get` 只是多解析几个包。

`screen_brightness_ohos 2.1.4`、`flutter_image_compress_ohos 0.0.3+1` 由官方 app-facing 包自动带入
（lock 里本来就有），**无需显式声明**。

---

## 3. 改动二：`dependency_overrides` 新增 11 条 CPF-Flutter OHOS fork

全部来自 `gitcode.com/CPF-Flutter` 组织；均用 `git ls-remote` + raw pubspec 逐条核对过存在性与版本。
TAG 规则 `<上游版本>-ohos-<x.y.z>`，分支名如 `br_v7.1.4_ohos`。

> **2026-10 起全部锁定到 40 位 commit SHA**（下表「→」后为短 SHA），分支/TAG 仅作来源记录。
> 校验：`dart tool/check_ohos_pubspec.dart`；非 OHOS 平台回归：`--portable`。

| 包 | 上游版本 → fork 版本 | ref | 其他端影响 / 备注 |
|---|---|---|---|
| device_info_plus | 12.3.0 → 12.3.0 | `br_device_info_plus-v12.3.0_ohos` → `8b5ba6a` | 零版本差；替代原 `device_info_plus: 12.3.0` override |
| connectivity_plus | 7.0.0 → 7.0.0 | `br_connectivity_plus-v7.0.0_ohos` → `9514235` | 零版本差 |
| open_filex | 4.7.0 → 4.7.0 | TAG `4.7.0-ohos-1.0.0` → `850a9ab` | 零版本差 |
| mobile_scanner | 7.4.2 → **7.1.4** | `br_v7.1.4_ohos` → `f5a4ff5` | 降级，`qr_login_scan_page` 需回归 |
| volume_controller | 3.7.0 → **3.6.0** | `br_v3.6.0_ohos_dev` → `3cf0457` | 满足 `^3.6.0` |
| app_links | 7.2.1 → **7.0.0** | TAG `7.0.0-ohos-1.0.1` → `109fac2`，path `app_links` | 没用 7.2.2 分支：其 pubspec 带 `resolution: workspace`，git 依赖下有解析风险 |
| flutter_local_notifications | 21.0.0 → **22.0.1** | vendored `packages/flutter_local_notifications`（源 `br_3.41_dev` @ `714178b`，删 PUBLISH_AGENT_REMINDER） | 升大版本，21→22 API 需 task-5 适配 |
| sqflite（传递依赖） | 2.4.4 → **2.4.2+1** | `br_3.41_dev` → `9627805`，path `sqflite` | fork 内 `sqflite_ohos` 是 path 依赖，随 checkout 解析 |
| flutter_inappwebview | 6.2.0-beta.3 → **6.1.5** | `br_v6.1.5_ohos` → `389cf40`，path `flutter_inappwebview` | ⚠️ 最高风险，24 处业务引用 |
| flutter_inappwebview_platform_interface | 1.4.0-beta.3 → **1.3.0+1** | 同上 ref，path `flutter_inappwebview_platform_interface` | 必须与 app-facing 同来源，否则 pub source 冲突 |
| ota_update | 7.1.0 → **7.0.2** | `br_3.35` → `feff13b` | 7.0.2 缺 `OtaStatus.INSTALLATION_DONE/ERROR`，见 §6 |

**构建期修正（2026-10-21 13:50，Lead 执行）**：

- `flutter_inappwebview_linux` / `flutter_inappwebview_windows` 的本地 path override **已移除**：
  仓库内 vendored 的桌面 fork 是 6.2.0-beta.3 配套（平台接口 1.4.0-beta），与 6.1.5 的 PI 1.3.0+1
  类型冲突，会让 OHOS 的 kernel 编译失败；6.1.5 fork 自身通过相对 path 引用其 windows/linux 实现，
  不再需要覆盖。桌面端旧修复如需恢复，得同步升级 inappwebview 主包（独立事项）。
- 新增 `flutter_math_fork: path: packages/flutter_math_fork` vendored override：上游 0.7.4 的
  `TargetPlatform` switch 未覆盖 `TargetPlatform.ohos`，触发
  `type 'TargetPlatform' is not exhaustively matched` 编译错误（见 §9）。
- `flutter_rust_bridge: 2.12.0` 保留（与 rhttp codegen 对齐）。

### 3.1 最终 `dependency_overrides` 块（可直接复制比对）

```yaml
dependency_overrides:
  device_info_plus:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git, ref: 8b5ba6a9ef3a28558177e9193319a0700f9cc640, path: packages/device_info_plus/device_info_plus }
  connectivity_plus:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git, ref: 9514235dda402b432b860a31c69d4dc5153891f5, path: packages/connectivity_plus/connectivity_plus }
  open_filex:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_open_filex.git, ref: 850a9abd0220316dc2bb45924315cb2304ff4ab6 }
  mobile_scanner:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner.git, ref: f5a4ff52f003e1645db1d4de743a2db0313665a8 }
  volume_controller:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_volume_controller.git, ref: 3cf0457a6e9dd21f59a62bd18407e94e68a1e081 }
  app_links:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_app_links.git, ref: 109fac28a22c3f5ab403049adec46412dacf1acd, path: app_links }
  flutter_local_notifications:
    path: packages/flutter_local_notifications   # vendored（源 br_3.41_dev @ 714178b）
  sqflite:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_sqflite.git, ref: 9627805b994b89d8abc273a450bfb176142c5860, path: sqflite }
  flutter_inappwebview:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git, ref: 389cf40dbb647f1df7272de5ea6b3401efe27a75, path: flutter_inappwebview }
  flutter_inappwebview_platform_interface:
    git: { url: https://gitcode.com/CPF-Flutter/flutter_inappwebview.git, ref: 389cf40dbb647f1df7272de5ea6b3401efe27a75, path: flutter_inappwebview_platform_interface }
  ota_update:
    git: { url: https://gitcode.com/CPF-Flutter/fluttertpc_ota_update.git, ref: feff13ba2bb3c1ec31c15ed21e2e75fe2e8a9c28 }
  # 构建期追加（vendored 本地修复，见 §9）：
  flutter_math_fork: { path: packages/flutter_math_fork }
  # 注意：flutter_inappwebview_linux / _windows 的 path override 已移除（与 6.1.5 PI 冲突）。
  flutter_rust_bridge: 2.12.0
```

（`pubspec.yaml` 中保留多行 + 中文注释的等价写法；`device_info_plus: 12.3.0` 已被 git override 取代。）

---

## 4. 验证结果（本机替代校验）

1. **版本解析**：`dart pub get` + 14 个 git 依赖换成本地 clone 的 path 替身 →
   `Changed 344 dependencies!`，exit 0，**无冲突**。关键解析结果：
   `flutter_inappwebview 6.1.5 / PI 1.3.0+1 / _ohos 1.1.3`、`mobile_scanner 7.1.4`、
   `app_links 7.0.0`、`flutter_local_notifications 22.0.1`、`sqflite 2.4.2+1 + sqflite_ohos 2.4.2`、
   `ota_update 7.0.2`、`saver_gallery 5.1.0`、`device_info_plus 12.3.0`、`connectivity_plus 7.0.0`。
2. **联邦实现均被带入**：`path_provider_ohos 2.2.1`、`shared_preferences_ohos 2.2.0`、
   `url_launcher_ohos 6.3.0`、`image_picker_harmonyos 0.0.1`、`video_player_harmonyos 0.0.1`、
   `just_audio_harmonyos 0.0.1`、`audio_session_harmonyos 0.0.1`、`wakelock_plus_harmonyos 0.0.1`、
   `package_info_plus_harmonyos 0.0.1`、`flutter_secure_storage_ohos 1.0.0`、`record_ohos 1.0.0`。
3. **lib 层 API 破坏**（自定义 analyzer，840 文件）：61 errors，其中**依赖降级导致 4 处**，见 §6；
   其余 57 处是既有/与依赖无关（l10n 生成文件缺失 8 处 + 其级联的 `toolPanel_*` 空安全 35 处 +
   `markdown_toolbar` double/int 6 处等）。
4. **hvigor 插件前置检查**：按 `docs/ohos-build-notes.md` §8，凡声明 `platforms: ohos` 的包，
   其包目录必须有合法 `ohos/` 工程（`oh-package.json5` + `src/main/module.json5` + `hvigorfile.ts` +
   `build-profile.json5`），否则 hvigor 解析阶段直接报错。已逐个检查本轮引入的 **22 个 OHOS 插件包
   （12 新增 + 10 override）全部 5/5 齐全**（在 `.cache/ohos-pkgs/` clone 与 `.pub-cache` 中核实）。
   注：`flutter_secure_storage` / `record` 官方主包本身没有 ohos 平台声明，靠上面两个原生-only 包补，
   不会进 `plugins.ohos` 列表的冲突项。

---

## 5. 第一轮**未**纳入、后续已补齐的包

> 本节记录第一版策略下故意缓做的项；share_plus / file_picker 已在 **§10** 补齐（vendored path 依赖）。

| 包 | 第一轮缓做原因 | 最终结果 |
|---|---|---|
| **share_plus** | CPF `br_share_plus-v12.0.1_ohos` 的 `share_plus_platform_interface` 带**嵌套 git 依赖**（`gitcode.com/openharmony-sig/flutter_packages` ref `master`，大仓库），且会把 `path_provider` 变成第二种 source，风险高、易拖垮首次 pub get | ✅ §10.1：vendored `packages/share_plus` + `packages/share_plus_platform_interface`（PI 改 hosted path_provider），path 依赖接入 |
| **file_picker** | CPF `fluttertpc_file_picker@10.3.8-ohos-1.0.0` 的**根 pubspec 名是 `file_picker_ohos`**，无法作为 `file_picker` 的 override（包名不匹配）；若作为额外依赖，其 android 平台声明会与官方 file_picker 在 Android 上重复注册同一 AAR | ✅ §10.2：vendored 成 `packages/file_picker`（包名改回 + 入口 re-export），零业务改动 |
| chat_bottom_container | 需升 0.4.1 → ^0.5.3 才有 ohos 平台声明，属跨端升级 + 聊天页回归 | 仍缓做（lib 已可正常运行，非阻塞） |
| fluttertoast（catcher_2 传递） | CPF 8.2.8 可加，但属于 P3，lib 无直接引用，且要验证 catcher_2 与新 API 兼容 | 仍缓做（需要错误 toast 时再加） |
| flutter_foreground_task / workmanager / window_manager / screen_retriever / flutter_acrylic / win32_registry / flutter_displaymode / flutter_dynamic_icon_plus / rhttp / native_animated_image / flutter_avif / flutter_js / full_svg_flutter / super_clipboard / gal / flutter_timezone | 保留依赖不动，OHOS 上**无实现**，走运行期降级/平台守卫（task-5 负责代码侧） | 见 §6 清单与 docs/ohos-port-status.md §5 |

---

## 6. OHOS 上「不可用 / 需降级」清单（交给 task-5 / Lead）

> 状态：A 组 4 处 **已于 2026-10-21 Lead 修复**（`docs/ohos-port-status.md` §3，`dart analyze lib` 已 0 error），
> 保留作历史定位记录；B 组已由 lib 侧 `ohos_compat` 守卫；C 组已解决（codegen 已生成）。

**A. 由本次 pubspec 改动直接引入的编译错误（已修复）**

| 文件:行 | 错误 | 原因 | 建议 |
|---|---|---|---|
| `lib/pages/webview_page.dart:355` | 未定义命名参数 `onDownloadStarting` | inappwebview 6.2.0-beta.3 → 6.1.5 | 删除/改用 `onDownloadStartRequest`（6.1.5 API） |
| `lib/services/webview_settings.dart:178` | `setMemoryUsageTargetLevel` / `MemoryUsageTargetLevel` 不存在 | 同上（6.2 新增 API） | 加 SDK 版本守卫或直接删除 |
| `lib/services/apk_download_service.dart:136,143` | `OtaStatus.INSTALLATION_DONE` / `INSTALLATION_ERROR` 不存在 | ota_update 7.1.0 → 7.0.2 | 用 `OtaStatus.INSTALLING/INSTALLED/ERROR` 旧枚举；OHOS 侧改用 `executeOhos()` 分支 |

**B. 无 OHOS 实现、需要在 lib 加守卫/降级**（pubspec 层保留依赖，其他五端不受影响）

`rhttp`（已有 5s 超时 forceDisable）、`native_animated_image`（回退 Flutter ImageProvider）、
`flutter_avif` + `avif_fast_bridge`（FFI 符号不存在，需条件导入）、`super_clipboard`（纯文本降级）、
`flutter_js`（换 flutter_qjs 或降级）、`full_svg_flutter`（改 jovial_svg）、`gal`（OHOS 改用 saver_gallery）、
`flutter_timezone`（自写 MethodChannel）、`flutter_displaymode`、`flutter_dynamic_icon_plus`、
`flutter_foreground_task`、`workmanager`、`window_manager`/`screen_retriever`/`flutter_acrylic`、
`win32_registry`、`pro_image_editor`（仅 android 原生）、`catcher_2` 的 email/toast handler、
`share_plus`/`file_picker`（本轮未接 OHOS 实现，调用处需 try/catch 或隐藏入口）。

**C. 构建前置（与依赖无关，但会挡住 `flutter build hap`）——已解决**

- `lib/l10n/generated/*` 与 `lib/l10n/slang/strings.g.dart` 是生成物：已跑 `dart run tool/gen_l10n.dart`
  生成（当前工作区存在，构建前若清理工作区需重新生成），否则会报 45+ 个 l10n 相关 error。
- `repo/core/doh_proxy` Rust 产物、`third_party/sqlite3` build hook 属 task-2/task-6 范畴（已处理）。


---

## 7. 回滚方式（逐级）

| 粒度 | 操作 |
|---|---|
| 全量回滚 pubspec | `git -C repo checkout -- pubspec.yaml pubspec.lock` → `flutter pub get` |
| 只回滚 override | 删除 `dependency_overrides:` 中 `HarmonyOS / OHOS：CPF-Flutter` 注释段（11 条），把 `device_info_plus: 12.3.0` 加回 → `flutter pub get` |
| 只回滚新增依赖 | 删除 `dependencies` 中 `HarmonyOS / OHOS 平台实现（叠加包）` 注释段（12 条）→ `flutter pub get` |
| 回滚到双 pubspec 方案 | 把 §3.1 的 override 块整体搬入 `pubspec.ohos.yaml`，主 pubspec 恢复原样 |

回滚风险：`pubspec.lock` 会被 `flutter pub get` 重写（原 lock 已由 git 保管），无需手工修。

---

## 8. 风险与后续建议

1. **最大风险仍是 Flutter 3.47.7-canary vs 插件最高声明 3.41**：全部 12 个 OHOS 实现/override 包都要在
   `@ohos/flutter_ohos` 新 har 上重新编译验证；pub get 通过 ≠ 插件能编译（ArkTS 侧 `checkOhosPluginsDependencies`）。
2. **inappwebview 6.1.5 + ArkWeb**：登录 WebView/OAuth 是 P0，建议 Lead 优先跑一次 HAP 构建看 ArkTS 编译结果。
3. **saver_gallery 5.1.0 要求 Flutter ≥3.44**（当前 3.47.7 ✓），但需确认其 `ohos/` 用的是 SaveButton 而非受限权限。
4. **单 pubspec 策略的副作用**：Android/iOS/桌面端本轮也会用 fork 版本（inappwebview 6.1.5、mobile_scanner
   7.1.4、ota_update 7.0.2、local_notifications 22 等）。若近期还要发五端版本，建议尽快拆双 pubspec（§7 最后一行）。
5. 下一轮可补：share_plus（vendored PI）、file_picker（双 pubspec + import 切换）、chat_bottom_container 0.5.3、
   fluttertoast 8.2.8。

### 8.1 已预检的 hvigor/插件工程风险（Lead 构建时优先看）

- 各插件 `ohos/oh-package.json5` 对 `@ohos/flutter_ohos` 的写法不统一（`file:libs/flutter.har` /
  `file:./har/flutter.har` / 无）。已确认 SDK 的 hvigor 插件（
  `tools/flutter/packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts:177`）会用
  `overrides['@ohos/flutter_ohos'] = file:<真实 har>` **全局改写**，路径写法不一致不影响构建。
  **例外**：`ota_update/ohos/oh-package.json5` 的 `dependencies` 为空（未声明 `@ohos/flutter_ohos`）。
  若 hvigor 报 `@ohos/flutter_ohos` 解析失败，两种处理（二选一）：① 把 ota_update 从 override 撤掉
  （P2 功能，不影响首启）；② 在该文件补 `"@ohos/flutter_ohos": "file:./har/flutter.har"`。
- `sqflite_ohos/ohos/build-profile.json5` 的 `targets` 是 `sqflite_ohos` + `ohosTest`（没有 `default`），
  其余插件都是 `default`。若 hvigor 报 target 找不到，需在构建脚本里 patch 成 `default`（或该插件
  单独降级：`sqflite` 只影响图片/主题缓存，不阻塞首屏）。
- 其余 20 个插件 `ohos/` 四件套齐全且 build-profile 均为标准 `default` target（§4 已逐个核实）。

---

## 9. 真实构建验证与构建期追加修复（2026-10-21 13:50 起，Lead 执行）

### 9.1 验收证据（依赖层）

- **`flutter pub get` ✅**：`repo/pubspec.lock` 重生成（94,734 B，22 条 `source: git` 条目），
  `.dart_tool/package_config.json` 与 `.flutter-plugins-dependencies` 均生成。
- **`flutter build hap` ✅**：`.flutter-plugins-dependencies` 里 **24 个 OHOS 插件**注册成功
  （app_links / audio_session_harmonyos / connectivity_plus / device_info_plus /
  flutter_image_compress_ohos / flutter_inappwebview_ohos / flutter_local_notifications /
  flutter_secure_storage_ohos / image_picker_harmonyos / just_audio_harmonyos / mobile_scanner /
  open_filex / ota_update / package_info_plus_harmonyos / path_provider_ohos / record_ohos /
  saver_gallery / screen_brightness_ohos / shared_preferences_ohos / sqflite_ohos / url_launcher_ohos /
  video_player_harmonyos / volume_controller / wakelock_plus_harmonyos）；Lead 记录 25 个 OHOS 插件模块
  参与 hvigor 编译；HAP 已签名、安装并在模拟器启动渲染（`docs/ohos-port-status.md` §1）。
- 结论：**「pub get 成功 + build 不再因依赖解析/平台声明失败」达标**；后续失败点均在 ArkTS/Rust 原生
  与 Cloudflare 网络层（非 pubspec 依赖解析）。

### 9.2 构建期在依赖层追加的修复（以本节为最终状态）

| # | 修复 | 位置 | 原因 / 回滚 |
|---|---|---|---|
| 1 | **vendored `just_audio_harmonyos`**（pub.dev 0.0.1 → `path: packages/just_audio_harmonyos`） | `packages/just_audio_harmonyos/ohos/src/main/ets/MediaSource.ets` | 上游未实现 API 26 新增的 `media.MediaSource.enableOfflineCache()/getID()`，ArkTS 报 `incorrectly implements media.MediaSource`。回滚：pubspec 改回 `just_audio_harmonyos: 0.0.1` + 删除该目录（OHOS 将编译失败） |
| 2 | **vendored `flutter_math_fork` 0.7.4**（新增 `dependency_overrides` path） | `packages/flutter_math_fork/lib/**` 4 处 `TargetPlatform.ohos` 分支 | 上游 `TargetPlatform` switch 不穷尽 OHOS 枚举 → `type 'TargetPlatform' is not exhaustively matched`。回滚：删除 override + 目录（OHOS 将编译失败） |
| 3 | **移除 `flutter_inappwebview_linux/_windows` 的 path override** | `pubspec.yaml` dependency_overrides | 本地 vendored 桌面 fork 是 6.2.0-beta.3/PI 1.4.0-beta，与 6.1.5/PI 1.3.0+1 类型冲突，OHOS kernel 编译失败。桌面端恢复旧修复需升级 inappwebview 主包（独立事项） |
| 4 | **`packages/fluxdo_render` submodule 内补 OHOS 分支**（`text_selection_rules.dart`、`selection_content_layer.dart`，`TargetPlatform.ohos`） | submodule 工作区（**当前 `-dirty`，未提交**） | 与 #2 同类问题。⚠️ 主仓库只记录 submodule 指针，这笔修改不会随主仓库提交；建议后续 fork/提交到 fluxdo_render 仓库，否则重跑 `git submodule update` 会丢 |
| 5 | `assets/certs/.gitkeep` | repo/assets | Flutter 资源打包要求目录存在（非依赖层，构建必需） |
| 6 | l10n 生成物 | `lib/l10n/generated/*`、`lib/l10n/slang/strings.g.dart` | 构建前置 codegen（`dart run tool/gen_l10n.dart`）；生成后 `dart analyze lib` 0 error |

> #1/#2/#4 均为「上游插件未适配 Flutter 3.47 的 `TargetPlatform.ohos` / API 26 ArkTS 接口」的
> 最小本地补丁，不改 Dart 业务逻辑；**三个 vendored 目录目前是 untracked（`?? packages/flutter_math_fork/`、
> `?? packages/just_audio_harmonyos/`）或 submodule dirty，提交/固化前请勿清理工作区**。

### 9.3 依赖层缺口（Share / FilePicker）——**已于 2026-10-21 晚补齐，详见 §10**

| 包 | 原状态 | 处理结果 |
|---|---|---|
| **share_plus** | hosted 12.0.2，无 ohos 实现；7 个业务文件直接调用 `SharePlus.instance.share(...)`（邀请链接、帖子分享、导出等）→ 运行期 MissingPluginException | ✅ 已 vendored `packages/share_plus`（12.0.1 + ohos/ ArkTS）+ `packages/share_plus_platform_interface`（去掉嵌套 git 依赖），`pubspec.yaml` 改 path 依赖 |
| **file_picker** | hosted 10.3.10，无 ohos 实现；6 个业务文件（附件上传、编辑器选图、导出保存）→ 运行期 MissingPluginException | ✅ 已 vendored `packages/file_picker`（CPF fork 10.3.8-ohos-1.0.0，包名改回 `file_picker` + `lib/file_picker.dart` re-export），业务代码零改动 |
| 其他 | `gal`/`flutter_timezone`/`super_clipboard`/`flutter_avif`/`native_animated_image`/`flutter_js`/`rhttp`/`doh_proxy` 等 | 已由 lib 侧 `ohos_compat` 降级/守卫（见 docs/ohos-port-status.md §5），专项排期 |

### 9.4 最终 lock 版本快照（关键包，便于回归比对）

> ⚠️ 本节为 2026-10-21 13:50 lock 的快照；§10 的 share_plus/file_picker path 替换后，这两项需等
> Lead 重跑 `flutter pub get` 才写入 lock（预期 `share_plus 12.0.1 [path]`、`file_picker 10.3.8 [path]`）。

`device_info_plus 12.3.0`(git) · `connectivity_plus 7.0.0`(git) · `open_filex 4.7.0`(git) ·
`mobile_scanner 7.1.4`(git) · `volume_controller 3.6.0`(git) · `app_links 7.0.0`(git) ·
`flutter_local_notifications 22.0.1`(git) · `sqflite 2.4.2+1`(git) + `sqflite_ohos 2.4.2`(path) ·
`flutter_inappwebview 6.1.5`(git) + `_platform_interface 1.3.0+1`(git) + `_ohos 1.1.3`(path) ·
`ota_update 7.0.2`(git) · `flutter_secure_storage_ohos 1.0.0`(git @545fb022) ·
`record_ohos 1.0.0`(git @851a667b) · `path_provider_ohos 2.2.1` · `shared_preferences_ohos 2.2.0` ·
`url_launcher_ohos 6.3.0` · `saver_gallery 5.1.0` · `just_audio_harmonyos 0.0.1`(path) ·
`flutter_math_fork 0.7.4`(path) · `screen_brightness_ohos 2.1.4` · `flutter_image_compress_ohos 0.0.3+1`。

---

## 10. 追加交付：share_plus / file_picker 的 OHOS 接入（vendored，2026-10-21 晚）

> 目标：消除 OHOS 上「分享」与「选文件/保存」两条高频链路的 MissingPluginException。
> 验收口径：`flutter pub get` + `flutter build hap` 通过，且 **lib 业务代码零改动**（import/调用点不变）。

### 10.1 share_plus（7 处业务调用）

| 项 | 内容 |
|---|---|
| vendored 包 | `packages/share_plus`（12.0.1，CPF `br_share_plus-v12.0.1_ohos`，含 `ohos/` ArkTS Share Kit 实现） |
| 配套 | `packages/share_plus_platform_interface`（6.1.0，**去掉**对 `openharmony-sig/flutter_packages` 的嵌套 git 依赖，`path_provider` 改回 hosted `^2.1.4`） |
| pubspec 改动 | `dependencies`：`share_plus: ^12.0.1` → `share_plus: { path: packages/share_plus }` |
| 其他端影响 | Android/iOS/macOS/Windows/Linux 由 12.0.2 → 12.0.1（patch 级），行为不变 |
| 许可证 | BSD-3-Clause（两个包各自 `LICENSE` 保留）；说明见各自 `VENDOR.md` |

### 10.2 file_picker（6 处业务调用）

| 项 | 内容 |
|---|---|
| vendored 包 | `packages/file_picker`（来自 CPF `fluttertpc_file_picker` TAG `10.3.8-ohos-1.0.0` = 上游 10.3.8 + `ohos/` ArkTS 实现） |
| 关键改造 | fork 原包名 `file_picker_ohos`、入口 `lib/file_picker_ohos.dart` → 本副本改名为 `file_picker`，新增 `lib/file_picker.dart` 做 re-export，14 个文件的自引用 `package:file_picker_ohos/` → `package:file_picker/`，`ohos/oh-package.json5` 与 `module.json5` 的 `name` 同步改为 `file_picker`（hvigor 按插件名注入依赖，必须一致） |
| pubspec 改动 | `dependencies`：`file_picker: ^10.3.10` → `file_picker: { path: packages/file_picker }` |
| 其他端影响 | Android/iOS/macOS/Windows/Linux 由 10.3.8 + 上游 OHOS 适配代码提供（**10.3.10 → 10.3.8**，patch 级），需五端回归一次选文件/保存 |
| 许可证 | MIT（`LICENSE` 保留）；说明见 `VENDOR.md` |

### 10.3 验证结果（含 Lead 会话真实构建）

**沙箱内静态验证（本 agent）**

1. **依赖解析预验证**：新建 `.tmp/vendorcheck` 临时工程 path 依赖两个 vendored 包 + `flutter` sdk →
   `dart pub get` ✅ exit 0（`Changed 69 dependencies`，`share_plus 12.0.1 from path`、
   `share_plus_platform_interface 6.1.0 from path`；无 git 依赖、无版本冲突）。
2. **Dart API 兼容性验证**：把 repo 现有 `.dart_tool/package_config.json` 中 `file_picker`/`share_plus`/
   `share_plus_platform_interface` 的 rootUri 临时指到 vendored 目录，用进程内 analyzer 分析
   `repo/lib` → **848 文件 0 error**（证明 7 + 6 处业务调用与 vendored Dart API 完全兼容，业务代码无需改）；
   分析完已恢复原 package_config。
3. **vendored 包自检**：同法分析 3 个 vendored 包，0 error（覆盖到被 lib 引用的文件）。

**真实构建验证（Lead 会话，2026-10-21 15:43–15:45，日志
`.cache/ohos-build/logs/build-debug-ohos-x64-20261021-154315.log`）**

- `flutter pub get` ✅：`* file_picker 10.3.8 from path packages\file_picker (was 10.3.10)`、
  `* share_plus 12.0.1 from path packages\share_plus (was 12.0.2)`、
  `* share_plus_platform_interface 6.1.0 from path packages\share_plus_platform_interface (was 6.1.0)`，
  `Changed 3 dependencies!`；`pubspec.lock` 中三项均为 `source: path`。
- 插件解析 ✅：`.flutter-plugins-dependencies` 的 `plugins.ohos` 由 24 → **26**（新增 `share_plus`、`file_picker`，
  路径分别指向 `repo/packages/share_plus/`、`repo/packages/file_picker/`）；hvigor `dependencyMap` 也生成了
  `share_plus/oh-package.json5`、`file_picker/oh-package.json5`。
- `flutter build hap` ✅：`Running Hvigor task assembleHap... 108.9s` 完成（仅提示配置调试签名，属预期），
  产出 `repo/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`（344,426,605 B, 15:45:19）
  并签名成功 `.cache/ohos-build/fluxdo-debug-ohos-x64-signed.hap`（344,859,177 B, 15:45:23）。
- **仍需人工/UI 验证**：模拟器里点一次「分享」（邀请/帖子分享）与「选文件/保存」（附件上传、编辑器选图、
  数据管理导出），确认 Share Kit 面板与 Picker 实际行为（构建通过 ≠ 运行期交互正确）。

### 10.4 Lead 验证步骤（已执行，保留供复现）

```powershell
cd C:\Users\iceblock\fluxdo
Set-ExecutionPolicy -Scope Process Bypass -Force; . .\tools\env.ps1
cd repo
flutter pub get     # 预期：Changed 3 dependencies! / 三项 path 依赖写入 lock
cd ..
.\tools\build-ohos.ps1 -Install -Launch
# 预期：assembleHap 成功 + signed HAP；.flutter-plugins-dependencies → plugins.ohos = 26
# UI 验证：分享面板（7 处入口任选）、文件选择/保存（编辑器附件、数据管理导出）
```

失败时最可能的 3 个点（按概率，本次均未触发）：
1. `share_plus/ohos` 或 `file_picker/ohos` 的 ArkTS 在 API 26 下编译报错（类似 just_audio 的接口成员问题）；
2. hvigor 找不到 `file_picker` 模块（已改 `module.json5`/`oh-package.json5` 的 name，若仍报错检查
   `.flutter-plugins-dependencies` 里该插件的 `path` 是否落在 `repo/packages/file_picker/ohos`）；
3. 其他五端 kernel 编译对 10.3.8/12.0.1 有 API 差异（本机 analyzer 已排除 Dart 侧，若报错大概率在
   Android/iOS 原生工程，不影响 OHOS 验收）。

### 10.5 回滚

```yaml
# pubspec.yaml → dependencies
share_plus: ^12.0.1
file_picker: ^10.3.10
```

然后删除 `packages/share_plus/`、`packages/share_plus_platform_interface/`、`packages/file_picker/`，
`flutter pub get` 即回到原状。

---

## 11. 固化清单（提交前必做）

### 11.1 `packages/fluxdo_render` submodule 补丁

- 补丁已导出：`docs/patches/fluxdo_render-ohos.patch`（2 文件，`TargetPlatform.ohos` 分支：
  `text_selection_rules.dart`、`selection_content_layer.dart`）。
- 当前 submodule 工作区是 **`-dirty`** 状态：主仓库只记录 submodule 指针，**不包含**这份修改。
  重新 `git submodule update --init` / 换机后会丢失 → 必须二选一固化：
  1. 在上游 `Lingyan000/fluxdo_render` 提交该补丁并更新 gitlink；或
  2. 保留 patch 文件，在构建脚本/文档中要求执行：
     ```powershell
     git -C repo\packages\fluxdo_render apply ..\..\docs\patches\fluxdo_render-ohos.patch
     ```
- 校验：`git -C repo/packages/fluxdo_render status --porcelain` 出现 2 个 ` M` 即为已打补丁。

### 11.2 必须 `git add` 的 vendored 目录（当前均为 untracked）

```
repo/packages/file_picker/
repo/packages/share_plus/
repo/packages/share_plus_platform_interface/
repo/packages/flutter_math_fork/
repo/packages/just_audio_harmonyos/
```

每个目录都带 `VENDOR.md`（来源 commit/TAG、许可证、本地改动清单、升级/回滚方式）：

| 包 | 上游 | 许可证 | 本地改动 |
|---|---|---|---|
| file_picker | CPF `fluttertpc_file_picker@10.3.8-ohos-1.0.0`（MIT） | MIT | 包名改回 file_picker + 入口 re-export + 自引用重写 + ohos 模块名 |
| share_plus | CPF `br_share_plus-v12.0.1_ohos`（BSD-3） | BSD-3 | 零代码改动（剔除 example/test 减体积） |
| share_plus_platform_interface | CPF 同分支（BSD-3） | BSD-3 | pubspec：嵌套 git `path_provider` → hosted `^2.1.4` |
| flutter_math_fork | pub.dev 0.7.4（Apache-2.0） | Apache-2.0 | 4 处 `case TargetPlatform.ohos:` |
| just_audio_harmonyos | pub.dev 0.0.1（BSD-3） | BSD-3 | `MediaSource.ets` 补 API 26 `enableOfflineCache()/getID()` |

> 建议提交时把 `docs/patches/`、5 个 `VENDOR.md` 与 pubspec 改动放在同一个 commit，便于整体回滚。


