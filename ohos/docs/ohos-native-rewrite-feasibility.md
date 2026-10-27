# FluxDO × HarmonyOS 7：全原生架构替代可行性评估
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从 `module.json5` 删除。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 评估对象：FluxDO v0.2.29（Flutter 第三方 Linux.do 客户端）→ HarmonyOS 7 / API 26 现有移植成果  
> 基线：`repo` @ `ba28efd`（2026-10-21），`docs/ohos-*.md` 9 份移植文档，本机 API 26 SDK（`ets/api` 顶层 470 个 `.d.ts`，含子目录共 677 个）+ HMS SDK（164 个 `.d.ts`）  
> 评估日期：2026-10-21  
> 方法：代码/文档盘点 + 本机 SDK 声明核对 + 现网 26 个已注册 OHOS 插件 ArkTS 源码核对 + 已安装 hmos skill 知识库 + 分域三点估算  
> 性质：决策建议文档，不是迁移实施计划；所有估算均为量级估算（±40%），不应作为报价或排期承诺。

---

## 0. 结论摘要

### 0.1 三维结论

| 维度 | 结论 | 置信度 |
|---|---|---|
| 技术可行性 | **有条件可行**。24 个能力域 + cook JS 单列（共 25 项）中未发现“绝对做不到”的硬阻塞；4 个 A 级能力已有本机可运行实现，18 个为 B 级（API/库存在，需适配；其中 CF/AVIF 为 B-，含未验证门禁），3 个 C 级需 PoC/自研（HTML 渲染、编辑器、cook JS）。**CF 评为 B-（不是否决项）**：API 23+ 的 `fetchAllCookies` + `WebHttpCookie` 可读 cookie 值与 `isHttpOnly` 属性，现有 Flutter 插件用旧 API 只解析字符串，是“读不到”的主要来源；仍需设备 A/B 验证。**AVIF 为 B-**：自编 `libohos_avif.so` 已存在，但未进当前 HAP、NAPI 包装/实测未完成 | **中**（3 个 C 项零原型、ArkTS 从未本地编译、渲染器 0 行） |
| 经济可行性 | **不建议一次性全量重写**。完整对标约 **118–200 人月**（含设计/QA/PM，中位约 157；按非空行口径；物理行口径约高 10%）；核心 MVP 约 **40–65 人月**；精简版（砍长尾）约 **60–90 人月**；4 人团队完整对标约 **2.5–4.5 年** | 中 |
| 维护可行性 | **不建议长期双代码库**。OHOS 全原生意味着与 Flutter 上游永久分叉，上游每个功能都要双写；三年维护成本 54–108 人月（1.5–3 人月/月，即 18–36 人月/年），高于同时期 Flutter 移植维护（18–54 人月） | 高 |

### 0.2 一句话回答

**“能，但不划算。”** 技术上可以全部用 ArkTS/ArkUI + 系统 Kit + NAPI 重写；但代价是重建一套 30 万行级应用，并且放弃 Android/iOS/Windows/macOS/Linux 共享的 Flutter 代码（仓库另有 web 目录）。  
真正的硬骨头不是平台 API，而是 **Discourse HTML 渲染 + 富文本编辑器 + UI 全量重写**；CF 已有 `fetchAllCookies` 这条 API 路径，属于“可验证”而非“不可解”。  
如果目标只是通知/后台/分享/扫码/深链/账号等系统集成能力，**混合方案约 10–20 人月，而全原生约 118–200 人月（约 1/6–1/20）**；但体积、启动、引擎移除这三项收益只有全原生能拿到。只有当 HarmonyOS 成为主战场、且愿意投入 4+ 名原生专职开发 12+ 个月时，全原生才具备经济性。

### 0.3 关键数字

| 指标 | 当前值 | 说明/来源 |
|---|---:|---|
| 应用 Dart 代码 | **293,108 非空行 / 849 文件**（物理行 322,795） | `repo/lib`（评估时含未提交 AVIF 改动，见 §2.4） |
| 一方 Dart 总量 | **约 36 万非空行（物理行约 40 万）** | lib 29.3 万 + `fluxdo_render/lib` 4.1 万 + `ai_model_manager`、`common_ui`、`m3e_ui`、`extended_image_lite` 等约 2.7 万 |
| 自研渲染/编辑器包 | 41,126 行 / 122 文件（lib 部分） | `repo/packages/fluxdo_render/lib`（渲染 5,837、解析 2,528、选区 2,946、节点 2,465、编辑器 22,999） |
| 页面 | 46 个顶层页面文件 / 32,506 行；含 4 个子目录共 103 文件 / 61,503 行 | `repo/lib/pages`（详情 16,131、聊天 7,995、网络设置 4,486、书签 385） |
| 组件 | 315 文件 / 100,855 行 | `repo/lib/widgets` |
| 服务 / Provider / 模型 | 209 / 70 / 39 文件，51,875 / 14,744 / 8,142 行 | `repo/lib/services` 等；131 个 Provider、71 个 Notifier |
| 测试 | 300 文件 / 49,272 行 | `repo/test` |
| 依赖 | 119 个直接依赖 + 13 个 override + 4 个 dev 依赖；lock 实测约 361 包 | `repo/pubspec.yaml` / `pubspec.lock` |
| OHOS 插件实现 | 26 个已注册（+1 个 `flutter_native_x86_64` 辅助） | `.flutter-plugins-dependencies`、`repo/ohos/entry/oh_modules` |
| 原生库（arm64-v8a 目录） | DOH 6.34 + rhttp 5.64 + 动图解码 0.54 + AVIF 0.86 = **13.38 MB**；**当前 release HAP 未含 AVIF `.so`** | `repo/ohos/entry/libs/arm64-v8a` |
| ArkTS 代码 | 约 460 行业务（桥 335 + Ability 34 + 入口 19 + 注册 72）+ 约 155 行测试/模板；**NAPI 0 行、CMakeLists 0 个** | `repo/ohos/entry/src/main/ets` |
| release HAP | 114.3 MB（签名后，2026-10-21 22:04）；**x64 fat：引擎仅 x86_64（libapp 35.69 + libflutter 19.99），含双 ABI 原生库 + MiSansVF 19.16 MB**；不可与 arm64 单 ABI 直接比较 | `.cache/ohos-build/fluxdo-release-ohos-x64-signed.hap` |
| debug HAP | 356.2 MB（签名后，22:39） | 同上 debug 文件 |
| 移植验收 | A1–A35 共 35 项通过 | `docs/ohos-acceptance.md` |
| 上游发布节奏 | 9 个月 84 个版本（约 9 版/月），当前 v0.2.29（2026-10-20） | `repo/CHANGELOG.md` |
| 已安装 hmos skill | 39 个，约 267 MB 知识库 | `C:\Users\iceblock\.dsh\profiles\desktop\node_modules\dsh-hmos-skills\skills` |

> 口径说明：`README-ohos.md` 的 release 91 MB 是较早构建记录（该文档同时称 3 个 Rust 库已接入），当前 114.3 MB 是 x64 fat HAP，差异来自引擎/字体/双 ABI 原生库与资源，未逐项归档，不能简单归因于某次改动。**行数默认指“非空行（不含空行、含注释）”；物理行见附录 A（lib 322,795）。**

### 0.4 推荐动作（按优先级）

1. **不做 big-bang（一次性全量重写）**。现有 Flutter 版本已可交付（35 项验收通过），重写的机会成本极高。
2. **先做 B1/B2（混合加深）**：补齐 cook JS、AVIF、富剪贴板、后台/本地通知等能力，增加原生系统入口（通知扩展、分享扩展、深链、实况窗等）。预算约 **10–20 人月**，可拿到全原生大部分“平台能力”收益。
3. **若仍有战略必要，再做 4 周 S0 原生竖切 PoC**：登录+CF+列表+详情渲染+简单回复+编辑器最小竖切，实测原生开发速度与关键风险。G1 通过后再讨论全原生（C）。
4. **C 的启动条件**见 §9.3：OHOS 主战场、Flutter OHOS 分支不可持续、体积/启动硬指标、必须深度系统集成、4+ 原生专职 12+ 个月。任一条件不满足，继续 B。

---

## 1. 评估范围、方法与证据等级

### 1.1 范围

- **在范围内**：OHOS 端把 Flutter（Dart + Flutter engine）替换为 ArkTS/ArkUI + 系统 Kit + NAPI（C++/Rust）的可行性、代价、风险与路线。
- **不在范围内**：Android/iOS/Windows/macOS/Linux 端；新功能；UI 视觉重设计；具体迁移实施。
- **功能基线**：v0.2.29 + 现有移植验收 A1–A35 的能力面；目标平台 API 26 / HarmonyOS 7，手机优先，平板/2in1/折叠屏第二阶段。
- **假设**：AGC/应用市场账号可用（涉及发布证书/App Linking 时）；团队具备 ArkTS 学习能力；上游 Flutter 继续演进；用户数据迁移可接受一次登录/迁移成本（此项本身是风险，见 R8）。

### 1.2 证据优先级

1. **本机 API 26 SDK 声明**：`D:\DevEco Studio\sdk\default\openharmony\ets\api\*.d.ts`（顶层 470 个，递归 677 个）+ `...\hms\ets\api\*.d.ts`（164 个）——API 存在性、签名、版本与限制注释。
2. **现网 OHOS 插件 ArkTS 源码**：`repo/ohos/entry/oh_modules/<plugin>/...` 或 `.cache/ohos-pkgs/...`——真实编译、真实调用系统 Kit 的“可运行证据”。
3. **已安装 hmos skill 知识库**：ArkUI/ArkTS 文档、Push/Scan/Account/Multidevice/测试/DFX 技能——组件约束、最佳实践、平台前置条件。
4. **官方文档/网络检索**：仅作补充，标注来源与日期（本次环境网络检索不可用，未引用在线文档）。

**本次实际使用的 hmos skill（证据/方法来源）**：

| Skill | 用途 | 影响章节 |
|---|---|---|
| `hmos-arkui-mvvm-pattern` | Model/ViewModel/View 分层、V2 状态归属、Repository 边界 | §5 |
| `hmos-arkui-knowledge-retriever` | `RichText`/`RichEditor`/`List`/`Image`/`componentSnapshot` 的组件限制与用法证据 | §4/§6 |
| `hmos-arkts-knowledge-retriever` | ArkTS 语言限制、API 签名、错误码、并发/TaskPool | §5/§6 |
| `hmos-push-kit`（+token/notification/background/voip） | Push Token/AGC 权益/后台消息前置条件 | §4/§6 R7 |
| `hmos-scan-kit-defaultscan` | 扫码登录的原生路径 | §4 #14 |
| `hmos-account-kit-quicklogin-client` | 一键登录（可选增强） | §4/§9 |
| `hmos-multidevice-*` | 手机/平板/2in1/折叠屏适配成本 | §4 #23/§7 |
| `hmos-local-test` / `hmos-instrument-test` | 测试体系与工作量 | §7 |
| `hmos-jscrash-analysis` / `hmos-cppcrash-analysis` / `hmos-native-memleak-analysis` / `hmos-appfreeze-analysis` | 原生 DFX/可观测性成本 | §6 R13 |
| `hmos-arkts-syntax-checker` / `hmos-arkts-deprecated-interface-checker` | CI 质量门禁 | §7 W12 |

### 1.3 评级定义

| 评级 | 含义 |
|---|---|
| **A** | 已有本机可运行实现（插件源码/ArkTS 桥/已验收项） |
| **B** | SDK API 或官方文档存在，需适配/重写，但路径明确 |
| **B-** | B 级路径存在，但含未验证门禁；门禁失败降为 C（本报告用于 CF/AVIF） |
| **C** | 需 PoC 或自研，存在性能/保真/交互不达标风险 |
| **D** | 不适用/建议放弃 |

> 严格区分“API 存在”与“能力达标”：B 只代表有路，不代表体验、性能、上架要求自动满足。

### 1.4 本次评估的局限

- 未执行真实构建/装机（报告为只读评估；PoC 需另行批准并使用 `danger-full-access`）。
- 仅覆盖 API 26 模拟器（x86_64）与现有文档证据；真机相机、CF 住宅 IP、AGC 推送未验证。
- **ArkTS 从未本地编译**：现有 OHOS 工程只做过 TS 语法解析；ArkUI 页面代码为 0 行，所有“能力达标”判断来自 SDK 声明 + 已编译插件，而非亲手运行。
- HTML 渲染、编辑器（以及仍需设备验证的 CF）的结论依赖设计推演与现有代码事实，最终必须由 S0 PoC 证实/证伪。
- 评估期间 `repo` 仍在活跃开发（HEAD `ba28efd`，渲染器子模块 10 月仍有提交；评估中出现未提交的 AVIF 库）；数字会随代码演进变化。

---

## 2. 现状基线：移植做成了什么、还剩下什么

### 2.1 已打通（有实测证据）

| 能力 | 状态 | 证据 |
|---|---|---|
| Flutter → HAP 构建/签名/安装/启动 | ✅ 一条命令可复现 | `tools/build-ohos.ps1`、`tools/ohos-sign.ps1`、`docs/ohos-build-notes.md` |
| Cloudflare 403 | ✅ 挑战真正执行 + 浏览器网络栈兜底；冷启动零点击出列表 | `docs/ohos-cf-fix.md`、`.cache/shot-cold-r5.jpeg` |
| 26 个 OHOS 插件 | ✅ 编译注册（+1 个辅助包） | `.flutter-plugins-dependencies`、`repo/ohos/entry/oh_modules` |
| Rust 原生库 | ✅ DOH / rhttp / 动图解码交叉编译并进包 | `repo/ohos/entry/libs/<abi>/lib*.so`；`docs/ohos-native-strategy.md` §0.1/§0.2 |
| ArkTS 自研桥 | ✅ 时区、剪贴板兜底、相册、通知、深链、AVIF 探测 | `FluxdoBridgePlugin.ets`、`docs/ohos-arkts-bridges.md` |
| 功能验收 | ✅ 35 项（登录页、列表、详情、搜索、深链、分享图、系统分享、另存为、相册、输入法、文本选择、时区、扫码预览、CF 冷启动） | `docs/ohos-acceptance.md` A1–A35 |

### 2.2 代码规模（决定重写成本的底层事实）

| 目录 | 文件 | 非空行 | 说明 |
|---|---:|---:|---|
| `lib/pages` | 103 | 61,503 | 46 个顶层页面（32,506 行）+ 详情/聊天/网络设置/书签子域 |
| `lib/widgets` | 315 | 100,855 | 含 markdown_editor 23,743、post 15,409、content 10,822、topic 10,318、common 10,687 |
| `lib/services` | 209 | 51,875 | 含 network 18,079、CF/cookie 相关约 10k、Discourse 5,978；含未提交 `avif_ohos_codec.dart` 126 行 |
| `lib/providers` | 70 | 14,744 | Riverpod 状态层；131 个 Provider、71 个 Notifier |
| `lib/utils` | 61 | 14,454 | 时间、图片、平台、导航、剪贴板等 |
| `lib/models` | 39 | 8,142 | 含 `topic.dart` 2,487、`user.dart` 687 |
| `lib/l10n` | 8 + 176 ARB | 31,575 | 4 语言、ARB 唯一 key 约 3,046（含 @meta 3,351）、44 个模块 |
| 其他（settings/storage/theme/navigation/plugins/modules/根） | 44 | 9,960 |  |
| **`lib` 合计** | **849** | **293,108** | 非空行；物理行 322,795；数字随活跃开发变化 |
| `packages/fluxdo_render/lib` | 122 | 41,126 | 自研渲染/编辑器/选区（Flutter 专属） |
| 其他一方包（`ai_model_manager`、`common_ui`、`m3e_ui`、`extended_image_lite` 等） | — | 约 27,000 | 纯 Dart/Flutter UI 与业务包；全原生需替换或重写 |
| `repo/test` | 300 | 49,272 | Dart 测试；用例可复用，代码不可 |

> 全原生要处理的是**约 36 万非空行一方 Dart**（物理行约 40 万），而不是只看 `lib` 的 29.3 万行；`packages/` 里的纯 Dart UI/业务包（尤其 `fluxdo_render` 41k）同样作废。

### 2.3 依赖与插件：当前移植的“脆弱层”

- 119 个直接依赖、13 条 `dependency_overrides`、5 个 vendored 包（`file_picker`、`share_plus`、`just_audio_harmonyos`、`flutter_math_fork` 等）、12 个 OHOS 联邦实现包。
- 插件矩阵覆盖 56 个原生/插件类依赖：A 组（上游/社区已有实现）改动量≈0；B 组（需 override/追加）为核心工作量；C 组（无实现）需自写桥或降级；D 组为 OHOS 新增能力（`docs/ohos-plugin-matrix.md`）。
- **系统性风险**：OHOS 官方适配清单只到 Flutter 3.35，CPF 活跃分支到 `br_3.41_dev`；本移植用的是 **3.47.7-ohos-canary1**，没有任何插件 fork 声明支持 3.47.7（`docs/ohos-plugin-matrix.md:12`）。这是“继续 Flutter”路线最大的长期风险，也是“全原生”最真实的收益之一。
- 最大单点：`flutter_inappwebview`（24 个业务文件 + 34 个平台接口文件）只能退到 CPF 6.1.5-ohos，而项目用 6.2.0-beta.3（`ohos-plugin-matrix.md:15`）。

### 2.4 已降级/未完成能力（当前产品事实）

| 能力 | 现状 | 证据 |
|---|---|---|
| cook JS 1:1 预览 | OHOS 关闭，降级 Dart 近似预览；cook bundle 约 567 KB | `ohos_compat.dart:28-30`；`assets/cook/discourse-cook.js` 567,475 B；`ohos-native-strategy.md:47` |
| AVIF | ImageKit 方案已实测失败；**评估期间已出现自编 `libohos_avif.so`（arm64 0.86 MB / x86_64 1.02 MB，工作区未提交），`supportsAvif` 已切 true**；Flutter 侧走 Dart FFI，原生侧仍需 NAPI 包装与真机验证 | `ohos_compat.dart:37-45`；`repo/ohos/entry/libs/*/libohos_avif.so`；`docs/ohos-native-strategy.md` §0.3；`FluxdoBridgePlugin.ets:121-150` |
| 后台保活/后台通知 | 仅前台轮询/本地通知；`KEEP_BACKGROUND_RUNNING` 已声明但未使用 | `ohos_compat.dart:68-70`；`module.json5:67` |
| 应用内更新安装 | HAP 不能静默安装，引导外部/应用市场 | `ohos_compat.dart:72-74` |
| 富文本/图片剪贴板 | 降级纯文本；图片复制降级为链接 | `ohos-arkts-bridges.md` §4、`clipboard_utils.dart` |
| 原生相机扫码 | 已启用 CPF 插件 + 权限；真机识别待验证 | `.cache/shot-qrscan.jpeg`、A31 |
| 推送 | 无系统级推送；仅前台 MessageBus + 本地通知 | `docs/ohos-port-status.md` §5；`module.json5` 无 PushKit 配置 |

### 2.5 可复用资产（全原生不是从零开始，但只占小头）

| 资产 | 可复用程度 | 说明 |
|---|---|---|
| Rust crates：DOH/rhttp/动图解码 | **高** | 3 个 Rust 库 × 2 ABI = 6 个 `.so`；原生侧需加 NAPI 包装（C ABI），逻辑与 crates 可复用 |
| AVIF 原生库 `libohos_avif.so` | **高** | 自编 libavif + dav1d 已产出 arm64/x86_64 `.so`（0.86/1.02 MB，工作区未提交）；原生侧需 NAPI 包装 |
| libavif + dav1d 构建产物 | **高** | `.cache/avif-build` 已有 aarch64/x86_64 静态库（`libdav1d.a`、`libavif_internal.a`），可继续复用于原生 |
| ArkTS 桥（时区/相册/通知/剪贴板/深链/AVIF 探测） | **高** | 约 460 行业务代码，可直接扩展为原生能力层 |
| CF 处理知识（挑战判定、UA、WebView 网络栈、cookie 同步） | **中** | 架构/判据可复用，Dart 代码不可；当前主站请求默认已走 ArkWeb 栈（`webview_adapter_settings_service.dart:45`） |
| Toolchain/签名/权限配置/API 26 配置 | **中** | `tools/env.ps1`、`ohos-sign.ps1`、`module.json5` 可复用；构建脚本围绕 Flutter，需重写；当前是 OpenHarmony 默认证书自签，非 AGC 发布证书 |
| l10n 数据（ARB 唯一 key 约 3,046/含 meta 3,351/4 语言） | **高** | 文案数据可迁移为 resources；slang 代码需重生成 |
| 测试用例/验收清单/截图 | **中** | 作为行为规格与回归基线；Dart 测试代码不可复用 |
| `fluxdo_render` 渲染/编辑器设计 | **低-中** | 节点模型、选区、分块、灰度思想可借鉴；Flutter 代码不可复用，且仍在活跃迭代（10 月仍有表格/虚拟光标/选区提交） |
| NAPI / CMake 基建 | **低** | App 侧当前 0 行 NAPI、0 个 CMakeLists；插件侧有先例（`flutter_inappwebview_ohos` 的 `napi_init.cpp` 真实编译）；**3 个 Rust 库 + AVIF = 4 个原生库 × 2 ABI = 8 个 `.so`** 仍需补包装 |
| 业务知识（Discourse API、cook、onebox、插件、LDC、AI） | **高** | 文档与模型定义是重写规格的主要来源 |

**结论：全原生可以少走“产品/协议/平台配置”的弯路，但 80% 以上的 UI、状态、渲染、编辑器代码需要重写。**

---

## 3. “全原生”的定义与验收基线

### 3.1 目标形态

- **UIAbility + ArkUI 声明式 UI**（状态管理 V2：`@ComponentV2`/`@Local`/`@Param`/`@Event`/`@ObservedV2`/`@Trace`/`@Computed`/`@Monitor`），单 Page + `Navigation`/`NavDestination`。
- **ArkWeb** 负责 CF 挑战、OAuth 登录、需要 Web 内核的富内容（可选）。
- **系统 Kit**：Network Kit/RCP、ArkData（RDB/Preferences）、Media Kit（AVPlayer/AVRecorder）、Image Kit、Camera Kit、Scan Kit、Notification Kit、Push Kit（仅在有服务端转发时可用）、Share Kit、File Kit、PhotoAccessHelper、Pasteboard、Ability Kit（Want/深链）、I18n。
- **NAPI（C++/Rust）**：DOH、rhttp TLS 指纹、AVIF/动图解码等重活。
- **不包含**：Flutter engine、Dart runtime、Flutter 插件、`dart:io`/`dart:ui`。

### 3.2 功能基线（parity 的定义）

- 46 个页面 + 导航入口/面板（底栏可配置、详情/设置子页）对应的核心路径与长尾功能。
- 35 项已验证能力 + 当前已降级能力的“应有体验”（cook 预览、AVIF、后台、富剪贴板、应用内更新策略需产品确认）。
- 关键非功能指标（建议作为迁移验收，而非当前事实）：
  - 冷启动 ≤ 1.5 s（中端机）；
  - 长帖滚动 ≥ 50 fps、无明显卡顿；
  - release HAP 的“≤60 MB”按 **arm64 单 ABI、去 x64 引擎/资源** 口径，当前 114.3 MB 是 x64 fat HAP，两者不可直接比较（见 §7.5 测算）。
  - 崩溃率/ANR 不高于 Flutter 版本；
  - 登录/CF 冷启动 10/10 无需人工干预。

> 注意：上述指标是“如果做全原生”的目标，不是对现有 Flutter 版本的否定；当前 Flutter 版本没有公开的启动/帧率基线，需先测量再比较。

### 3.3 非目标

- 其他平台原生；1:1 像素复刻 Material 3（应改用 HarmonyOS Design 语言，允许视觉重设计）；桌面专属功能（窗口管理、亚克力、动态图标等）；首次发布即 parity。

---

## 4. 能力映射矩阵

> 说明：证据列优先给本机可运行实现；SDK 只证明 API 存在。评级 A/B/C/D 见 §1.3。

| # | 能力域 | 当前实现（证据） | 原生方案 | 评级 | 主要缺口/备注 |
|---:|---|---|---|---|---|
| 1 | 应用框架/导航/页面 | 46 页 + 底栏/详情/设置导航；`lib/navigation/nav_entry_registry.dart` | `UIAbility` + `Navigation`/`NavDestination` + `NavPathStack`；深链 Want | B | 页面数量大，导航/返回/多实例/恢复需重做 |
| 2 | 主题/i18n/设置 | `lib/theme` 501 行、`lib/l10n` 约 3,046 文案 key、`lib/settings` 4,824 行 | ArkUI 主题/资源 `$r`、深浅色、字体缩放；Preferences 持久化 | B | 设计语言需从 Material 3 转 HarmonyOS Design；文案可复用数据 |
| 3 | 状态管理/DI | Riverpod：70 文件/14,744 行，219 个文件引用；131 个 Provider、71 个 Notifier | V2 `@ObservedV2/@Trace` + ViewModel + Repository；手写轻量容器 | B | 无 Riverpod 等价物；Dart 动态/函数式写法需改写为强类型 ArkTS |
| 4 | HTTP/2/TLS | 80 个 dio import、全项目大量调用；cookie jar 223 处 | `@ohos.net.http`（HTTP/2、`enableAutoCookie`、TLS 配置）或 RCP（`@hms.collaboration.rcp`，HTTP/3 假设、CookieRepository） | B | 请求/重试/拦截器/证书/代理/DoH 需重建；无 dio 等价库 |
| 5 | DOH / rhttp（Rust） | `lib/services/network/doh_proxy` 1,257+738 行；`librhttp.so` 已进包 | 保持 Rust crates，新增 NAPI C ABI；或 RCP + Dart DoH 等价实现 | B | NAPI 包装是新工作；TLS 指纹（rhttp）是否仍需取决于 CF 策略 |
| 6 | Cookie / CF / WebView 登录 | `cf_challenge_service.dart` 2,959 行 + 适配器 1,749 + 相关 cookie/refresh/trust 约 10k 行；已验收 A7/A8；现状主站请求默认走 ArkWeb 栈 | ArkWeb + `webview.WebCookieManager.fetchAllCookies()`（@since 23）+ `WebHttpCookie`（含 `isHttpOnly`/`domain`/`path`/`expiresDate`）；`configCookieSync(..., includeHttpOnly)` 回写；RCP `CookieRepository` 注入；必要时 WebView JS fetch 作传输 | **B-（含未验证门禁）** | 旧插件只解析 `fetchCookieSync` 字符串、属性全 null；新 API 可读值与 HttpOnly 属性。若 A/B 失败：网络层退化为 ArkWeb 传输栈，性能/并发需重估，评级降为 C |
| 7 | Discourse API/模型 | `lib/services/discourse` 5,978 行（22 文件）、`models` 8,142 行（39 模型） | 强类型 DTO + 手写/生成 JSON 解析；RCP/HTTP；Repository | B | 模型多、字段可选/嵌套、错误码/限流/CSRF 需逐项对齐 |
| 8 | Discourse HTML 渲染 | `widgets/content` 10,822 行（**17 个 builder 文件，含 6 个 onebox builder**）、`fluxdo_render` 41,126 行、post/topic/detail 约 42k 行 | 自研 HTML→ArkUI 节点渲染器（AST + chunk + 虚拟化 + 选区）；或 Web 组件逐帖渲染；或混合 | **C** | `RichText` 底层是 Web、不维护、List 内复用卡顿且不可定制；`Web` 方案还受 `FIT_CONTENT`/7680px/不能切 mode 限制；现有 Flutter 渲染器重构本身预估 4–6 个月 |
| 9 | Markdown 编辑器/富文本 | `widgets/markdown_editor` 23,743 行（rich_composer 4,767 行）、`fluxdo_render/editor` 22,999 行 | ArkUI `RichEditor` + 自定义工具栏/Markdown 编解码/图片/投票/表格/表情/贴纸/语音；必要时 Web 编辑器 | **C** | RichEditor **无编程式 undo()/redo() API，但组件内置撤销/重做（`undoStyle` @since 20）**；`fromHtml/toHtml` 仅少量标签、无表格、默认粘贴纯文本、StyledString 与 IME 互斥；现有编辑器功能远超系统组件 |
| 10 | 长列表/虚拟化 | 各页 `Sliver`/`CustomScrollView`；`fluxdo_render` chunk；116 处 ListView/Sliver、67 处 isolate | `List`/`LazyForEach`/`Repeat` + `@Reusable` + 分页/预取 | B | ArkUI 列表能力成熟，但“长帖内节点虚拟化 + 跨节点选区”需专门设计 |
| 11 | 图片/缓存/动图 | `cached_image`、`lazy_image`、`sticker_thumbnail_provider`、Rust `libnative_animated_image_codec.so` | `Image`（支持 png/jpg/bmp/svg/webp/gif/heif，**GIF/WebP 动图原生播放**，不支持 APNG/SVGA）+ 自建磁盘/内存缓存；或复用 Rust 解码 NAPI | B | 图片缓存/预取/渐进/占位/失败重试需重写；系统 Image 无公共磁盘缓存 API；动图 disposal 行为需回归 |
| 12 | AVIF | `avif_image_provider.dart`、`avif_fast_bridge.dart`；自编 `libohos_avif.so` 已产出（未提交），`supportsAvif=true` | 复用 `libohos_avif.so`，新增 NAPI 包装；或直接不支持 AVIF | **B-** | ImageKit 方案已证伪（只解容器头）；`.so` 已有但未提交/未真机验证；原生侧不能 `DynamicLibrary.open`，必须 NAPI；风险中等 |
| 13 | 视频/音频/录音 | `video_player_harmonyos`（AVPlayer）、`just_audio_harmonyos`、`record_ohos` 已编译；验收分享/媒体 | `AVPlayer`/`AVRecorder` + `XComponent`/`AVSession`；后台播放用长时任务 | A | 已有插件级可运行证据；全原生可做得更直接；后台播放/PiP 未实现 |
| 14 | 相机/扫码 | `mobile_scanner` OHOS（CameraKit + ScanKit）；A31 预览+权限 | Camera Kit 预览 + Scan Kit `startScan`/`customScan` | A | 真机识别待验证；权限/降级逻辑已有 |
| 15 | 通知/推送/后台 | `flutter_local_notifications` fork；仅前台；`backgroundTaskManager` 未接；`KEEP_BACKGROUND_RUNNING` 已声明未用 | Notification Kit + reminderAgent + `backgroundTaskManager`（长时任务）；Push Kit 仅在“自建服务端转发”时可用 | B | **远端推送不是开箱即得**：linux.do 不会向 HMS 推送，需自建转发服务（接收 Discourse 通知 → 调 HMS 推送）；本地通知/长时任务可直接做 |
| 16 | 分享/导出/相册/文件 | `share_plus`（Share Kit）、`file_picker`、`saver_gallery`、`image_picker`；A20–A23 | Share Kit `ShareController`、File Kit `picker`、PhotoAccessHelper、`fileIo` | A | 已有可运行插件；富文本/多文件/打印等组合需回归 |
| 17 | 剪贴板 | 纯文本兜底；富文本/图片降级 | `pasteboard` 支持文本/HTML/图片/URI；可逆袭当前降级 | B | 需要统一 `RichClipboard` 门面与各调用点回归 |
| 18 | 深链/时区/权限 | `app_links`、ArkTS 时区桥、module.json5 skills；A13/A26；App Linking 域名校验 TODO | Want + `skills.uris`、`i18n.System.getSystemTimeZone()`、`abilityAccessCtrl` | A | 冷启动/热启动、权限拒绝/永久拒绝的 UX 需重走；https 深链需 AGC 校验 |
| 19 | 数据库/缓存/迁移 | Hive 3 个 DAO（Bookmark/Chat/ExportHistory）+ AppDatabase 封装；SharedPreferences 219 处调用/74 文件；自定义 cookie jar；`lib/storage` 633 行；迁移 v2–v9 | `relationalStore`（支持加密/备份/事务）+ Preferences（加密等级）+ HUKS/asset 存 token | B | Hive→RDB 表设计、迁移脚本、旧数据兼容是隐蔽大头；登录 cookie/secure storage 迁移困难 |
| 20 | 搜索/过滤/高亮 | `search_page` 1,348 行、`highlighter_service` 396 行 | RegExp/字符串匹配 + `Text`/RichEditor 高亮；服务端搜索不变 | B | 纯逻辑可移植；性能/长结果/高亮分段需重写 |
| 21 | AI/加密/LDC/Notion/插件/长尾 | `widgets/ai` 2,570、`widgets/crypto` 1,426、`modules/ldc_reward` 889、`notion` 约 2.4k、插件 377 行 | HTTP AI 调用、`@ohos.security.cryptoFramework`/HUKS、Notion API、插件注册表 | B | 业务逻辑分散，长尾功能多；可考虑首版裁剪 |
| 22 | 分享图/长图 | `widgets/share` 1,971 行、`screenshot_utils.dart`（RepaintBoundary，分块拼接） | `UIContext.getComponentSnapshot`/`createFromBuilder` 生成 PixelMap → 编码/分享；顶层 `componentSnapshot.get` 已 deprecated since 18 | B | API 齐全（`@ohos.arkui.componentSnapshot.d.ts`）；长图/离屏渲染/字体一致性需 PoC；Web 参与时长图受 7680px 限制 |
| 23 | 多设备/窗口/无障碍 | `adaptive_scaffold` + `adaptive_navigation` 约 1,291 行（`widgets/layout` 全目录 2,846 行）；`module.json5` 仅 phone/tablet，`foldStatus` 零命中 | ArkUI 断点/`GridRow`/折叠屏/2in1 窗口；无障碍属性 | B | 手机优先；折叠屏/2in1 是额外工作量，不建议首版全覆盖 |
| 24 | 测试/DFX/CI | 300 Dart 测试/49k 行；hilog 自定义 domain 可观测性存疑 | Hypium 单元/Instrument 测试、UiTest、hilog、crash/freeze/内存分析 | B | Dart 测试不可复用；需重建测试金字塔与 CI/签名流水线；原生可观测性需从零建 |

**评级汇总：A = 4（13/14/16/18），B = 18（含 CF/AVIF 两个 B-），C = 3（8/9 + cook JS）**。  
> 定义补充：**B- = B 级路径存在、但含未验证门禁**（CF 需设备 A/B；AVIF 需 NAPI/真机）；门禁失败则降为 C。  
> 注：cook JS 单列为 C（见 R4），表格中未单列，避免与编辑器重复；CF 因 `fetchAllCookies`/`WebHttpCookie`（@since 23）评为 B-；AVIF 因 `libohos_avif.so` 已产出而评为 B-。  
> 结论：**绝大多数能力有明确原生路径（B），真正需要 PoC/自研的是 3 个点（HTML 渲染、编辑器、cook JS）；没有 D 级“必须放弃”的能力**（桌面专属功能、无服务端转发的远端推送除外）。

---

## 5. 目标架构建议（如果做全原生）

### 5.1 分层与模块

```
entry/ (UIAbility, 路由, 深链, 权限)
├── common/        设计 token、资源、基础组件、工具
├── core/          网络(RCP/HTTP)、Cookie/CF、存储(RDB/Prefs)、安全(HUKS)、日志、TaskPool
├── data/          DiscourseApi、DTO/Model、Repository、缓存
├── domain/        Auth/Topic/Post/Chat/Notification/Search/Upload 服务
├── feature/       topics、topic_detail、editor、chat、profile、settings、notifications、search、media
├── render/        HTML AST → ArkUI 节点、chunk、虚拟化、选区、代码高亮、onebox/poll/iframe
├── editor/        RichEditor 封装、Markdown 编解码、上传、投票、表格、表情/贴纸
└── native/        NAPI：DOH、rhttp、AVIF、动图
```

### 5.2 关键架构决策

| 决策 | 推荐 | 理由 |
|---|---|---|
| 状态管理 | **V2**（`@ObservedV2`/`@Trace` + `@ComponentV2`/`@Param`/`@Event`） | 新项目无 V1 包袱；V2 的 `@Computed`/`@Monitor` 更贴近 Riverpod 派生状态；避免 V1/V2 混用 |
| 分层 | **MVVM + Repository** | View 不直接访问 Model；ViewModel 持有 UI 状态；Repository 负责 API/DB/缓存；与 hmos `arkui-mvvm-pattern` 一致 |
| 依赖注入 | 手写轻量容器/Context 传递 | 无 Riverpod 等价物；避免引入重型 DI 框架；Repository 单例 + 构造注入 |
| 导航 | **单 Page + Navigation/NavDestination + NavPathStack** | 支持深链、返回栈、分栏（平板）；避免多 Page 路由状态割裂 |
| HTML 渲染 | **首版 Web 组件/混合，二期自研 ArkUI 节点渲染器** | 自研是 4–6 个月级投入；先用 Web 验证产品闭环，再按节点灰度替换；与现有 `fluxdo_render` 的“节点级灰度”思想一致 |
| 编辑器 | **RichEditor + Markdown 编解码层**；复杂块（表格/投票）用自定义面板 | 系统组件提供 IME/图片/粘贴回调；Markdown/预览/上传/表格仍需自研；必要时用 Web 编辑器兜底 |
| 网络 | **RCP + CookieRepository 为主，ArkWeb 负责 CF，rhttp NAPI 作为 TLS 指纹后备** | RCP 原生支持 httpOnly cookie、HTTP/3 假设、TLS 1.2/1.3、自定义校验；ArkWeb 负责挑战；rhttp 保留指纹能力 |
| 存储 | **RDB（加密）+ Preferences（加密等级）+ HUKS/asset** | Hive 的 KV/草稿/缓存映射为表；token 进 HUKS/asset；cookie 进 RCP CookieRepository 持久化 |
| 原生库 | **NAPI 包装 Rust/C** | 现有 `.so` 逻辑可复用；NAPI 是 ArkTS 调用原生库的标准路径；避免 JNI/FFI 假设 |

### 5.3 数据流

```
View (ArkUI) → ViewModel (V2 state) → Repository → RCP/HTTP + RDB/Preferences
                                   ↘ RenderService (HTML AST → 节点)
                                   ↘ UploadService (文件/图片 → 压缩 → 上传)
                                   ↘ CfSolver (ArkWeb 挑战 → cookie → RCP)
```

规则：
- View 只读 ViewModel，不直接 import Model/Repository；
- Repository 返回领域模型，不返回原始 JSON Map；
- 渲染器只依赖规范化 AST，不依赖网络；
- 编辑器与渲染器共享同一 Node 模型，保证“所见即所得”与预览一致；
- 所有跨线程重活（解析/解码/压缩）走 `TaskPool`/Worker，不在 UI 线程做同步大计算。

### 5.4 存储 schema 迁移（草案）

| 旧（Flutter） | 新（原生） | 迁移策略 |
|---|---|---|
| Hive `draft`/`bookmark`/`chat_cache`/`export_history` box | RDB 表 `drafts`/`bookmarks`/`chat_messages`/`export_history` | 优先做一次性导入器；Hive 二进制解析复杂，可降级为“清缓存 + 保留草稿导出” |
| SharedPreferences（219 调用/74 文件） | Preferences（按 area/加密等级） | key 映射 + 默认值；需处理类型差异 |
| cookie jar / WebView cookie | RCP CookieRepository（httpOnly 持久化） | 原生侧重新登录最稳；如需无缝，需导出/导入 cookie（HttpOnly 可读性待验证） |
| flutter_secure_storage（token） | HUKS/asset store | 无法直接解密旧数据 → 强制重新登录 |
| Hive 收藏/历史缓存 | RDB 缓存表 | 可在线重建，允许丢弃 |
| 下载文件 | 应用沙箱/文件 URI | 路径/权限/分享 URI 需重写 |

> **重要**：同 bundle（`com.fluxdo.app`）升级意味着用户数据必须迁移；登录态/cookie 的迁移是产品级风险，不是纯技术细节（R8）。

---

## 6. 风险登记与验证设计

### 6.1 风险总表

| # | 风险 | 现有证据 | 失效模式 | 等级 |
|---:|---|---|---|---|
| R1 | CF/HttpOnly/TLS 网络栈 | 旧插件只用 `fetchCookieSync` 字符串、属性全 null（`MyCookieManager.ets:169-195`）；但 API 23+ 有 `fetchAllCookies()` + `WebHttpCookie`（含 `isHttpOnly`），见 `@ohos.web.webview.d.ts:1492,8093-8157`；现有日志有 2 行 `hasCfClearance=false`（`.cache/hilog-i7.txt:483` 等），仅证明当时 store 无 clearance | 若 `fetchAllCookies` 也取不到值，则只能“主站全走 WebView 栈”，性能/并发/超时受桥限制；UA/指纹不一致导致 CF 循环挑战 | 中高 |
| R2 | Discourse HTML 保真渲染 | 17 个 builder 文件（含 6 个 onebox builder）+ 41k 行渲染/选区；`RichText` 是 Web 内核、List 内卡顿、不可定制；`Web` 的 `FIT_CONTENT`/7680px 受限；渲染器重构本身 4–6 个月 | 长帖卡顿/选区错乱/onebox/poll/iframe/代码/公式/图片灯箱缺失；用户可感知的体验倒退 | **高** |
| R3 | 富文本编辑器 | 23.7k 行编辑器 + 23k 行 editor 内核；RichEditor 无编程式 undo()/redo()（但内置 `undoStyle`）、`fromHtml/toHtml` 仅少量标签、无表格、默认纯文本粘贴、StyledString 与 IME 互斥 | 发帖/编辑/投票/表格/图片/语音/草稿体验大幅缩水 | **高** |
| R4 | cook JS 1:1 预览 | `flutter_js` 无 OHOS；`OhosCompat.supportsCookJs=false`；cook bundle 约 567 KB；QuickJS 可 NAPI 嵌入但未验证 | 编辑器预览与线上渲染不一致；可降级但不阻塞 | 中高 |
| R5 | AVIF/动图 | ImageKit 实测不能解 AVIF 像素；自编 `libohos_avif.so` 已产出（未提交） | AVIF 图片裂图/占位；动图 disposal 差异闪烁；NAPI 未接 | 中 |
| R6 | 音视频/后台播放 | AVPlayer/AVRecorder 插件已编译；AVSession/长时任务可用 | 后台播放/画中画/音频焦点/断点续播差异 | 中 |
| R7 | 推送/后台保活 | Push Kit 需 AGC 开通服务/分类权益 + 发布证书；**linux.do 不会直接向 HMS 推送，需自建转发服务**；本地通知/长时任务可用 | 无服务端转发则远端推送不可用；后台消息延迟/被杀 | 中高 |
| R8 | 数据/登录态迁移 | Hive 3 个 DAO + AppDatabase/Preferences 219 调用/74 文件/cookie/secure storage 分散；Flutter 与原生存储格式不同 | 升级后丢草稿/收藏/登录态；用户投诉/差评 | **高** |
| R9 | 长列表/大 HTML 性能 | Flutter 现有渲染器有卡顿/选区崩溃历史；ArkUI 无同等自定义渲染器实践；现有 `ui.Paragraph` 缓存层无等价物 | 滚动掉帧/内存峰值/长帖 OOM | 中高 |
| R10 | 双代码库/上游分叉 | 上游 9 个月 84 个版本、v0.2.29 与移植同日；46 页功能面；OHOS 全原生独立 | 每个上游功能双写；版本长期落后；团队被拖住 | **高** |
| R11 | 发布/合规/签名 | 当前是 OpenHarmony 默认证书自签；AGC 发布证书/profile 未做；Push/App Linking 依赖 AGC；HAP 不能静默安装；**第三方客户端 + CF 绕过/UA 归一 + 站点 ToS/平台审核政策未评估** | 上架延迟；推送/深链不可用；更新链路断裂；合规/ToS 风险 | 中高 |
| R12 | 多设备/折叠屏/2in1 | `module.json5` 仅 phone/tablet；`foldStatus` 零命中；两个 adaptive 文件约 1,291 行（layout 目录 2,846 行） | 平板/折叠屏体验差；额外 3–6 人月 | 中低 |
| R13 | 团队/生态/可观测性 | 现有团队 Flutter/Dart+Rust；ArkTS 仅约 460 行桥经验、从未本地编译（仅 TS 语法解析）；hilog 自定义 domain 可观测性存疑 | 学习曲线/招聘/返工；首年产能下降；线上问题难定位 | 中高 |

### 6.2 Top 5 风险详解与最小验证

#### R1：CF / HttpOnly cookie / TLS 指纹（可解，但仍需设备 A/B）

**文档矛盾的原因**：
- `docs/ohos-port-status.md:33`：说“ArkWeb cookie store 仍读不到 HttpOnly 的 `cf_clearance`”。
- `docs/ohos-cf-fix.md:151-161,419-421`：说 `fetchCookieSync` 返回“all cookie values”，理论上含 HttpOnly。
- 两者其实在说不同的 API：`fetchCookieSync` 只返回 **Cookie 头字符串**，SDK 明确“a specific cookie value cannot be obtained separately”，且插件 `MyCookieManager.ets:169-195` 把 domain/path/HttpOnly/expires 全置 null——用它当然读不到属性。
- **API 23+ 提供了正解**：`WebCookieManager.fetchAllCookies(incognito)` 返回 `WebHttpCookie[]`，含 `name`/`value`/`domain`/`path`/`expiresDate`/`isHttpOnly`/`isSecure`/`isSessionCookie`/`samesitePolicy`（`@ohos.web.webview.d.ts:1492, 8093-8157`）；写回可用 `configCookieSync(..., includeHttpOnly)`（`:1247`）。
- 但“字段存在”不等于“返回实体”：现有日志（`hilog-i7.txt:483` 等）只证明当时 store 里没有 `cf_clearance`，不能证明内核过滤；必须设备 A/B。

**验证设计（S0 PoC）**：
1. ArkWeb 加载 `https://linux.do/`，让 Turnstile 真正执行（参考 `ohos-cf-fix.md` 第 5 轮修复，关闭 `useOnNavigationResponse`/`shouldOverride`）。
2. 过盾后调用 `fetchAllCookies(false)`，断言存在 `name === 'cf_clearance'` 且 `isHttpOnly === true`；同时记录 `[CfChallenge][OHOS] clearance 归因`。
3. 把 `WebHttpCookie` 转成 RCP `ResponseCookie` 注入 `CookieRepository`（保留 `httpOnly/domain/path/expires`），发 `GET https://linux.do/latest.json`，期望 200。
4. 若 200：原生 HTTP 栈可行，记录冷启动耗时/成功率（10 次）。
5. 若 `fetchAllCookies` 无 `cf_clearance` 或注入后 403：退回“所有主站请求走 ArkWeb JS fetch”（现有移植已验证可行），记录性能/并发/缓存代价。
6. 若仍失败：尝试 rhttp（Rust TLS 指纹）NAPI，或接受“浏览器栈为主”的架构。

**失败判据**：10 次冷启动中 >2 次需要人工点验证，或主站 API 延迟 >3 s，或 WebView 传输导致图片/分页/搜索明显退化。  
**降级路径**：若 A/B 失败，CF 评级降为 C，网络层退化为“主站全走 ArkWeb JS fetch”，连接复用/并发/超时/上传需重估；这会影响启动/吞吐指标，但不等于项目不可行（现有 Flutter 版已验证该路径可用）。

#### R2：HTML 渲染

**证据**：`lib/widgets/content/discourse_html_content` 17 个 builder 文件（含 6 个 onebox builder）；`fluxdo_render` 30+ 节点、4–6 个月重构计划；`RichText` 底层 Web、List 内复用卡顿、不维护（`ts-basic-components-richtext.md`）；`Web` 的 `layoutMode(FIT_CONTENT)` 还受“不能切 mode / 高度 >7680px 需 `SYNC_RENDER` / 不支持瀑布流”限制（`ets/component/web.d.ts:7332-7342`）。

**方案对比**：
| 方案 | 成本 | 体验 | 风险 |
|---|---|---|---|
| 全 WebView 渲染 | 低 | 滚动/选区/字体与原生不一致，长帖重（7680px 限制） | 中 |
| ArkUI 自研节点渲染器 | 高（15–25 PM） | 最好，可虚拟化/选区/交互 | 高 |
| 混合：静态节点 ArkUI + poll/iframe/video 原生/Web 嵌入 | 中高 | 接近最好 | 中高 |

**PoC 验收**：3 个真实话题（长帖、投票、代码+公式+onebox），滚动 ≥50 fps，文本可跨节点选择，图片懒加载，链接/mention 可点，折叠块/引用/表格正确。

#### R3：编辑器

**证据**：`markdown_editor` 23,743 行；`rich_composer_editor.dart` 4,767 行；功能含表情/贴纸/图片上传/投票/语音/表格/块选择/预览/草稿；RichEditor 文档明确默认粘贴仅纯文本、无表格、无 HTML/Markdown；`fromHtml/toHtml` 仅支持 p/span/img/a/b/i/em/u/del/sup/sub 等少量标签，且 StyledString 模式与 IME 回调互斥；**控制器无编程式 undo()/redo()，但组件内置撤销/重做（`undoStyle` @since 20），需验证跨 span/图片/表格的撤销粒度与能否用 `editMenuOptions` 暴露按钮。**

**修正（评审后）**：早前把“无编程式 API”写成“组件无撤销/重做”是错的；SDK `rich_editor.d.ts:126-147,3415-3431` 明确有 `UndoStyle`/`undoStyle`。编辑器风险仍高，但风险点改为：Markdown/HTML 往返、表格、图片粘贴、IME 组合态、撤销粒度与可编程性。

**PoC 验收**：中文 IME 输入、加粗/引用/代码/列表/链接、插入图片（相册/拍照/粘贴）、投票、表格、撤销/重做、Markdown 往返、草稿自动保存、预览与线上渲染一致。  
**失败判据**：撤销粒度跨 span 丢失 / 图片粘贴退化为文件名 / Markdown 往返丢 ≥1 类语法 / IME 组合态光标错位。

#### R4：cook JS

**方案**：NAPI 嵌入 QuickJS（`quickjs.c` + wrapper，约 1 MB）或 ArkWeb JS；或首版降级为“Dart 等价 Markdown 预览”的 ArkTS 版本。**建议首版不做 1:1**，以编辑器预览一致性为验收，不阻塞主流程。

#### R5：AVIF

**证据**：ImageKit 只解容器头，`createPixelMap` 三种姿势全失败；系统格式清单无 AVIF（`@ohos.multimedia.image.d.ts:77/81/4173`）；但评估期间已产出自编 `libohos_avif.so`（arm64 0.86 MB / x86_64 1.02 MB，工作区未提交），Flutter 侧 `supportsAvif` 已切 true。

**方案**：复用 `libohos_avif.so`，NAPI 暴露 `decode(bytes)->RGBA`；或首版不支持 AVIF（图片占位/回退）。成本约 1–3 PM（库已存在，主要工作是把 Dart FFI 包装换成 NAPI + 真机验证）。

### 6.3 其他风险要点

- **R7 远端推送**：这是最容易被低估的一项。linux.do 是第三方 Discourse 站点，不会向 HMS Push 推送；要用 Push Kit，必须自建一个转发服务（登录用户订阅 Discourse 通知 → 服务端调 HMS 推送），并承担 AGC 账号/权益/审核/隐私成本。**它不是“接个 SDK”那么简单，也不应作为 B1 的默认项。** 本地通知 + 后台长时任务不依赖 AGC，可以优先做。
- **R8 数据迁移**：同 bundle 升级时，Flutter 的 Hive/Preferences/cookie/secure storage 与原生不兼容；最稳妥是“原生首版强制重新登录 + 草稿导出/导入”，并把“数据不丢”作为产品决策而非技术默认。Hive 是纯 Dart 私有格式，原生不能原地读。
- **R10 双代码库**：上游 9 个月 84 个版本、日期与移植同日发布 v0.2.29；如果其他平台继续 Flutter，OHOS 全原生就是永久分叉；上游每个功能（AI、聊天、编辑器、渲染器）都要双写。**这不是一次性成本，是 1.5–3 人月/月（18–36 人月/年）的持续成本。**
- **R11 发布**：当前签名是 OpenHarmony 默认证书链自签，不是 AGC 发布证书；Push Kit、App Linking（https 深链）都依赖 AGC 域名/证书校验；HAP 不能静默更新。全原生不会自动解决这些，反而在“上架”上增加一轮 AGC 接入。
- **R13 团队/可观测性**：现有 ArkTS 只有约 460 行桥经验，且从未本地编译（只做 TS 语法解析）；ArkTS 限制（无 `any`/`unknown`、无结构化类型、无 `delete`/原型/反射、`arkts-no-spread` 等）会让 Dart 的动态/函数式写法大量返工；hilog 自定义 domain 的可观测性在文档与实测之间存在冲突，原生上线前要先把日志/崩溃采集跑通。

---

## 7. 工作量与成本模型

### 7.1 方法

- **自下而上（主口径）**：按 12 个工作包（WP）估算，每包给低/中/高三点；依据 = 代码规模、页面/节点数量、平台差异、可复用程度、现有团队经验。
- **自上而下（下限校验）**：一方 Dart 约 36 万非空行（物理行约 40 万），扣除生成 l10n/样板后有效重写规模约 30 万非空行；按 2.5k–4k 有效行/人月 → 75–120 人月开发；叠加 40–60% 设计/QA/PM/学习/发布 → 105–192 人月。该结果与自下而上的 118–200 存在约 10–15% 差异，主要来自 W4（渲染器/选区）与 W5（编辑器）的非线性成本；**预算以自下而上为准，自上而下仅作下限**。
- **与“30–45 人月”乐观值的关系**：该值只含纯开发、假设 AI 高杠杆、不含设计/QA/数据迁移，且其自身分域估算相加已约 44–76；若按同口径补上 40–60% 与迁移，约 60–90，仍低于本报告，因为它假设“无 parity 压力 + 渲染/编辑器用 Web 降级”。**本报告不采用它作为预算，只把它作为乐观下限参照；S2-lite 的定义见 §7.3。**
- **不含**：招聘、设备、应用市场/AGC 行政成本、长期维护。
- **精度**：±40%，用于量级判断与预算区间，不用于报价。

### 7.2 工作包估算（开发本体，人月）

| WP | 内容 | 低 | 中 | 高 | 依据 |
|---|---:|---:|---:|---:|---|
| W1 | 基础设施：工程/架构/导航/主题/i18n/设置框架 | 6 | 8 | 10 | 46 页导航、约 3,046 文案 key、设计语言切换 |
| W2 | 网络/认证/CF/Cookie/安全 | 10 | 13 | 16 | CF 约 10k 行、cookie/适配器/拦截器、RCP/Rust 集成 |
| W3 | Discourse API/模型/缓存/同步 | 7 | 9 | 11 | 22 服务文件、39 模型、MessageBus/预加载/Offline |
| W4 | HTML 渲染（AST/节点/选区/虚拟化/onebox/poll） | 15 | 20 | 25 | 41k 行渲染器 + 30+ 节点；现有重构 4–6 个月 |
| W5 | 编辑器/发帖/草稿/上传/投票/表格 | 12 | 16 | 20 | 23.7k 行编辑器 + 23k 行 editor 内核 |
| W6 | 其余页面/组件/交互（46 页） | 18 | 24 | 30 | 61.5k 页面 + 100.9k 组件（扣除 W4/W5） |
| W7 | 媒体：图片/动图/AVIF/音视频/相机/扫码 | 5 | 7 | 9 | 插件已有证据；AVIF/缓存/后台播放额外 |
| W8 | 通知/推送/后台/聊天/私信 | 5 | 7 | 9 | 聊天 8k 行、通知/长时任务；远端推送不含自建服务 |
| W9 | 分享/导出/相册/文件/分享图 | 4 | 5 | 7 | 插件已有；长图/离屏渲染 |
| W10 | 存储/迁移/登录态 | 4 | 5 | 7 | Hive→RDB、cookie/secure storage 迁移 |
| W11 | AI/加密/LDC/Notion/插件/长尾 | 4 | 6 | 8 | 功能分散；可裁剪 |
| W12 | 测试/DFX/CI/发布/合规 | 8 | 10 | 13 | 300 测试重建、Hypium、签名/上架 |
| **开发本体** |  | **98** | **130** | **165** |  |
| 固定增量 | 设计 4–6 + 学习 4–8 + PM 10%（9.8–16.5）+ 发布 2–3 | **+19.8** | **+26.5** | **+33.5** | 逐项相加，不再“凑数” |
| **总计（含设计/QA/PM）** |  | **117.8** | **156.5** | **198.5** | 取整 **约 118–200**，中位约 157 |

> 说明：W12 已含 QA；固定增量已逐项列出；总计 = 开发本体 + 固定增量。按非空行口径，物理行重算会高约 10%，不改变量级与结论。

### 7.3 场景与日历时间

| 场景 | 范围 | 人月（含设计/QA/PM） | 4 人团队 | 8 人团队 |
|---|---|---:|---:|---:|
| **S0 PoC** | 原生壳 + 登录/CF + 列表 + 详情渲染 + 图片 + 简单回复（+ 编辑器最小竖切，见 §9.2） | 2–3 | 4–5 周 | 4 周 |
| **S1 核心版** | 登录/浏览/详情/回复/搜索/通知/个人/设置（约 12–18 页） | 40–65 | 10–16 个月 | 6–10 个月 |
| **S2-lite 精简版** | 核心阅读/发帖/聊天；渲染用 Web/混合、编辑器简化；砍 AVIF/远端推送/LDC/Notion/2in1/长尾；**不是 46 页 parity** | 60–90 | 15–22 个月 | 9–14 个月 |
| **S2 完整版** | 46 页全功能 + 编辑器 + 聊天/AI/媒体/插件/长尾 | 118–200 | 2.5–4.5 年 | 1.5–2.5 年 |
| **S3 完整版+原生增强** | S2 + 实况窗/服务卡/多设备/账号（推送需自建转发） | S2 + 15–25% | +4–10 个月 | +3–6 个月 |

> 并行度假设：4 人时 1 设计 + 1 QA 共享；8 人时 1 设计 + 2 QA；模块间依赖（渲染器/编辑器/网络）限制并行，日历时间非线性缩放。AI 辅助编码可把开发本体降低约 20–30%（**假设，无公开基准**），但平台学习、真机回归、渲染/编辑器调优不会同比例下降，故总区间不按同比例下调。

### 7.4 与“维持 Flutter / 混合”对比（从今天起的增量成本）

| 项 | A 现状 Flutter | B 混合渐进 | C 全原生 |
|---|---|---|---|
| 初次投入 | 0（已完成） | 10–20 人月 | 118–200 人月（精简 60–90） |
| 年度维护 | 6–18 人月/年（0.5–1.5/月） | 12–30 人月/年（1.0–2.5/月） | 18–36 人月/年（1.5–3/月） |
| 3 年累计维护 | 18–54 人月 | 36–90 人月 | 54–108 人月 |
| **3 年总成本（增量）** | **18–54 人月** | **46–110 人月** | **172–308 人月（精简 114–198）** |
| 平台能力 | 受 Flutter 插件/引擎限制 | 大部分系统能力可用 ArkTS 模块补齐 | 完整原生；远端推送仍需自建服务 |
| 体积/启动 | 114.3 MB（x64 fat）/ 未测 | 同 A（engine 仍在）/ 未测 | 测算 43–47 MB（§7.5）/ 启动待测 |
| 跨平台 | Android/iOS/Windows/macOS/Linux 共享 | 同 A | OHOS 独立；其他平台另维护 |
| 上游节奏 | 9 个月 84 版，需持续跟进 | 同 A + ArkTS 层 | 每个功能双写，永久分叉 |

> 结论：**C 在成本上几乎不可能低于 A/B**（172–308 vs 18–110）。选 C 只能是**战略投入**，不是省钱；只有当 A 基线不可持续（Flutter OHOS 分支停更/插件生态断裂）或 OHOS 成为唯一主战场时，C 才在“必须做”的意义上成立。

### 7.5 体积测算（C 相对 A/B 的增量收益之一）

当前 release HAP 解包 113.5 MB（189 项）：

| 组成 | 当前 x64 fat HAP | 全原生 arm64 估算 | 说明 |
|---|---:|---:|---|
| Flutter engine（x64 libapp + libflutter） | 55.68 MB | 0 | 全原生移除；系统提供 ArkUI 运行时 |
| MiSansVF.ttf | 19.16 MB | 19.16 MB | 不子集化则保留；这是 30–50 MB 目标的关键变量 |
| 其他字体 | ~1.5 MB | ~1.5 MB | KaTeX/Material 等 |
| x64 原生库 | 14.45 MB | 0 | 单 ABI |
| arm64 原生库 | 13.73 MB | ~13.7 MB | 含 DOH/rhttp/动图；AVIF +0.86（未进当前 HAP） |
| 资源/代码/assets/其他 | ~8.9 MB | ~8–12 MB | 估算 |
| **合计** | **113.5 MB** | **约 43–47 MB** | 未做字体子集化/资源裁剪 |

> 结论：“30–50 MB”只有在 **字体子集化 + 资源裁剪 + 单 ABI** 后才成立；当前无全原生构建，以上为测算假设，不是实测。**冷启动/内存同样没有基线，必须先测 A 再谈 C 的收益。**

### 7.6 收益侧假设（避免只看成本）

| 潜在收益 | 现状 | 全原生可能带来 | 可测性 |
|---|---|---|---|
| 体积/启动/内存 | 114.3 MB x64 fat；启动/内存未测 | 43–47 MB 测算；启动更快 | 可测，但需先测 A 基线 + S0 |
| 插件生态风险 | 13 override/5 vendored/3.35 vs 3.47 | 移除 56 插件类依赖与 Flutter OHOS fork | 可统计每版升级耗时 |
| 系统集成 | 后台/通知/分享/扫码已部分可用 | 实况窗/服务卡/系统搜索/账号/无障碍 | 部分 B 也能做，非 C 独占 |
| 原生 UI/多设备 | Flutter 自适应 | ArkUI 原生断点/折叠屏/2in1 | 可做用户测试，但无留存数据 |
| 用户/留存/评分 | 无数据 | 无法承诺 | 需 A/B 测试，不能作为立项依据 |
| 合规/ToS | 第三方客户端 + CF 绕过/UA 归一 | 不改善，可能更显眼 | 法务评估；见 R11 |

> 结论：C 的增量收益主要是**体积/启动/引擎移除 + 插件生态风险消除**；其中体积/启动尚未测量，插件风险可用 B 逐步替换缓解。**在收益未量化前，不应把“原生体验”作为选 C 的主要理由。**


---

## 8. 方案对比

### 8.1 四个方案

- **A 维持现状（Flutter OHOS 移植）**：继续修补插件/CF/能力降级；成本最低，平台能力受限。
- **B 混合渐进（推荐默认）**：Flutter UI 保持；ArkTS 能力层继续加深（后台/本地通知/分享/扫码/剪贴板/深链/系统入口）；必要时用 `OhosView` 嵌入少量原生页面。反向的“原生壳 + FlutterPage 内容”也可行，但 Flutter engine 仍在、体积/启动收益有限，复杂度更高，不建议作为首选。远端推送需自建转发服务，单独评估。
- **C 全原生重写**：ArkTS/ArkUI + 系统 Kit + NAPI；OHOS 独立代码库；一次性投入 118–200 人月（精简版 60–90）。
- **C' Rust core + 原生 UI**：把 API/模型/缓存/渲染解析等核心逻辑抽到 Rust，ArkTS 只做 UI；理论上可与桌面共享核心，但需要先重构 Flutter 侧，投入更大、周期更长，适合作为长期架构方向而非首版方案。

### 8.2 加权评分（示例，权重可调）

| 方案 | 一次性成本 25% | 时间 20% | 风险 15% | 维护/上游 15% | 性能/体积 10% | 平台能力 10% | 团队/生态 5% | 加权 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A 现状 | 5 | 5 | 3 | 2.5 | 2 | 3 | 5 | **3.83** |
| B 混合 | 3.5 | 4 | 4 | 2.5 | 3 | 4 | 4 | **3.55** |
| C 全原生 | 1 | 1 | 1.5 | 2 | 5 | 5 | 2 | **2.08** |
| C' Rust core+UI | 1.5 | 1.5 | 2 | 3 | 4.5 | 4.5 | 2.5 | **2.45** |

> 读法：**A 的加权分最高**（3.83），B 次之（3.55），C 最低；**B 不是分数胜出，而是战略选择**——用 +10–20 人月换平台能力/风险对冲。B 是 A 的超集，维护分不应高于 A，故给 2.5（与 A 持平：新增 ArkTS 层与逐步替换脆弱插件相抵）；若你认为插件生态风险已不可接受、把 B 的维护分上调到 3.0，B 为 3.63，仍低于 A。若把“平台能力/战略”权重提高到 25%，C 会上升；若成本权重提高到 40%，A 胜出。**结论不是“B 绝对最优”，而是“在不确定的战略前提下，B 是风险调整后的默认选择”。**

### 8.3 B vs C：增量收益与成本（选 B 的关键依据）

| C 相对 B 多得到什么 | 是否可测 | 何时可测 | 对应代价/备注 |
|---|---|---|---|
| 移除 Flutter engine → 体积/启动/内存 | 可测 | 先测 A 基线；S0 测 C | 体积测算见 §7.5；启动/内存无基线，不能先验宣称 |
| 摆脱 56 插件类依赖/13 override/5 vendored 与 Flutter OHOS fork | 可统计 | 每次上游升级计时 | 这是 C 最实的长期收益；但 B 也能逐个替换最脆弱插件 |
| 原生 UI/无障碍/折叠屏/2in1/系统集成 | 部分可测 | 用户测试/评审 | 服务卡/实况窗/分享扩展等 B 也能用 ArkTS 做，非 C 独占 |
| 更少的跨平台代码共享 | 负收益 | 立即 | C 是永久分叉，双写成本 1.5–3 人月/月 |
| 远端推送 | 不成立 | — | 仍需自建转发服务，与 C 无关 |

**量化**：C 的增量成本约 **100–190 人月**（118–200 vs 10–20），增量收益主要是“体积/启动/引擎移除 + 插件生态风险消除”。其中体积/启动尚未测量，插件风险可用 B 渐进替换。**因此，除非体积/启动/引擎移除是硬指标（或 Flutter OHOS 路线断裂），否则 B 的性价比显著更高。**

### 8.4 推荐

- **默认 B（条件性）**：用 10–20 人月补齐能力 + 原生系统入口，先把“平台能力收益”拿到；保留 Flutter 的跨平台与现有交付。**若只看成本/时间，A 更优；选 B 的前提是插件生态/平台能力确实是痛点。**
- **保留 C 作为条件触发**：满足 §9.3 的触发条件再启动；启动前必须通过 S0 PoC 门禁。
- **不建议 C' 作为首版**：Rust core 重构本身是 20–40 人月级投入，且会同时拖慢 Flutter 侧；可作为 2–3 年后的架构演进。

---

## 9. 推荐路线与触发条件

### 9.1 路线 B（默认）

**B1（4–8 周，约 5–8 人月）：补齐高价值降级项**
- **cook JS（可选/最后做）**：先做可行性验证（`flutter_qjs` 或 NAPI QuickJS），**1:1 预览不作为 B1 验收**；这与 R4“首版不做 1:1”一致；
- AVIF：`libohos_avif.so` 已产出（工作区未提交），先完成提交/真机验证/回滚开关；当前 release HAP 不含它，需重新构建确认；
- 富剪贴板：ArkTS `pasteboard` 桥（HTML/图片/URI）；
- 后台/通知：`backgroundTaskManager` 长时任务 + 本地通知（不依赖 AGC）；
- **远端推送先不做**：linux.do 不会向 HMS 推送，要接 Push Kit 必须先自建转发服务；这是独立项目/产品决策，不是“接个 SDK”；
- 修复插件版本风险：把 `inappwebview`/`file_picker`/`record` 等 override 收敛到可维护版本，记录升级路径；
- 测量基线：冷启动、HAP 体积、长帖帧率、内存，作为后续任何决策的依据。

**B2（8–12 周，约 5–10 人月）：原生系统入口（不改 UI）**
- 通知扩展/点击跳转；分享扩展（Share Kit）；深链/App Linking；
- 实况窗（LiveView Kit）用于活动/通知类场景（如需要）；
- 扫码/账号一键登录（Account Kit）等系统能力；
- 这些都可以用 ArkTS 实现，不需要替换 Flutter UI，是“性价比最高的原生化”。

**B3（可选，不建议早做）**：用 `OhosView` 把个别页面（设置/关于/通知中心）做成 ArkUI，嵌入 Flutter。**两套 UI 框架同页混用会显著增加复杂度，除非有强需求，否则不做。**

**B4**：每年复评一次；若触发条件出现，启动 S0 PoC。

### 9.2 S0 原生竖切 PoC（如果决定评估 C）

- **范围**：独立原生工程（`scratch/native-spike/`，不影响 `repo`）；原生壳 + ArkWeb 登录/CF + `fetchAllCookies` 注入 + 话题列表 + 话题详情（Web 或简化渲染）+ 图片 + 简单文本回复 + **编辑器最小竖切**（中文 IME/加粗/引用/图片/撤销 20 步）。
- **不做**：完整编辑器（表格/投票/语音/富粘贴）、聊天、通知、平板、AGC 推送、其他平台。
- **环境**：DevEco Studio 26 / API 26 / 模拟器 x86_64；构建需 `danger-full-access`（现有工具链在 `tools/env.ps1`）。
- **时间盒**：2–3 人 × **18–20 个工作日**；超 30 个工作日（1.5×）即停。
- **通过标准（G1）**：
  1. 3 天内完成构建/签名/安装/启动；
  2. 5 天内完成登录 + CF + `fetchAllCookies` 注入 → API 200，冷启动 10/10 无人工；
  3. 5 天内完成 3 个真实话题渲染（长帖/投票/代码+公式+onebox），滚动 ≥50 fps，文本可选；
  4. 3 天内完成文本回复 + 图片上传 + 表情；
  5. 4 天内完成编辑器最小竖切（中文 IME/加粗/引用/图片/撤销 20 步）；若此条不达标，**G1 不得通过**，因为编辑器是 C 的两大风险之一；
  6. 记录原生开发速度（有效 LOC/人日）、HAP 体积、启动时间、内存峰值。
- **产出**：测量报告 + go/no-go 建议；代码仅留在 `scratch/`，不合并。

### 9.3 C 的触发条件（满足至少 2 条再启动）

1. **战略**：HarmonyOS 成为主战场/唯一发行渠道，或公司明确要求“纯鸿蒙原生”；
2. **技术**：Flutter OHOS 分支不可持续（停止维护/无法升级），或插件生态（3.35 vs 3.47）导致无法交付；
3. **指标**：体积/启动/内存/上架有硬指标，混合方案无法达标；
4. **能力**：必须深度使用系统独占能力（服务卡、实况窗、系统搜索、分享扩展、账号等），且这些能力无法通过 ArkTS 模块与 Flutter 共存；**远端推送不算**——它需要自建转发服务，与是否全原生无关；
5. **团队**：可投入 ≥4 名原生专职 + 1 设计 + 1 QA，持续 12+ 个月，并接受上游功能冻结或双团队；
6. **数据**：用户数据迁移方案（登录态/草稿/收藏）已产品确认。

### 9.4 止损线

- S0 超过 1.5× 时间盒，或关键路径（CF/渲染）未达标 → 留在 B；
- S1 阶段实际速度 < 计划 50%，或渲染/编辑器返工 >2 次 → 停止 C，回滚 B；
- 任何阶段导致现有 Flutter 版本无法维护/发版 → 立即停止；
- 保留 Flutter 版本至少 2 个 release 作为回滚路径。

### 9.5 迁移顺序（若做 C）

1. 基础设施（工程/导航/主题/网络/存储/日志）；
2. 登录/CF/cookie/会话；
3. 话题列表/详情（先 Web/混合渲染，再自研节点）；
4. 回复/发帖（先纯文本+图片，再富文本）；
5. 搜索/通知/个人中心/设置；
6. 聊天/私信/媒体/AI/长尾；
7. 原生增强（实况窗/服务卡/多设备/账号；推送需先有服务端转发）。

**不要从编辑器/渲染器开始**：这两个是最高风险，先做会把项目拖死；先用低风险链路验证团队速度，再啃硬骨头。

---

## 10. 结论与建议

### 10.1 直接回答

**“全部用原生鸿蒙架构替代”在技术上可行，但经济上不划算，除非满足明确的战略/技术触发条件。**

- 可行：24 个能力域 + cook JS 单列（共 25 项）没有 D 级硬阻塞（桌面专属功能、无服务端转发的远端推送除外）；4 个域已有可运行原生实现，18 个域有明确 API/库路径，3 个域需要 PoC/自研（HTML 渲染、编辑器、cook JS）。
- 不划算：完整对标 **118–200 人月**、4 人团队 2.5–4.5 年；同期 Flutter 版本已交付且可继续维护；全原生会形成第二套代码库，上游每个功能双写。
- 两个真正的硬骨头：**Discourse HTML 渲染 + 富文本编辑器**；再加上**双代码库/上游分叉**的长期成本。CF 已找到 `fetchAllCookies` API 路径（B-，需验证），不再是“不可解”的否决项。

### 10.2 建议

1. **短期（0–3 个月）**：保持 Flutter 版本；执行 B1，补齐 cook/AVIF/富剪贴板/后台/本地通知；测量体积/启动/帧率基线；远端推送先不启动（需自建转发）。
2. **中期（3–12 个月）**：执行 B2，增加原生系统入口（通知/分享/深链/实况窗/账号）；根据战略变化决定是否做 S0 PoC。
3. **长期（12 个月+）**：仅在 §9.3 条件下启动 C；先 S0 → G1 → S1，分阶段、可回滚，不承诺一次性 parity。若一定要做全原生，建议做 **S2-lite 精简版**（保留阅读/发帖/搜索/通知/个人/设置，砍掉 AVIF/远端推送/LDC/Notion/2in1/部分长尾），目标 60–90 人月，而不是追求 46 页全量 parity。
4. **不要**：为了“纯原生”而重写一切；不要在未验证 CF/渲染/编辑器之前排期；不要低估数据迁移与双代码库维护。

**决策速查**：

| 你的首要目标 | 建议 | 理由 |
|---|---|---|
| 补齐通知/后台/分享/扫码/深链/账号等平台能力 | **B（B1/B2）** | 10–20 人月，ArkTS 模块即可，不需要重写 UI |
| 降低体积/启动时间/移除 Flutter 引擎 | **先测 A 基线，再决定是否 S0** | 这是 C 唯一确定的增量收益，但体积/启动尚未测量；测算见 §7.5 |
| OHOS 成为主战场，且团队 ≥4 名原生专职 12+ 个月 | **C（S2-lite 优先）** | 60–90 人月可交付精简原生版；不要承诺 46 页 parity |
| 其他平台仍是主力、OHOS 只是补充 | **A/B** | 双代码库长期成本高于收益 |

### 10.3 一句话给决策者

**“如果 HarmonyOS 只是多平台之一，继续 Flutter + 原生能力层；如果 HarmonyOS 是未来主战场，且愿意投入 2.5–4.5 年和一支原生团队，那么全原生可行——但请先用 4 周 PoC 证明你们能过 CF、能渲染长帖、能做编辑器，再签字。”**

---

## 附录 A：统计命令与口径

```powershell
# 代码规模（在 repo/ 下；Windows PowerShell 5.1）
# 注意：Measure-Object -Line 统计“非空行”（不含空行、含注释），不是物理行
Get-ChildItem lib -Recurse -File -Filter *.dart |
  ForEach-Object { (Get-Content $_.FullName -Encoding UTF8 | Measure-Object -Line).Lines } |
  Measure-Object -Sum

# 物理行（含空行）
Get-ChildItem lib -Recurse -File -Filter *.dart |
  ForEach-Object { [System.IO.File]::ReadAllLines($_.FullName).Count } |
  Measure-Object -Sum

# 目录级统计（非空行）
foreach ($d in 'pages','widgets','services','providers','models','utils','l10n') {
  $fs = Get-ChildItem "lib\$d" -Recurse -File -Filter *.dart
  $loc = ($fs | ForEach-Object { (Get-Content $_.FullName -Encoding UTF8 | Measure-Object -Line).Lines } | Measure-Object -Sum).Sum
  "$d $($fs.Count) $loc"
}

# 依赖/插件/产物
Select-String -Path pubspec.yaml -Pattern '^  [a-zA-Z_0-9]+:'
Get-ChildItem ohos\entry\oh_modules -Directory
Get-ChildItem ohos\entry\libs -Recurse -File
Get-ChildItem C:\Users\iceblock\fluxdo\.cache\ohos-build -File -Filter *.hap
```

口径：正文行数默认“非空行（不含空行、含注释）”；`lib` 非空行 293,108、物理行 322,795；测试非空行 49,272、物理行 53,535。`lib` 不含 `packages/fluxdo_render`；插件数不含 `@ohos` 与 `flutter_native_x86_64` 等构建辅助包。

## 附录 B：关键证据索引

| 主题 | 证据 |
|---|---|
| 移植总览/验收 | `docs/ohos-port-report.md`、`docs/ohos-acceptance.md`（A1–A35）、`README-ohos.md` |
| CF 修复与 cookie 边界 | `docs/ohos-cf-fix.md:147-163`、`:419-421`；`docs/ohos-port-status.md:33`；SDK `@ohos.web.webview.d.ts:1492`（`fetchAllCookies`）、`:8093-8157`（`WebHttpCookie`）、`:1247`（`configCookieSync` includeHttpOnly）；插件 `.pub-cache/.../MyCookieManager.ets:169-195` |
| 插件矩阵/版本风险 | `docs/ohos-plugin-matrix.md:12`、`:15`、`:17`、`:37-66`、`:68-92` |
| 原生组件策略 | `docs/ohos-native-strategy.md:41-66`、`:850`（Rust 交叉编译）、`:876`（AVIF 实测） |
| ArkTS 桥 | `docs/ohos-arkts-bridges.md`；`repo/ohos/entry/src/main/ets/plugins/FluxdoBridgePlugin.ets:105-150` |
| 能力开关 | `repo/lib/utils/ohos_compat.dart:18-74` |
| 渲染器重构 | `repo/docs/render_refactor_plan.md:52`、`:75`、`:205`、`:474`；`repo/packages/fluxdo_render` 41,126 行 |
| ArkUI 组件限制 | hmos skill：`hmos-arkui-knowledge-retriever` 的 `ts-basic-components-richtext.md`（不再维护/List 内卡顿）、`arkts-common-components-richeditor.md`（粘贴/IME/StyledString 限制）、`ts-basic-components-image.md`（GIF/WebP/APNG）；SDK `ets/component/web.d.ts:7332-7342`（FIT_CONTENT/7680）、`ets/component/rich_editor.d.ts:126-147,3431`（UndoStyle/undoStyle） |
| 原生 API | `@ohos.net.http.d.ts`（HTTP/2/3、TLS、证书、代理）、`@ohos.multimedia.image.d.ts:77`（格式清单无 AVIF）、`@ohos.arkui.componentSnapshot.d.ts`（快照 API）、`@ohos.data.relationalStore.d.ts`（加密/FTS）、`@hms.collaboration.rcp.d.ts:1177`（CookieRepository）、`@hms.core.push.pushService.d.ts:102`（getToken）、`@hms.core.scan.scanBarcode.d.ts:258`、`@hms.collaboration.systemShare.d.ts:719` |
| NAPI 先例 | `.pub-cache/.../flutter_inappwebview_ohos/ohos/src/main/cpp/napi_init.cpp`（`napi_define_properties`/`napi_module_register`，真实编译）；`native/sysroot/usr/include/node_api.h` |
| 测试/DFX | hmos skills：`hmos-local-test`、`hmos-instrument-test`、`hmos-jscrash-analysis`、`hmos-cppcrash-analysis`、`hmos-native-memleak-analysis`、`hmos-appfreeze-analysis` |

## 附录 C：未验证项（必须在 PoC/真机确认）

1. `WebCookieManager.fetchAllCookies()` 在过盾后是否返回 `cf_clearance` 实体，且 `isHttpOnly`/`value` 正确（这是 CF 可行性的决定性 A/B）。
2. RCP `CookieRepository` 注入 `WebHttpCookie` 后，CF 是否放行；UA/TLS 指纹是否触发二次挑战。
3. ArkUI 自研 HTML 渲染器在长帖/复杂节点下的帧率、内存、选区是否正确；`Web` 的 `FIT_CONTENT` 在 >7680px 长帖的实际表现。
4. RichEditor 在中文 IME、图片粘贴（`onPaste` 拿不到 MIME）、撤销粒度/可编程性（有 `undoStyle` 但无 undo() 方法）、表格、`fromHtml/toHtml` 标签覆盖、Markdown 往返下的实际可用度。
5. AVIF `.so`/NAPI 封装后的解码性能与内存（`libohos_avif.so` 未提交、未进当前 HAP、未真机）。
6. Push Kit 在 AGC 开通/发布证书/自建转发服务后的 token 获取与到达率；**没有服务端转发就没有远端推送**。
7. 原生应用与 Flutter 应用同 bundle 升级时的数据迁移可行性（Hive/Preferences/cookie/secure storage）。
8. 真机相机扫码、后台播放、长时任务、折叠屏/2in1 布局。
9. 原生 HAP 的 release 体积/启动时间/内存相对 Flutter 版本的实际收益（先测 A 基线，再谈 C）。
10. 团队 ArkTS 真实产能（用 S0 的 LOC/人日测量，而不是拍脑袋）。
11. AGC 发布证书/Profile、App Linking 域名校验、应用市场审核与隐私合规；第三方客户端 + CF 绕过/UA 归一的站点 ToS/平台政策风险。
12. 原生 hilog/faultlog 可观测性（现有自定义 domain 在文档与实测间存在冲突）。

## 附录 D：术语

| 术语 | 含义 |
|---|---|
| ArkTS/ArkUI | HarmonyOS 的声明式 UI 语言与框架 |
| NAPI | Node-API，ArkTS 与 C/C++/Rust 原生库的桥接接口 |
| RCP | Remote Communication Kit，HMS 原生 HTTP 客户端（HTTP/3、CookieRepository、TLS 配置） |
| HAP | HarmonyOS 应用包 |
| AGC | AppGallery Connect，华为应用市场/推送/账号的后台 |
| CF | Cloudflare（linux.do 前置盾） |
| cook | Discourse 服务端把 Markdown 渲染为 HTML 的过程；客户端 cook JS 用于 1:1 预览 |
| parity | 功能/体验对等 |
| S0/S1/S2 | 竖切 PoC / 核心版 / 完整版 |

---

## 附录 E：版本与修订

| 版本 | 时间 | 修订 |
|---|---|---|
| v1.0 | 2026-10-21 | 初稿（基于 `repo` @ `ba28efd`、移植文档、SDK 声明、26 个 OHOS 插件源码、hmos skill） |
| v1.1 | 2026-10-21 | 评审修订：统一维护成本单位；修正 RichEditor undo/redo 表述；补 B vs C 增量收益；修正 HAP 体积口径与测算；行数改为“非空行”并给物理行；修正 l10n key、Hive/prefs 计数、builder 计数、S0 时间盒与 G1；补充收益假设/ToS 风险 |

---

> 本文所有“可行/不可行”结论均为条件性判断；最终决策请以 S0 PoC 的实测数据与产品战略为准。  
> 本文未修改任何生产代码；评估期间 `repo` HEAD 为 `ba28efd`，工作区状态可能随开发继续变化。
