# FluxDO HarmonyOS 7 真机测试单
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从应用侧 `module.json5` 删除（最终包仍由依赖 HAR 带入，见 README.md）。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 版本：FluxDO 0.2.29（bundle `com.fluxdo.app`，`compatibleSdkVersion 26.0.0`）
> 产物：`.cache/ohos-build/fluxdo-release-ohos-arm64-unsigned.hap`（114.1 MB，arm64）
> 关联文档：`README-ohos.md`（交付说明）、`docs/ohos-acceptance.md`（模拟器验收 A1–A44）

---

## 0. 前置条件

| 项 | 要求 | 检查方式 |
|---|---|---|
| 设备系统 | **HarmonyOS 7（API 26）** 或更高；API < 26 无法安装（`compatibleSdkVersion 26.0.0`） | 设备「设置 → 关于本机」查看版本 |
| 开发者模式 | 已开启，USB 调试已授权 | `hdc list targets` 能看到设备序列号 |
| 架构 | arm64（真机），已产出 `ohos-arm64` 包 | HAP 内 `libs/arm64-v8a/libflutter.so` 存在 |
| 工具 | DevEco Studio 26 装在**无空格路径**（本机 `C:\Users\iceblock\DevEcoStudio`）、本仓库 `tools/` | `hdc -v` 正常 |

```powershell
# 连接检查（换成实际序列号）
hdc list targets
hdc -t <序列号> shell bm get -u        # 取设备 UDID（签名白名单要用）
```

---

## 1. 签名与安装（两条路径，按设备类型选）

### 路径 A：开发板 / OpenHarmony 设备（信任 OpenHarmony 根证书）

一条命令完成「构建 arm64 → 自动取设备 UDID 签 debug profile → 安装 → 启动」：

```powershell
cd C:\Users\iceblock\fluxdo
.\tools\build-ohos.ps1 -Mode release -Arch ohos-arm64 -Device auto -Install -Launch
```

- `-Device auto` 自动选择第一个已连接设备（脚本已支持；默认值仍是模拟器 `127.0.0.1:5555`）；
- 签名 UDID 由 `tools/ohos-sign.ps1` 从**当前连接的设备**读取，无需手填；
- 产出：`.cache/ohos-build/fluxdo-release-ohos-arm64-signed.hap`。

### 路径 B：商用 HarmonyOS 设备（需华为开发者证书）

商用设备不信任 OpenHarmony 默认根证书，需用 DevEco Studio 的自动签名（要求登录华为账号）：

1. DevEco Studio 打开 `repo/ohos` 工程；
2. `File → Project Structure → Signing Configs` → 勾选 **Automatically generate signature**（会写入 `signingConfigs`）；
3. 直接 `Build → Build Hap(s)`，或在工程根执行：
   ```powershell
   cd repo\ohos
   .\hvigorw assembleHap -p product=default -p buildMode=release --no-daemon
   ```
4. 用 DevEco 的 `Run` 直接部署到设备，或手动安装：
   ```powershell
   hdc -t <序列号> install -r entry\build\default\outputs\default\entry-default-signed.hap
   ```

> ⚠️ 注意：DevEco 自动签名会往 `repo/ohos/build-profile.json5` 写入 `signingConfigs`（含加密密码），
> 之后再跑 `tools/build-ohos.ps1` 会在 SignHap 阶段报
> `No permission write to signConfigCheckJson.json`。跑脚本前请把该字段恢复为空数组 `[]`（文件内有注释说明）。

> ✅ 前置已就绪（2026-10-22 验证）：
> - DevEco 已重装到无空格路径 `C:\Users\iceblock\DevEcoStudio`，工具链引用已同步更新；
> - `repo/ohos/build-profile.json5` 的 `targetSdkVersion` 已从错误的 `"1"` 修正为 `"26.0.0"`（提交 `bcd6680`）；
> - `hvigorw --sync -p product=default` 实测 **exit=0**，`File → Project Structure` 可正常打开配置签名；
> - `flutter build hap --release --target-platform ohos-arm64` 实测通过（114.1 MB，85.6s）。

### 安装后自检

```powershell
hdc -t <序列号> shell aa start -a EntryAbility -b com.fluxdo.app
hdc -t <序列号> shell snapshot_display -f /data/local/tmp/t0.jpeg
hdc -t <序列号> file recv /data/local/tmp/t0.jpeg ./t0.jpeg
```

---

## 2. 冒烟测试（5 分钟内，必须先过）

| # | 检查项 | 期望 | 证据采集 |
|---|---|---|---|
| S1 | 应用能安装并启动，无闪退 | 进入首页话题列表 | 截图 `t0.jpeg` |
| S2 | 冷启动首屏（断网/弱网下也应出骨架或缓存） | 3 秒内出列表或加载态 | 录屏/截图 |
| S3 | 应用日志存在且时间区正确 | `timezone_resolved timezone=Asia/Shanghai` | 见 §4 拉日志 |
| S4 | 5 个原生库加载成功 | 见下表 5 条日志 | 见 §4 |
| S5 | 列表滚动、图片/头像加载 | 无错位、无大面积占位 | 截图 |

**S4 判定标准（应用内 JSONL 日志，缺一条即记为不通过）**

| 能力 | 期望日志 |
|---|---|
| rhttp（Rust 网络栈） | `{"type":"rhttp","event":"rhttp_init","result":"ok"}` |
| 动图解码 | `{"type":"image","event":"native_animated_codec","result":"ok","version":"0.3.2"}` |
| AVIF 解码 | `{"type":"image","event":"avif_probe","result":"native-ok","detail":"w=… h=… rgba=…"}` |
| cook JS（QuickJS） | `{"type":"cook","event":"cook_bundle_eval","result":"ok"}` + `cook_global_probe globalType=object` |
| 后台保活（debug 版才有） | `{"type":"background","event":"ohos_continuous_task_probe","state":"started"}` |

---

## 3. 功能测试单

> 说明：模拟器阶段已通过的项目标 ✅（详见 `docs/ohos-acceptance.md`）；**标 🔍 的项因模拟器无账号/无相机，
> 必须真机验证**。每条请记录：通过/失败 + 截图或日志。

### 3.1 账号与登录

| # | 用例 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|
| A1 | 密码登录 | 登录页 →「账号密码」→ 输入账号密码 → 登录 | 登录成功，返回首页并显示头像 | 🔍 |
| A2 | 扫码登录 | 登录页 →「扫码登录」→ 相机预览 → 扫描电脑端二维码 | 预览流畅、识别成功并登录 | 🔍 |
| A3 | 浏览器授权登录 | 登录页 →「浏览器授权」→ 内嵌 WebView 完成授权回调 | 回调 `discourse://auth_redirect` 被应用接管并登录 | 🔍 |
| A4 | 登录态持久化 | 登录后杀进程重启 | 仍为登录态，不重复要求登录 | 🔍 |
| A5 | 退出登录 | 我的 → 设置 → 退出登录 | 回到游客态，后续请求 403 有优雅降级 | 🔍 |

### 3.2 浏览与阅读（模拟器已过，真机复测渲染与流畅度）

| # | 用例 | 期望 | 状态 |
|---|---|---|---|
| B1 | 首页列表（最新/热门/分类切换） | 列表加载、下拉刷新、无限滚动正常 | ✅→真机复测 |
| B2 | 话题详情（HTML 富文本、代码块、引用、表格） | 渲染正确、无截断 | ✅→真机复测 |
| B3 | 楼层跳转（1/253 楼层导航） | 跳转定位准确 | ✅ |
| B4 | 长按选中文本 → 复制/全选/复制引用 | 选择手柄、菜单可用 | ✅ |
| B5 | 搜索（关键词、结果分页） | 结果正确、可进入话题 | ✅ |
| B6 | 用户主页 / 标签页 / 分类页 | 数据加载正常 | 🔍（需登录态更完整） |
| B7 | 深链 `fluxdo://topic/123` | 直接打开对应话题 | ✅ |
| B8 | 返回栈、手势返回 | 行为与系统一致 | 🔍 |

### 3.3 图片与媒体

| # | 用例 | 期望 | 说明 |
|---|---|---|---|
| C1 | 正文图片 / 头像加载 | 正常显示、可点开大图 | ✅ |
| C2 | GIF / 动图表情 | 动画播放流畅（原生解码库） | 🔍 真机确认帧率与内存 |
| C3 | AVIF 图片 | 正常显示（自编 libavif+dav1d） | 🔍 找含 AVIF 的帖子验证 |
| C4 | 图片查看器：缩放、保存到相册 | 保存后系统相册可见 | ✅（模拟器已弹授权框） |
| C5 | 复制图片到剪贴板 | 提示「图片已复制」，可粘贴到其他应用 | 🔍（模拟器已验证写入 ok） |

### 3.4 内容创作（必须登录，模拟器未覆盖）

| # | 用例 | 期望 | 状态 |
|---|---|---|---|
| D1 | 新建话题（标题+正文+分类+标签） | 发布成功并跳转到新话题 | 🔍 |
| D2 | 回复话题 / 引用回复 | 回复出现在楼层末尾 | 🔍 |
| D3 | 编辑自己的帖子 | 编辑后内容更新 | 🔍 |
| D4 | 富文本编辑器：加粗/斜体/代码块/列表 | 工具栏插入正确 Markdown | 🔍 |
| D5 | 从剪贴板粘贴富文本 | 有 HTML 时转 Markdown 插入（无权限则纯文本） | 🔍 见 §5 限制 |
| D6 | 上传图片（相册/拍照） | 上传进度正常、图片插入正文 | 🔍 |
| D7 | 语音/附件（若入口存在） | 权限弹窗正确、上传成功 | 🔍 |
| D8 | 草稿保存与恢复 | 退出再进草稿仍在 | 🔍 |

### 3.5 通知与后台（真机重点）

| # | 用例 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|
| E1 | 通知授权 | 首次进「我的」或收到通知时 | 系统通知开关可正常开启（**需手动在设置里打开本应用通知**） | 🔍 |
| E2 | 本地通知展示 | 登录后触发一条通知（如被回复） | 通知栏可见，点击进入对应话题 | 🔍 |
| E3 | 后台保活 | 登录 → 切后台 5 分钟 | 期间轮询继续（日志有请求），10 分钟内无被杀 | 🔍 |
| E4 | 回前台恢复 | 从后台切回 | 立即刷新列表、无白屏 | 🔍 |

### 3.6 网络与设置

| # | 用例 | 期望 | 状态 |
|---|---|---|---|
| F1 | 网络引擎切换（标准/高性能/兼容/自定义） | 切换后请求仍正常（高性能=rhttp） | 🔍（模拟器点击受限） |
| F2 | 上游代理（HTTP/SOCKS5）配置 | 配置后经代理访问，错误配置有提示 | 🔍 |
| F3 | DNS over HTTPS 开关 | 开启后本地 DOH 网关启动、请求正常 | 🔍 |
| F4 | Cloudflare 挑战 | 冷启动 linux.do 能自动过盾 | ✅（模拟器零点击通过） |
| F5 | 数据管理（缓存统计/清理） | 统计真实、清理生效 | ✅ |
| F6 | 外观（主题/字号/语言） | 立即生效并持久化 | ✅ |
| F7 | 深色模式 | 全页面跟随系统/手动切换 | 🔍 |

### 3.7 分享与导出

| # | 用例 | 期望 | 状态 |
|---|---|---|---|
| G1 | 分享图片（生成分享长图） | 生成成功、可保存/分享 | ✅ |
| G2 | 系统分享面板（分享话题链接） | 调起系统分享、能选择应用 | ✅ |
| G3 | 导出 Markdown 文件 | 保存到文件管理器、内容正确 | ✅ |
| G4 | 另存为（file_picker） | 系统保存器可用、文件落盘 | ✅ |
| G5 | 应用内更新检查 | 有新版时弹窗，点击跳浏览器发布页 | 🔍 见 §5 限制 |

### 3.8 异常与稳定性

| # | 用例 | 期望 |
|---|---|---|
| H1 | 飞行模式启动/切换网络 | 有离线提示、恢复后自动重试 |
| H2 | 快速切换页面 30 次 | 无崩溃、无明显掉帧 |
| H3 | 长时间停留详情页（10 分钟） | 内存稳定、无 ANR |
| H4 | 横竖屏/分屏（若设备支持） | 布局自适应、不重叠 |
| H5 | 低电量/后台被杀后恢复 | 冷启动能恢复登录态与页面 |

---

## 4. 证据采集命令

```powershell
$d = '<序列号>'   # 真机序列号

# 截图
hdc -t $d shell snapshot_display -f /data/local/tmp/shot.jpeg
hdc -t $d file recv /data/local/tmp/shot.jpeg .\shot.jpeg

# 应用 JSONL 日志（时区/原生库/网络请求/错误都在这）
hdc -t $d file recv /data/app/el2/100/base/com.fluxdo.app/files/flutter/logs/app_log.jsonl .\app_log.jsonl

# 系统日志（按自定义 TAG 过滤）
hdc -t $d shell hilog -x > hilog.txt
#   然后在本机搜索：FluxdoBridge / flutter / com.fluxdo.app

# 崩溃与冻结日志（若发生）
hdc -t $d file recv /data/log/faultlog/faultlogger .\faultlogger

# 应用信息
hdc -t $d shell bm dump -n com.fluxdo.app | findstr /i "version allowEnableNotification"
```

> JSONL 中重点关注字段：`"level":"warning"/"error"`、`event`（`rhttp_init` / `native_animated_codec` /
> `avif_probe` / `cook_bundle_eval` / `ohos_continuous_task*` / `ohos_clipboard_probe` / `cf_challenge`）。

---

## 5. 已知限制（真机上同样存在，属平台语义差异，不算缺陷）

| 限制 | 原因 | 应用行为 |
|---|---|---|
| 应用内更新安装 | HarmonyOS 不允许第三方应用静默安装 HAP | 检查更新后打开浏览器发布页 |
| 剪贴板「读」富文本 | `ohos.permission.READ_PASTEBOARD` 为 system_basic 级，普通证书无法授予 | 自动回退纯文本粘贴（写图片正常） |
| 通知需手动开启 | 系统侧 `allowEnableNotification` 默认关闭 | 引导用户到设置开启 |
| 后台保活有时长上限 | 数据同步类长时任务单次约 10 分钟 | 每次切后台重新申请，超时后轮询暂停 |

---

## 6. 问题回报模板

```text
【模块】例如：话题详情
【用例编号】B2
【设备】型号 / HarmonyOS 版本 / UDID
【构建】release-ohos-arm64，提交 <git commit>
【现象】具体描述 + 复现步骤 1-2-3
【期望】
【日志】app_log.jsonl 相关行 / hilog 片段（脱敏）
【截图】shot.jpeg
```

---

## 7. 通过标准

1. §2 冒烟 5 项全过（尤其 5 个原生库日志齐全）；
2. §3 中 🔍 项无「阻断级」失败（登录、发帖/回复、通知、图片、扫码）；
3. §3.8 稳定性无崩溃/ANR；
4. 已知限制项行为与 §5 描述一致（不出现新问题）。

---

## 8. 真机实战记录（2026-10-22）

| 项 | 值 |
|---|---|
| 设备 | **HBN-AL00** |
| 系统 | **HarmonyOS 7.0.0.109(SP8C00E105R5P2)**，API **26**（与 `compatibleSdkVersion` 匹配） |
| UDID | `884FFA9A007A036C5A3955210C618F4F1256D0D327C6A3E70666CB4C9C10E88B` |
| 安装结果 | **install bundle successfully** |
| 运行结果 | 首页列表正常（深色模式、头像/标签/回复数），**无 DEBUG 角标**（release + AOT） |

### 签名：真机必须用华为证书（OpenHarmony 默认证书会被拒）

第一次用 `tools/ohos-sign.ps1`（OpenHarmony 默认证书链）签名后安装失败：

```
error: failed to install bundle. code:9568257 error: fail to verify pkcs7 file
```

原因：商用 HarmonyOS 设备只信任华为开发者证书链。正确做法（本次已验证）：

1. DevEco Studio **登录华为账号** → `File → Project Structure → Signing Configs` →
   勾选 **Automatically generate signature** → Apply。
   会生成/刷新 `C:\Users\iceblock\.ohos\config\default_ohos_*` 系列证书文件，
   并写入 `repo/ohos/build-profile.json5` 的 `signingConfigs`（含加密密码）。
2. 确认 `products[0]` 有 `"signingConfig": "default"`（没有就手工加一行）。
3. 用 hvigor 原生签名构建 release（**不要**再用手工 OpenHarmony 签名）：

```powershell
cd C:\Users\iceblock\fluxdo
.\tools\build-device-release.ps1                  # 构建 release + 签名 + 安装 + 启动
.\tools\build-device-release.ps1 -BuildOnly        # 只构建
.\tools\build-device-release.ps1 -Device 2NP0...   # 指定设备
```

产物：`repo/ohos/entry/build/default/outputs/default/entry-default-signed.hap`
（**204.8 MB**，双 ABI release，华为调试证书签名）。

### 已核验的 Profile 内容（hap-sign-tool verify-profile）

```json
{
  "type": "debug",
  "bundle-info": { "bundle-name": "com.fluxdo.app", "apl": "normal" },
  "debug-info": {
    "device-ids": [
      "454D55057494E058383609D94A75277F44F029C4E9A784E7E4F9600000000000",
      "884FFA9A007A036C5A3955210C618F4F1256D0D327C6A3E70666CB4C9C10E88B"
    ],
    "device-id-type": "udid"
  },
  "issuer": "app_gallery"
}
```

→ 同时包含模拟器与真机 UDID，两台设备都能装。

### 两种构建方式的分工

| 场景 | 工具 | 签名 |
|---|---|---|
| 模拟器 / OpenHarmony 开发板 | `tools/build-ohos.ps1`（flutter build hap） | OpenHarmony 默认证书（`tools/ohos-sign.ps1`） |
| **商用 HarmonyOS 真机** | `tools/build-device-release.ps1`（hvigor assembleHap） | **华为调试证书**（DevEco 自动生成，hvigor SignHap 完成） |

> ⚠️ 用了 DevEco 自动签名后，`build-profile.json5` 会含 `signingConfigs`（加密密码、机器相关）。
> 此时不要再跑 `build-ohos.ps1`（它假设签名配置为空）。
