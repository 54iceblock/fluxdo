# FluxDO × HarmonyOS 7 移植说明（交付版）

> 目标应用：[Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo) v0.2.29（Linux.do 第三方 Flutter 客户端）
> 目标平台：HarmonyOS 7.0.0（API 26），DevEco Studio 26.0，Flutter 3.47.7+ohos（Dart 3.13.5）
> 产物：`com.fluxdo.app` HAP（debug 344 MB / **release 91 MB**）

---

## 1. 一键构建 / 安装 / 启动

> 脚本的**权威版本**现在是 [`ohos/tools/`](../tools/README.md)（已入库）；
> 下面命令里的 `C:\Users\iceblock\fluxdo\tools\` 是本机工作副本路径，两者内容一致。

```powershell
# 环境（每次新终端都要执行）
Set-ExecutionPolicy -Scope Process Bypass -Force
. C:\Users\iceblock\fluxdo\tools\env.ps1

# 构建 + 签名 + 安装 + 启动（debug）
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1 -Install -Launch

# release 构建（AOT，体积小 73%）
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1 -Mode release -Install

# 只构建到 HAP（不装）
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1
```

> 签名口令从 `$env:FLUXDO_SIGN_PWD` 读取（不设时用 OpenHarmony 默认的公开口令
> 123456，仅够调试证书链）；正式证书请勿把口令写回脚本。

产物位置：
- 未签名：`repo\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap`
- 已签名：`.cache\ohos-build\fluxdo-{debug|release}-ohos-x64-signed.hap`

常用 hdc 命令：
```powershell
$hdc='D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets                                  # 设备列表
& $hdc -t 127.0.0.1:5555 install -r <signed.hap>     # 安装
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.app
& $hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/x.jpeg
& $hdc -t 127.0.0.1:5555 file recv /data/local/tmp/x.jpeg .\x.jpeg
```

> 注意：构建工具链（flutter/hvigor/java/hdc）需要能创建子进程的完整权限会话（DSH 沙箱 `workspace-write` 会拒绝，需 `danger-full-access`）。

---

## 2. 交付内容

| 路径 | 内容 |
|---|---|
| `repo/ohos/` | HarmonyOS 工程（bundle `com.fluxdo.app`，API 26，深链 `fluxdo://` `discourse://`，权限声明，`FluxdoBridgePlugin.ets` 自研 ArkTS 桥） |
| `repo/packages/` | 5 个 vendored OHOS 插件：`file_picker`、`share_plus`(+PI)、`flutter_math_fork`、`just_audio_harmonyos`（各含 `VENDOR.md` 来源/TAG/许可证/回滚） |
| `repo/lib/` | 平台适配：`PlatformUtils.isOhos`、`OhosCompat` 能力开关、OHOS UA、Cloudflare 挑战修复、时区桥、剪贴板兜底、file_picker 另存为修复、相机扫码启用、DOH 设置平台守卫 |
| `repo/pubspec.yaml` | OHOS 实现包 + 11 条 git override（**全部锁定 commit SHA**，见 `just check-pubspec`） |
| `repo/ohos/tools/` | 构建/签名/交叉编译脚本（`env.ps1`、`build-ohos.ps1`、`ohos-sign.ps1`、各 `build-*-ohos.sh`、AVIF/QuickJS 的 C 桥…）——此前只在工作区、未入库，现已版本化 |
| `repo/ohos/docs/` | 本目录：15 份移植/上架文档（含修订清单见 [README.md](README.md)） |
| `repo/tool/` | `check_no_secrets.dart`（防签名材料误提交）、`check_ohos_pubspec.dart`（git 依赖必须锁 SHA / 生成跨平台 pubspec） |
| `.cache/ohos-build/` | 已签名 HAP（debug/release）、构建日志 |

代码已提交（工作区干净）：
- `674a99f feat(ohos): 适配 HarmonyOS 7（API 26）移植`
- `97e1c8a feat(ohos): 启用实时相机扫码（扫码登录）`
- `d2dce01 fix(ohos): 隐藏 HarmonyOS 上不可用的 DOH 代理设置项`
- `bac65c2` / `7f6cdd7` / `3e67fcb` / `567cdaf`：2026-10 审核修复（签名材料、
  换行符归一、依赖锁定 SHA、AVIF 主线程阻塞与探针、外链 scheme 校验、死代码清理）
- submodule `packages/fluxdo_render` → `8c18e80`（`TargetPlatform.ohos` 补丁）

---

## 3. 功能状态（模拟器实测）

**已验证可用（34 项）**：构建/签名/安装/启动、release 构建、登录页（账号密码/扫码/浏览器授权入口）、我的页、话题列表、话题详情（HTML/楼层/分页/反应）、搜索、深链、跳转话题、楼层导航、应用设置、网络设置、数据管理（真实缓存统计）、话题菜单、分享图生成、系统分享面板、导出 Markdown、另存为（系统保存器）、保存到相册（系统授权）、相册/正文图片、系统输入法、文本选择（复制/全选/复制引用）、时区（Asia/Shanghai）、相机扫码预览 + CAMERA 权限、CF 冷启动零点击加载。

**已接入原生库（WSL 交叉编译，见 `ohos/tools/build-*-ohos.sh`）**：
- **DOH 代理**（Rust `core/doh_proxy`）→ `libdoh_proxy.so`（x86_64 7.5 MB / arm64 6.6 MB），网络设置恢复「DNS over HTTPS」项；
- **rhttp**（Rust reqwest + flutter_rust_bridge）→ `librhttp.so`（x86_64 7.1 MB / arm64 5.9 MB），设备日志已确认 `rhttp_init=ok`；
- **原生动图解码**（Rust `native_animated_image`）→ `libnative_animated_image_codec.so`（588 KB / 562 KB），设备日志确认 `native_animated_codec=ok, version=0.3.2`；
- **AVIF 解码**（自编 libavif + dav1d）→ `libohos_avif.so`（1.07 MB / 897 KB），设备日志确认 `avif_probe=native-ok, 1204x800 RGBA`。
  ⚠️ 2026-10 起 C 侧支持按 `max_dim` 降采样且解码上限收到 8192，**必须重编 .so**
  （`wsl bash ohos/tools/build-avif-ohos.sh`）才生效；Dart 侧已在常驻后台 isolate 解码；
- **cook JS 渲染**（自编 QuickJS 0.17.0）→ `libohos_quickjs.so`（1.27 MB / 1.19 MB），日志确认 bundle eval 成功（567 KB / 84 ms）且全局 `__fluxdoCook` 可见；
- **富文本剪贴板·写图片**（ArkTS pasteboard）→ PNG→PixelMap→系统剪贴板，日志确认 `clipboard_probe write-ok`（「读」HTML 需 system_basic 权限，相关实现与承诺已移除，粘贴按设计降级纯文本）。

> **后台保活（系统长时任务 DATA_TRANSFER）已整体移除**：会在通知栏常驻条目、
> 收益有限（见 `e63e3be`/`c9578bb`）。切后台交给系统正常挂起，通知走
> notificationManager 即时发布。`KEEP_BACKGROUND_RUNNING` 权限、
> `backgroundModes` 配置均已删除。

**仅剩的、非功能缺陷类差异**：

| 能力 | 现状 | 说明 |
|---|---|---|
| 应用内更新安装 | OHOS 不支持 APK 静默安装 | 检查更新后打开浏览器发布页，由用户自行安装新版 HAP |
| 剪贴板「读」富文本 | `READ_PASTEBOARD` 为 system_basic 权限，普通证书无法授予 | 自动回退纯文本粘贴（写图片已可用） |
---

## 4. 已知环境限制

1. HarmonyOS **系统扩展窗口**（权限弹窗、文件保存器）与**部分 Flutter 底部面板按钮**不接受 `uinput`/`uitest` 注入点击，自动化验证需人工点最后一步；应用侧调用链已验证正确。
2. 模拟器无真实相机：扫码页会弹权限并显示预览区域，扫码识别需真机。
3. 模拟器 IP 触发 Cloudflare 挑战：应用已内置「WebView 网络栈」兜底，冷启动实测可零点击出数据。

---

## 5. 上架/真机前置

> **完整上架计划见 [`ohos-release-plan.md`](ohos-release-plan.md)**（阶段门禁 G0–G7、任务与验收、风险登记、检查清单、待 AGC 后台确认项 Q1–Q8）。

1. 替换为**正式签名证书**（当前用 OpenHarmony 默认证书自签，仅调试可用）。
   ⚠️ 签名材料**不要提交**：`ohos/build-profile.json5` 的 `signingConfigs` 必须为空数组，
   提交前跑 `dart run tool/check_no_secrets.dart`（`just check-secrets`）。
2. `module.json5` 权限已按实际使用收敛到 4 项（INTERNET / GET_NETWORK_INFO /
   CAMERA / MICROPHONE）；`PUBLISH_AGENT_REMINDER` 等未用权限已删除，
   后续新增能力时同步补 `reason` 文案。
3. release 构建已完成（91 MB），可进一步做资源裁剪与 CPU 架构过滤（只保留 arm64 可真机发布）。
   仓库里的 10 个预编译 `.so`（约 31 MB）直接入库，体积敏感时建议改 Git LFS
   或改为 CI/本地 `ohos/tools/build-*-ohos.sh` 现场编译（见 `ohos-native-strategy.md`）。
4. 隐私合规：补充隐私政策、权限使用说明。
5. 跨平台回归：OHOS 的 11 条 `dependency_overrides` 对 Android/iOS/桌面端同样生效，
   发版前用 `dart run tool/check_ohos_pubspec.dart --portable` 生成去掉 OHOS
   override 的 pubspec，跑一遍目标平台构建。

详细技术细节见 `ohos-port-report.md`、`ohos-acceptance.md`。

---

## 真机测试（HarmonyOS 7 / arm64）

**产物**：`.cache/ohos-build/fluxdo-release-ohos-arm64-unsigned.hap`（114.1 MB，arm64，含 5 个原生库）

**一条命令（开发板/OpenHarmony 设备，自动取设备 UDID 签名并安装）**：

```powershell
.\tools\build-ohos.ps1 -Mode release -Arch ohos-arm64 -Device auto -Install -Launch
```

**商用 HarmonyOS 设备**：需用 DevEco Studio 的自动签名（登录华为账号）后部署，
详见测试单 §1 路径 B（并注意 §1 的 `signingConfigs` 恢复提示）。

**测试单**：[`docs/ohos-device-test-plan.md`](docs/ohos-device-test-plan.md)
（前置条件 / 签名安装 / 冒烟 5 项 / 8 大类功能用例 / 证据采集命令 / 已知限制 / 问题回报模板）
