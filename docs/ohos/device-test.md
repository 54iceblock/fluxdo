# 真机验证与测试

> 验证设备：**HUAWEI HBN-AL00**，**HarmonyOS 7.0.0.109(SP8C00E105R5P2)**，API **26**
> 构建：release（AOT）+ 华为调试证书签名，双 ABI 约 204 MB
> 应用：`com.fluxdo.app` v0.2.29

## 1. 结论

核心功能在真机上可用：安装启动、浏览/详情/搜索、设置、网络引擎切换、DOH 加密 DNS、
分享图片/系统分享/保存相册、深链、扫码相机、WebView 授权，以及 5 个自编译原生库加载，全部通过。

登录链路已用**真实 linux.do 账号**验证：浏览器授权 → 深链回跳 → OTP 兑换 → 登录态生效，
首页/「我的」/通知均为真实数据（见 §2.10）。发帖/回复的真实提交仍在 mock 环境验证（§2.9）。

## 2. 已验证项

### 2.1 安装与启动

| 项 | 结果 |
|---|---|
| 安装 | 华为调试证书签名后 `install bundle successfully` |
| 冷启动 | 进程约 0.9 s 就绪，随后出首屏列表 |
| 版本标识 | 界面无 DEBUG 角标（release + AOT 确认） |
| 稳定性 | 多轮启停、切前后台无崩溃（faultlogger 无记录） |

### 2.2 五个原生库（arm64 真机）

| 能力 | 证据（应用日志） |
|---|---|
| rhttp（Rust HTTP/2） | `{"type":"rhttp","event":"rhttp_init","result":"ok"}` |
| 动图解码 | `native_animated_codec ok version 0.3.2` |
| AVIF | `avif_probe native-ok w=1204 h=800 rgba=3852800` |
| QuickJS cook | `cook_bundle_eval ok 567467B（54–68ms）` + `cook_global_probe object` |
| DOH 网关 | `[DOH] 使用 FFI 启动代理` → `FFI 代理已启动，端口 41463`；设置页显示「代理运行中」 |
| 时区桥 | `timezone_resolved America/Los_Angeles`（跟随设备系统时区） |

### 2.3 浏览与详情

- 首页：主题、标签、作者头像、回复数、点赞数、时间正常；下拉刷新、无限滚动正常
- 详情：标题、分类标签、统计、楼层号、引用块、行内代码、代码块、链接预览卡（带图）、
  嵌套回复、客户端标识、表情反应栏、楼层进度（1/262）
- 用户卡片：信任等级、徽章、加入时间、统计

### 2.4 搜索

- 软键盘输入 "HarmonyOS" → **50 条结果**，「相关性」排序，结果含摘要/作者/标签/时间，可跳转

### 2.5 设置

设置树完整：外观 / 阅读 / 网络 / 功能 / 底栏 / 数据管理 / Notion 同步 / 关于。

网络设置内已验证：

- **网络引擎**：标准 / 高性能 / 兼容 / 自定义；切到「高性能」提示「使用 rhttp 引擎（HTTP/2 · Rust）」，
  切换后列表加载正常
- **DNS over HTTPS**：开关 + 「代理运行中 · 端口 41463」+ 设备独有证书 + 更多设置（服务器/IPv6/ECH）
- 上游代理（HTTP/SOCKS5/Shadowsocks）、VPN 自动切换、CF 自动验证

### 2.6 分享与媒体

- 「生成分享图片」：6 种主题（经典/纯白/深色/纯黑/蓝调/绿野）预览正常
- 「保存到相册」：系统授权弹窗「允许 FluxDO 保存 1 张图片？」正常
- 「分享」：系统分享面板正常（华为分享/微信/QQ/备忘录/打印等）
- 扫码登录页：相机权限弹窗 + **实时相机预览 + 扫码框** 正常
- 浏览器授权登录：应用内 WebView 正常打开 linux.do 登录页

### 2.7 深链

`fluxdo://topic/<id>` → `aa start -a EntryAbility -b com.fluxdo.app -U 'fluxdo://topic/…'`
可直接打开对应话题。

### 2.8 设置持久化

force-stop 后重启：DOH 自动恢复并拉起、网络引擎选择保持、5 个原生库探针全部重新通过。

### 2.9 登录后链路（mock 服务验证）

用本地 mock Discourse 服务（`tools/ohos/mock-discourse/server.py`）验证：

| 项 | 结果 |
|---|---|
| 登录态首页 | mock 话题列表 + 通知铃铛 + 发帖 FAB |
| 「我的」页 | 用户信息、等级、统计卡片、私信/聊天/徽章/邀请链接等入口 |
| 通知列表 | @提及 / 回复 / 点赞 三条，含类型图标、未读点、相对时间 |
| 发帖编辑器 | 标题/字数限制、Markdown 正文、分类选择、标签、预览、工具栏 |
| 写入请求 | `POST /posts.json` 200（mock 日志确认），随后跳转话题详情 |

> mock 只覆盖「请求构造 → 网络层 → 解析 → UI 渲染」链路；真实服务端行为（权限、审核、CF）需真实账号。

### 2.10 真实账号登录（浏览器授权）

用真实 linux.do 账号实测「浏览器授权登录」，验证通过：

| 项 | 结果 |
|---|---|
| 浏览器授权 → 深链回跳 | `/user-api-key/new` 授权成功，回调 `discourse://auth_redirect` 正常 |
| OTP 兑换 | `POST /session/otp/<token>` → 200；ArkWeb 内会话建立 |
| 登录态 | 「我的」页显示真实账号与等级、统计（访问天数/已读帖子/获赞/发帖数） |
| 首页 | 真实话题列表、头像、时间、未读角标正常 |
| 通知 | 真实通知列表（如 discobot 欢迎私信），含类型图标、相对时间 |

> **HttpOnly cookie 注意**：`_t` 与 `cf_clearance` 都是 HttpOnly，ArkWeb 的
> `WebCookieManager.fetchCookieSync` 只返回 Cookie 头字符串、读不到 HttpOnly cookie。
> OHOS 上请求被迫走 ArkWeb 网络栈（webview adapter）才能携带它们，因此：
> - OTP 兑换后不再以「jar 里是否出现新 `_t`」判定成功，改用
>   `/session/current.json`（同一 webview 通道）验证会话；
> - 账号密码登录不再要求 jar 里已有 `cf_clearance`（ArkWeb 自带）。
> 相关修复见提交 `fix(ohos): 登录链路适配 HttpOnly cookie`。

## 3. 未覆盖项

| 场景 | 原因 |
|---|---|
| 发帖/回复的真实提交与审核 | 未在社区实际发帖（仅 mock 验证过写入链路） |
| 收藏、关注、消息中心的真实交互 | 未逐项验证 |
| 通知实际弹出（系统通知） | 需在系统设置里允许通知，未验证 |
| 后台保活运行 | 未在真实登录态下长时间验证（API 已用探针验证 `started/stopped`） |

## 4. 复现命令

```powershell
# 构建 + 安装 + 启动（真机，需已配置 DevEco 自动签名）
cd tools\ohos
.\build-device-release.ps1

# 拉取应用日志
hdc file recv /data/app/el2/100/base/com.fluxdo.app/files/flutter/logs/app_log.jsonl .\app_log.jsonl

# 截图
hdc shell snapshot_display -f /data/local/tmp/s.jpeg
hdc file recv /data/local/tmp/s.jpeg .\s.jpeg
```

## 5. 手工测试清单（建议）

按需逐项验证，括号内为关注点：

1. 安装启动（release 无 DEBUG 角标；首屏出列表）
2. 5 个原生库探针（见 §2.2，日志出现即通过）
3. 浏览：首页下拉刷新/无限滚动、详情长图/代码块/引用/楼层跳转
4. 搜索：关键词、排序、进入结果
5. 设置：切换网络引擎（高性能 rhttp）、开关 DOH（看「代理运行中」）、改主题
6. 分享：生成分享图、保存相册（系统授权）、系统分享面板
7. 扫码登录页（相机预览/权限）与浏览器授权页（WebView）
8. 深链 `fluxdo://topic/<id>` 直达
9. 杀进程重启：设置持久化、DOH 自动恢复
10. 登录后（可选，需真实账号）：通知、发帖/回复、收藏、后台保活

## 6. 已知限制（平台差异）

| 限制 | 说明 |
|---|---|
| 未上架应用市场 | 只能侧载；应用内「检查更新」跳浏览器发布页 |
| 应用内更新安装 | HarmonyOS 不允许第三方应用静默安装 HAP |
| 剪贴板「读」富文本 | `READ_PASTEBOARD` 属 system_basic，普通证书无法授予，自动回退纯文本（写图片正常） |
| 登录表单无法「粘贴」密码 | 同为剪贴板读取限制：第三方应用读剪贴板需系统级权限。侧载版建议用「浏览器授权登录」，或在应用内键盘手动输入 |
| 通知 | 需用户在系统设置里手动允许本应用通知 |
| 后台保活 | 数据同步类长时任务单次约 10 分钟，切后台时重新申请（已实现） |
