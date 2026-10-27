# FluxDO HarmonyOS 真机验证报告
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从 `module.json5` 删除。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 设备：**HBN-AL00**（HUAWEI），系统 **HarmonyOS 7.0.0.109(SP8C00E105R5P2)**，API **26**
> UDID：`884FFA9A007A036C5A3955210C618F4F1256D0D327C6A3E70666CB4C9C10E88B`
> 构建：release（AOT），华为调试证书签名，**204.9 MB**（双 ABI），`hdc install` 成功
> 验证时间：2026-10-22 ~ 10-23

## 一、总体结论

核心功能在真机上可用：安装、启动、浏览、详情、搜索、设置、网络引擎切换、DOH 加密 DNS、
分享图片/系统分享、相册保存、5 个自建原生库加载全部通过。

真机测试还发现并修复了 1 个 emulator 阶段没暴露的 bug（见第四节）。

## 二、已验证项（附证据）

### 2.1 安装与启动

| 项 | 结果 |
|---|---|
| 签名 | OpenHarmony 默认证书被拒（`9568257 fail to verify pkcs7 file`）→ 改用 DevEco 华为自动签名 |
| 安装 | `install bundle successfully` |
| 冷启动 | **0.9 s** 进程就绪；首屏列表随即出现 |
| 版本标识 | 界面无 DEBUG 角标（release + AOT 确认） |
| 进程稳定性 | 多轮启停、切前后台无崩溃（faultlogger 无记录） |

### 2.2 5 个自建原生库（arm64 真机）

| 能力 | 日志证据 |
|---|---|
| rhttp（Rust HTTP/2） | `{"type":"rhttp","event":"rhttp_init","result":"ok"}` |
| 原生动图解码 | `native_animated_codec ok version 0.3.2` |
| AVIF（libavif+dav1d） | `avif_probe native-ok w=1204 h=800 rgba=3852800` |
| QuickJS cook 渲染 | `cook_bundle_eval ok 567467B / 54–68ms` + `cook_global_probe object` |
| DOH 代理（FFI 进程内） | `[DOH] 使用 FFI 启动代理，模式: DoH 网关` / `FFI 代理已启动，端口: 41463` |
| 时区桥 | `timezone_resolved America/Los_Angeles`（真机系统时区正确） |

### 2.3 浏览与详情

- 首页列表：主题/标签/作者/头像/回复数/点赞数/时间全部正常；下拉刷新、无限滚动正常
- 话题详情：标题、分类标签、统计（回复/浏览/时间）、楼层号、引用块、行内代码、代码块、
  列表、链接预览卡片（带图）、大图、嵌套回复（"回复某楼"徽标）、客户端标识（来自 iPhone/iPad）、
  表情反应栏（带计数）、楼层进度（1/262、2/16）
- 用户主页弹出卡片（信任等级、徽章、加入时间、数据统计）正常

### 2.4 搜索

- 右上角放大镜进入搜索页，占位提示 `搜索 @用户 #分类 tags:标签`
- 软键盘输入 "HarmonyOS" → 搜索 → **50 条结果**，支持「相关性」排序，结果含摘要/作者/标签/时间

### 2.5 设置

设置树完整：外观设置 / 阅读设置 / 网络设置 / 功能设置 / 底栏设置 / 数据管理 / Notion 同步 / 关于 FluxDO

网络设置内：
- **网络引擎**：标准 / 高性能 / 兼容 / 自定义（切换「高性能」生效，提示"使用 rhttp 引擎（HTTP/2 · Rust）"，切换后列表加载正常）
- **DNS over HTTPS**：开关 + 状态「代理运行中 · 端口 41463」+ 设备独有证书开关 + 更多设置（服务器/IPv6/ECH）
- 上游代理（HTTP/SOCKS5/Shadowsocks）
- 辅助：VPN 自动切换、VPN 判定方式、自动触发 CF 验证

### 2.6 分享与媒体

- 「生成分享图片」：生成带主题预览的分享卡（6 种配色：经典/纯白/深色/纯黑/蓝调/绿野）
- 「保存到相册」：正确弹出系统授权「允许"FluxDO"保存 1 张图片？」（saver_gallery 链路 OK）
- 「分享」：正确调起**系统分享面板**（分享 1 项 209.08 KB；华为分享/微信/QQ/我的华为/备忘录/网易… 及 复制/保存至图库/打印 等操作）

### 2.7 设置持久化

force-stop 后重启：
- DOH 自动恢复并在启动时拉起（`[DOH] FFI 代理已启动，端口 41463`）
- 网络引擎选择保持「高性能」
- 5 个原生库探针全部重新通过

## 三、尚未覆盖（需要登录账号）

### 3.1 无账号也能验证的登录相关界面（已测）

| 项 | 结果 |
|---|---|
| 登录页渲染 | 完整：LOGO/口号/用户名密码/记住密码/忘记密码/登录/或/扫码登录/浏览器授权登录/其他方式登录 |
| 扫码登录页 + 相机 | 相机权限弹窗正常；授权后 **实时相机预览 + 扫码框** 正常（mobile_scanner OHOS 通过） |
| 浏览器授权登录 | 应用内 WebView 正常加载 linux.do 登录页（Google/GitHub/Discord 入口、社区准则横幅、地址栏/刷新/标签页） |
| 深链 | `fluxdo://topic/3057096` → `aa start ... -U` 直接打开对应话题（1/536），标题/楼层正确 |

### 3.2 仍需真实账号的流程（未验证）

| 场景 | 说明 |
|---|---|
| 密码 / 扫码 / 浏览器授权登录 | 需要真实账号与扫码端 |
| 发帖、回复、编辑、草稿 | 需要登录 |
| 通知授权与推送展示 | 登录后 `BackgroundNotificationService.enable()` 才触发 |
| 后台保活（长时任务） | 同上；模拟器阶段已用 debug 探针验证 API 可用 |
| 收藏、关注、消息中心 | 需要登录 |

## 四、真机发现并修复的问题

### Bug：DOH 报「找不到代理可执行文件」

- 现象：真机开启 DNS over HTTPS → 提示「找不到代理可执行文件」
- 根因：`DohProxyFfi.isAvailable` 的平台列表漏了 HarmonyOS，导致
  `DohProxyService` 回退到「外部可执行文件」模式（OHOS 只有随 HAP 打包的 `.so`）
- 修复：`isAvailable` 增加 `PlatformUtils.isOhos`（提交 `efc870b`）
- 验证：修复后 `[DOH] 使用 FFI 启动代理` + 端口显示 + 重启自动恢复

## 五、Mock 联调（无账号验证登录后链路）

因为没有 linux.do 账号，用本地 mock 服务补齐了「登录态 → 通知 → 发帖/回复」的验证。

### 5.1 方案

1. `tools/mock-discourse/server.py`：最小 Discourse mock，关键点
   - 首页 `/` 返回带 **`<script id="data-preloaded">`** 的 HTML（外层 JSON + 内层 JSON
     字符串双层结构），其中 `currentUser` 让应用直接进入登录态；
   - 所有响应带 `Set-Cookie: _t=mocktoken; cf_clearance=mockcf`；
   - 覆盖 `/session/current.json`、`/latest.json`、`/t/{id}.json`、`/notifications`、
     `/posts.json`、`/topics.json`、`/u/{username}.json`、`/message-bus/*` 等；
   - 每个请求打日志，PC 侧可直接确认应用真的打到了 mock。
2. 真机通过 `hdc rport tcp:8080 tcp:8080` 把 `127.0.0.1:8080` 反向转发到 PC。
3. 构建时注入 `--dart-define=FLUXDO_BASE_URL=http://127.0.0.1:8080`
   （`tools/build-device-release.ps1 -BaseUrl http://127.0.0.1:8080`）。

### 5.2 验证结果

| 项 | 结果 |
|---|---|
| 登录态首页 | 显示 mock 话题列表；右上角出现通知铃铛、右下角出现发帖 FAB（登录态 UI） |
| 我的页面 | Mock 测试用户 @mockuser、L3 活跃用户、统计卡片、私信/聊天/待审/徽章/信任要求/邀请链接 全部渲染 |
| 通知列表 | 3 条通知（@提及 / 回复 / 点赞），含类型图标、未读蓝点、相对时间 |
| 发帖编辑器 | 标题（字数限制提示）、正文（Markdown）、字数补丁提示、分类选择、标签、预览、Markdown 工具栏全部正常 |
| 分类选择 | 显示 mock 分类（需 `permission <= 1` 才可发帖） |
| 写入请求 | **`POST /posts.json` 200**（mock 日志：`create post topic=1001 raw_len=27`），应用随后跳到话题详情并展示「我」徽章 |
| 话题详情 | 楼层号、`我`/`主` 徽章、回复/更多按钮、楼层进度 1/12 正常 |

> mock 只验证了「应用请求构造 + 解析 + UI 渲染」链路；真实服务端行为（权限、审核、
> CF 盾等）仍需真实账号验证。

## 六、复现命令

```powershell
# 一键构建 release（华为签名）+ 安装 + 启动
cd C:\Users\iceblock\fluxdo
.\tools\build-device-release.ps1

# mock 联调：先起 mock + 端口转发，再带 BaseUrl 构建
python tools/mock-discourse/server.py --port 8080
hdc -t 2NP0224724003561 rport tcp:8080 tcp:8080
.\tools\build-device-release.ps1 -BaseUrl http://127.0.0.1:8080
# 测完记得换回正常构建：.\tools\build-device-release.ps1

# 拉取应用日志（JSONL）
hdc -t 2NP0224724003561 file recv `
  /data/app/el2/100/base/com.fluxdo.app/files/flutter/logs/app_log.jsonl .\app_log.jsonl

# 截图
hdc -t 2NP0224724003561 shell snapshot_display -f /data/local/tmp/s.jpeg
hdc -t 2NP0224724003561 file recv /data/local/tmp/s.jpeg .\s.jpeg
```

## 六、截图索引（`.cache/`）

| 文件 | 内容 |
|---|---|
| `dev-shot1.jpeg` | 真机首屏（release，深色） |
| `dev-t1-detail.jpeg` | 话题详情（标签/统计/引用/行内代码） |
| `dev-t2-scroll.jpeg` | 详情滚动（表情反应栏/嵌套回复/楼层 1/262） |
| `dev-r9-results.jpeg` | 搜索结果（50 条） |
| `dev-r15-profile.jpeg` | 我的（未登录） |
| `dev-r16-settings.jpeg` | 应用设置总览 |
| `dev-r17-network.jpeg` / `dev-d1-doh.jpeg` | 网络设置 / DOH 运行中（端口 41463） |
| `dev-e1-engine.jpeg` | 高性能（rhttp）引擎已选 |
| `dev-sh1.jpeg` | 分享图片预览（6 主题） |
| `dev-g1-save.jpeg` | 保存相册系统授权弹窗 |
| `dev-sh2-share.jpeg` | 系统分享面板 |
| `dev-l1-login.jpeg` | 登录页 |
| `dev-l2-qr.jpeg` | 扫码登录（相机权限弹窗） |
| `dev-l3-webauth.jpeg` | 扫码页相机实时预览 |
| `dev-l4-webview.jpeg` | 浏览器授权 WebView（linux.do 登录页） |
| `dev-dl1.jpeg` | 深链直达话题 |
| `dev-mk4.jpeg` | mock 登录态首页（通知铃铛 + 发帖 FAB） |
| `dev-mk5-profile.jpeg` | mock 登录态「我的」页 |
| `dev-mk8-notif.jpeg` | mock 通知列表（3 条） |
| `dev-mp2-editor.jpeg` / `dev-mp4-filled.jpeg` | 发帖编辑器（空 / 已填） |
| `dev-mp7-cat.jpeg` | 分类选择器 |
| `dev-mp9-result.jpeg` | 发帖/回复后的话题详情 |
