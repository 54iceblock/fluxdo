# FluxDO × HarmonyOS 7 验收清单（Lead 维护）
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从应用侧 `module.json5` 删除（最终包仍由依赖 HAR 带入，见 README.md）。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 设备：HarmonyOS 7.0.0 (API 26) 模拟器 `127.0.0.1:5555`（Pura 90 Pro，x86_64）
> 构建/安装：`tools\build-ohos.ps1 -Install -Launch`（需 danger-full-access）
> 截图：`hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/x.jpeg` + `hdc ... file recv`
> 交互：`hdc -t 127.0.0.1:5555 shell "uinput -T -c <x> <y>"`（分辨率 1256×2760）

## A. 已完成并有证据

| # | 项目 | 证据 | 状态 |
|---|---|---|---|
| A1 | HAP 构建（25 个 OHOS 插件） | `.cache/ohos-build/logs/*.log` `assembleHap` 成功 | ✅ |
| A2 | 签名 + 安装 + 启动 | `install bundle successfully` / `start ability successfully` / `ps` 见 com.fluxdo.app | ✅ |
| A3 | 首屏渲染（登录页 + 游客入口） | `.cache/fluxdo-shot2.jpeg` | ✅ |
| A4 | 权限弹窗（麦克风，record 插件） | `.cache/fluxdo-shot1.jpeg` | ✅ |
| A5 | ArkWeb(WebView) 初始化 + UA 覆盖 | hilog `InAppWebView --> applyJsUserAgentOverride` | ✅ |
| A6 | 进入主界面（话题页容器） | `.cache/fluxdo-shot3.jpeg` | ✅ |
| A7 | **Cloudflare 403 解决**（挑战真正执行 + WebView 网络栈兜底） | `.cache/fluxdo-shot5.jpeg`（CF 安全验证页真正跑起来）、`shot8`/`shot9`（数据正常） | ✅ |
| A8 | **游客浏览话题列表**（真实数据：标题/作者/头像/分类/标签/回复数/相对时间） | `.cache/fluxdo-shot8.jpeg` | ✅ |
| A9 | **话题详情页**（正文 HTML 渲染、折叠块、楼层 #1、1/4 分页、作者卡、相对时间「7小时前」） | `.cache/fluxdo-shot9.jpeg` | ✅ |
| A10 | 图片加载（CDN 头像） | shot8/shot9 中头像已渲染 | ✅ |
| A11 | **搜索**（输入 + 提交 + 结果列表） | `.cache/shot-search4.jpeg`：50 条结果、排序「相关性」、结果卡（标题/摘要/作者/头像/时间/分类） | ✅ |
| A12 | 系统输入法（软键盘输入中文/英文） | `.cache/shot-search2.jpeg` | ✅ |
| A13 | **深链** `fluxdo://topic/1` | `.cache/shot-deeplink.jpeg`：直接打开话题 #1（57 回复/1.3w 浏览/楼层/分页 1/58/相关链接折叠） | ✅ |
| A14 | 绝对日期渲染（时区桥间接验证） | shot-deeplink 底部「2024年1月30日」 | ✅（精确 TZ 待专项验证） |
| A15 | 应用设置页（8 个分类 + 设置搜索） | `.cache/shot-settings.jpeg` | ✅ |
| A16 | 网络设置页（引擎选择 / DOH 关闭=系统 DNS / 上游代理 / VPN 自动切换；引擎说明显示「主站 API 请求走 WebView，其余走 Dio IO 适配器」= 第 5 轮 CF 方案生效） | `.cache/shot-net.jpeg` | ✅ |
| A17 | 数据管理页（真实缓存统计 5.2 MB、分类占比、清理按钮、AI 聊天数据、Cookie 缓存） | `.cache/shot-data.jpeg` | ✅ |
| A18 | 话题菜单（书签/通知/链接/过滤 + 生成分享图片/导出文章/浏览器打开/阅读设置） | `.cache/shot-menu.jpeg` | ✅ |
| A19 | **分享图片生成**（渲染卡片：品牌头、标题、作者、正文、图片、链接 + 6 套主题色） | `.cache/shot-share.jpeg` | ✅ |
| A20 | **系统分享面板**（share_plus OHOS）：分享 1 项 101.12 KB、华为分享、复制/保存至图库/打印/添加至中转站 | `.cache/shot-sharepanel.jpeg` | ✅ |
| A21 | **保存到相册**（saver_gallery/photoAccessHelper）：应用正确触发系统授权弹窗「允许 FluxDO 保存 1 张图片?」 | `.cache/shot-savegallery.jpeg` | ✅（弹窗为系统窗口，模拟器不接受注入点击，需人工点「允许」） |
| A22 | **导出文章 → 分享**：生成 Markdown（171 B）并唤起系统分享面板（华为分享/复制/另存为/添加至中转站） | `.cache/shot-exportshare.jpeg` | ✅ |
| A23 | **导出文章 → 另存为**：唤起系统文件保存器（`FilePickerUIExtAbility`，pickerType=save，可选「我的手机/Download/Documents」） | `.cache/shot-saveas6.jpeg` + hilog `[picker] document save start` | ✅（修复后；确认保存需人工点 ✓，模拟器不接受对扩展窗口的注入点击） |
| A24 | 跳转到话题（话题 ID 输入 + 跳转） | `.cache/shot-jump4.jpeg` | ✅ |
| A25 | 不存在的话题错误态（内容不存在 / 重试 / 查看详情） | `.cache/shot-menu2.jpeg` | ✅ |
| A26 | **时区（精确校验）**：应用落盘日志 `{"type":"timezone","event":"timezone_resolved","result":"resolved","timezone":"Asia/Shanghai","platform":"ohos"}` | `files/flutter/logs/app_log.jsonl` | ✅ |
| A27 | 楼层导航面板（当前楼层 1/16、滑动条、正位于此、跳转） | `.cache/shot-floor.jpeg` | ✅（可打开；面板按钮不接受注入点击） |
| A28 | 静态分析 | `dart analyze lib` | ✅ **0 error / 0 warning**（123 条既有 info 级 lint） |
| A29 | 代码固化 | `git log` | ✅ 主提交 `674a99f`（656 文件），submodule `8c18e80`；`oh_modules/` 已 gitignore |
| A30 | 干净工作区回归构建 | 15:43 后再次执行 build-ohos.ps1 | ✅ assembleHap → 签名 → 安装 → 启动全通 |
| A31 | **实时相机扫码（扫码登录）**：`mobile_scanner` OHOS 通道全部激活（`scanner/method`、`scanner/event`、`scanner/deviceOrientation`），页面显示相机预览 + 系统相机权限弹窗「用于扫码登录和拍摄图片」+ 「从相册选择」兜底 | `.cache/shot-qrscan.jpeg` + hilog | ✅ 相机不可用/未授权时 errorBuilder 自动降级相册，不会卡死 |
| A32 | **长按选中文本**（选择手柄 + 高亮 + 菜单「复制 / 全选 / 复制引用」） | `.cache/shot-select2.jpeg` | ✅ 选择菜单正常 |
| A33 | **游客态鉴权 API 优雅降级**：`GET /u/recent-searches.json` 返回 403 时，应用记录 `auth_signal_suppressed_already_logged_out` 并继续工作（不崩溃、不弹错误页） | `files/flutter/logs/app_log.jsonl` | ✅ |
| A34 | **release 构建**（AOT）：`flutter build hap --release --target-platform ohos-x64` → HAP 86.5 MB（签名后 91.3 MB，debug 为 344 MB），安装启动后**冷启动零点击**出话题列表、无 DEBUG 角标 | `.cache/shot-release.jpeg` + `build-release-*.log` | ✅ |
| A35 | **网络设置平台守卫**：HarmonyOS 上不再展示依赖 Rust 本地网关的「DNS over HTTPS」项（避免失效入口），其余设置项完整 | `.cache/shot-net2.jpeg` | ✅ |

## B. 待验证

| # | 项目 | 验证方法 | 通过标准 | 状态 |
|---|---|---|---|---|
| B3 | 正文内嵌图片（非头像） | 打开含图话题 | 图片显示，非裂图 | ✅（shot-menu/shot-share 中正文图片已渲染） |
| B5 | 未登录限制提示 | 游客态点回复/书签 | 提示登录（而非崩溃） | ⚠️ 门禁为纯 Dart 逻辑（与平台无关）；已旁证：游客态鉴权 API 403 被优雅降级（A33）。菜单图标行与粘贴菜单不接受注入点击，未能点中验证 |
| B6 | 网络设置页 | 「网络设置」入口 | 页面可打开，DOH 在 OHOS 显示不可用 | ✅（A16） |
| B7 | 分享（share_plus OHOS） | 话题/图片 → 分享 | 系统分享面板出现 | ✅（A20） |
| B8 | 文件选择/导出（file_picker OHOS） | 导出文章/选文件 | 系统选择器出现并返回 | 待验证 |
| B9 | 登录流程（WebView OAuth / Discourse 授权） | 登录页 → 登录 → 走完授权 | 登录成功并显示用户态 | 部分验证：登录页与两种入口渲染正常（shot-login）；无账号无法走完授权 |
| B10 | 冷启动 CF | 冷启动观察 | 自动通过、无需手动 | ✅（A 组 CF 结论，shot-cold-r5） |

> **冷启动 CF 浮层（已解决，第 5 轮）**：
> - 第 2 轮：dio 先请求 → 403 → 浏览器栈重放 → 能出数据，但冷启动需「退出 → 重试连接」两步。
> - 第 3 轮：「首个请求即走浏览器栈」+ robots.txt 真实导航 → 回归（预加载挂死 70s+）。
> - 第 4 轮：回退回归 + 12s 硬超时 → 恢复可用，浮层仍不自动关（DOM 判据在 OHOS 上拿不到稳定信号）。
> - 第 5 轮（最终）：OHOS **默认强制浏览器栈** + **ArkWeb cf_clearance 优先判据**（挑战通过后 ArkWeb 一定写入 clearance，`fetchCookieSync` 可读，与 DOM/UI 状态无关）+ 12s 超时自动回退 dio。
> - **验收证据**：`.cache/shot-cold-r5.jpeg` —— 冷启动**不点任何按钮**，话题列表直接加载（含「刚刚/1分钟前」的新帖、头像、分类、标签、回复数）。

## C. 待验证（ArkTS 桥，task-8）

| # | 项目 | 验证方法 | 通过标准 |
|---|---|---|---|
| C1 | 时区 | 进任意列表看绝对时间（相对时间不受时区影响）；或 App 落盘日志 | 本地时间（Asia/Shanghai），非 UTC 偏移 |
| C2 | 保存图片到相册 | 图片查看器 → 保存 | 系统保存弹框 → 图库可见 |
| C3 | 复制文本 | 长按选中 → 复制 | 剪贴板可粘贴（无 MissingPluginException） |
| C4 | 本地通知 | 设置里开启通知 | 无崩溃；收到测试通知（首启已见系统通知权限弹窗 = 插件已注册） |
| C5 | 深链 | `hdc shell aa start -a EntryAbility -b com.fluxdo.app -U "fluxdo://topic/1"` | 应用打开并跳到话题 |

> **观测性已知问题**：ArkTS 侧 `hilog` 用自定义 domain `0x0F1D` 打点，实测在 `hilog -x` 转储里看不到（疑似该 domain 未被 hilog 允许输出；Dart 的 `debugPrint` 也不进 hilog）。因此 C1/C2 需要靠 UI 行为或落盘日志判定，或后续把桥的 domain 改成可输出域（如 0x0000）再验证。

## D. 已确认降级（首版不阻塞，需在文档/UI 明示）

| 能力 | OHOS 现状 | 后续 |
|---|---|---|
| DOH 代理 / rhttp | 禁用，dio 直连 | P1/P2 Rust 交叉编译（docs/ohos-native-strategy.md） |
| cook JS 1:1 预览 | Dart 近似预览 | P2 换 flutter_qjs |
| AVIF / 动图 | 引擎内建解码 | P2 原生库移植 |
| 后台保活/后台通知 | 仅前台 | P2 长时任务 |
| 相机扫码 | 相册 + zxing2 兜底 | P2 mobile_scanner ohos |
| 应用内更新 | 引导外部（HAP 不能静默装） | — |
| 富文本/图片剪贴板 | 纯文本兜底 | P2 |

## E. 回归要求

1. `dart analyze lib` 0 error。
2. 非 OHOS 平台行为不得回退：所有改动以 `PlatformUtils.isOhos` / `OhosCompat` 前置（Lead 在合并时逐条核对）。
3. 关键产物可复现：`tools/build-ohos.ps1` + `tools/ohos-sign.ps1` + `docs/ohos-port-status.md` §6。

## A 组补充（第 20–24 轮新增，原生能力落地）

| 编号 | 验收项 | 证据 | 结果 |
|---|---|---|---|
| A36 | **DOH 代理原生库**（Rust `core/doh_proxy` → libdoh_proxy.so，x86_64/arm64）随 HAP 打包，网络设置恢复「DNS over HTTPS」项 | HAP 内含 `libs/*/libdoh_proxy.so`；`.cache/shot-doh.jpeg` | ✅ |
| A37 | **rhttp 原生库**（Rust + flutter_rust_bridge → librhttp.so）加载成功 | 日志 `{"type":"rhttp","event":"rhttp_init","result":"ok"}` | ✅ |
| A38 | **原生动图解码**（Rust native_animated_image → libnative_animated_image_codec.so） | 日志 `{"event":"native_animated_codec","result":"ok","version":"0.3.2"}` | ✅ |
| A39 | **AVIF 解码**（自编 libavif+dav1d → libohos_avif.so）：真实 1204×800 AVIF 解出 RGBA | 日志 `{"event":"avif_probe","result":"native-ok","detail":"w=1204 h=800 rgba=3852800"}` | ✅ |
| A40 | **cook JS 渲染**（自编 QuickJS 0.17.0 → libohos_quickjs.so）：cook bundle eval 成功且全局可见 | 日志 `cook_bundle_eval ok (567467B/84ms)`、`cook_global_probe globalType=object` | ✅ |
| A41 | **后台保活**（backgroundTaskManager 长时任务）：切后台可申请、回前台释放 | 日志 `{"event":"ohos_continuous_task_probe","state":"started"/"stopped"}` | ✅ |
| A42 | **富文本剪贴板·写图片**（ArkTS pasteboard）：PNG→PixelMap→系统剪贴板 | 日志 `{"event":"ohos_clipboard_probe","result":"write-ok"}` | ✅ |
| A43 | **release 包（含 5 个原生库）**：118.4 MB，安装启动、列表/详情/首页图片均正常 | `.cache/shot-release4.jpeg` 等 | ✅ |
| A44 | **静态分析**：`dart analyze lib` → 0 error / 0 warning（129 条既有 info） | 本地执行 | ✅ |

## 平台语义差异（非功能缺陷，已文档化）

| 差异 | 原因 | 应用行为 |
|---|---|---|
| 应用内更新安装 | HarmonyOS 不允许第三方应用静默安装 HAP | 检查更新后打开浏览器发布页，由用户安装 |
| 剪贴板「读」富文本 | `ohos.permission.READ_PASTEBOARD` 属 system_basic 级，普通证书无法授予 | 自动回退纯文本粘贴（写图片不受影响） |

## 通知能力现状（第 25 轮实测）

| 项 | 结果 |
|---|---|
| `flutter_local_notifications` OHOS 端口注册 + `initialize()` | ✅ 日志 `ohos_notification_probe result=ok` |
| 实际展示通知 | ⚠️ 系统侧 `allowEnableNotification: false`（应用通知开关需用户在「设置-通知」里手动打开，模拟器无法注入系统设置点击） |
| 应用侧兜底 | 未授权时插件按既有逻辑跳过展示，不影响其他功能（见 `local_notification_service.dart` 权限分支） |
