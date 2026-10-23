# FluxDO for HarmonyOS

> **FluxDO 的 HarmonyOS（鸿蒙）移植版** —— 基于上游 [Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo) v0.2.29，
> 目标系统 **HarmonyOS 7（API 26）**。
>
> ⚠️ **本应用未上架华为应用市场（AppGallery）**，只能通过 **侧载（sideload）** 安装，见下方[侧载安装](#侧载安装)。

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](./LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-7%20(API%2026)-green.svg)](https://developer.huawei.com/consumer/cn/harmonyos)

---

## 这个分支是什么

这是 FluxDO（linux.do 第三方客户端，Flutter 开发）的 **HarmonyOS 7 移植分支**。
上游代码保持不动，新增的是 `ohos/` 平台工程与配套的原生库/桥接/构建脚本：

| 能力 | 实现方式 | 状态 |
|---|---|---|
| 应用骨架 / UI | OHOS Flutter 3.47.7（鸿蒙 Flutter SDK） | ✅ 真机验证 |
| 高性能网络引擎 | 自编译 Rust `rhttp`（`librhttp.so`） | ✅ |
| DNS over HTTPS | 自编译 Rust `doh_proxy`（`libdoh_proxy.so`），进程内 FFI 网关 | ✅ 真机「代理运行中」 |
| AVIF 图片 | 自编译 `libavif + dav1d`（`libohos_avif.so`） | ✅ |
| 动图解码 | 自编译 `native_animated_image_codec` | ✅ |
| cook JS 渲染 | 自编译 QuickJS 0.17（`libohos_quickjs.so`，持久上下文） | ✅ |
| 后台保活 | 系统长时任务（`backgroundTaskManager`，DATA_TRANSFER） | ✅ API 验证 |
| 相册保存 / 相机扫码 / 通知 / 剪贴板写图片 | ArkTS 桥 + OHOS 插件端口 | ✅ |
| 其余业务功能 | 上游 Dart 代码，零改动或最小改动 | ✅ 浏览/详情/搜索/设置/分享/深链等 |

原生库已**预编译并提交**在 `ohos/entry/libs/{x86_64,arm64-v8a}/`，**普通构建不需要自己交叉编译**。

---

## 侧载安装

HarmonyOS 对应用签名有硬性要求：**HAP 必须被设备信任的证书签名才能安装**。
商用 HarmonyOS 设备只信任**华为开发者证书**，且调试证书的 Profile 里绑定了**设备 UDID** ——
所以「别人签好的包」在你自己的手机上通常装不上（报 `9568257 fail to verify pkcs7 file`）。

因此正确姿势是：**用你自己的华为开发者账号签名，再安装**。

### 0. 前置准备

1. 一台 **HarmonyOS 7（API 26）** 或更高版本的设备；
2. 设备上开启 **开发者模式**：设置 → 关于本机 → 连续点击版本号 7 次；
3. 开启 **USB 调试**：设置 → 系统和更新 → 开发人员选项 → USB 调试；
4. 电脑安装 **DevEco Studio 26**（自带 `hdc`、`hvigor`、SDK），或用 command-line tools 提供 `hdc`；
5. USB 连接手机，手机弹窗选「允许调试」，确认：

```bash
hdc list targets
# 输出设备序列号即成功
```

### 方式 A：DevEco Studio 自动签名（推荐，最简单）

1. 用 DevEco Studio 打开本仓库的 **`ohos/` 目录**（不是仓库根目录）；
2. 首次打开等待右下角 **Sync** 完成；
3. 右上角登录**华为账号**（实名认证过的开发者账号）；
4. 菜单 `File → Project Structure → Signing Configs`，勾选 **Automatically generate signature**，点 OK；
   - 这一步会自动生成华为调试证书与 Profile（绑定当前连接的设备 UDID），
     并写入 `ohos/build-profile.json5` 的 `signingConfigs`；
5. 菜单 `Build → Build Hap(s)/APP(s) → Build Hap(s)`（中文界面为 **构建 → 编译 Hap(s)/APP(s) → 编译 Hap(s)**）；
6. 构建产物：

```
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

7. 安装并启动：

```bash
hdc -t <设备序列号> install -r ohos/entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <设备序列号> shell aa start -a EntryAbility -b com.fluxdo.app
```

> 也可以直接在 DevEco 里点 **Run ▶** 安装（注意 Run 装的是 debug 包）。

### 方式 B：命令行构建 + 安装（开发者）

前提：已按方式 A 第 4 步生成过自动签名配置（`ohos/build-profile.json5` 里有 `signingConfigs`）。

```powershell
# 仓库根目录执行
cd tools\ohos
.\build-device-release.ps1                      # 构建 release（华为证书签名）+ 安装 + 启动
.\build-device-release.ps1 -BuildOnly           # 只构建，产物为 entry-default-signed.hap
.\build-device-release.ps1 -Device <序列号>      # 多设备时指定
```

脚本会自动定位 DevEco（可用环境变量 `DEVECO_HOME` 覆盖）并调用 hvigor。

### 方式 C：Release 资产里的现成包

 Releases 页面提供两类产物：

| 资产 | 适用设备 | 说明 |
|---|---|---|
| `fluxdo-ohos-arm64-unsigned.hap` | 真机（arm64） | **未签名**，需按方式 A/B 用你自己的证书签名后安装 |
| `fluxdo-ohos-x64-signed.hap` | 模拟器（x86_64） | 用 OpenHarmony 默认证书链签名，可直接装到 DevEco 模拟器 |

安装：

```bash
hdc -t <设备序列号> install -r fluxdo-ohos-arm64-unsigned.hap    # 仅签名后可用
hdc -t 127.0.0.1:5555 install -r fluxdo-ohos-x64-signed.hap      # 模拟器
```

### 方式 D：OpenHarmony 开发板 / 模拟器

OpenHarmony 设备信任 OpenHarmony 默认证书链，可直接用仓库脚本签名安装：

```powershell
cd tools\ohos
.\build-ohos.ps1 -Mode release -Arch ohos-arm64 -Install -Launch   # 开发板（arm64）
.\build-ohos.ps1 -Mode debug -Arch ohos-x64 -Install -Launch       # 模拟器（x86_64）
```

---

## 从源码构建

### 依赖

| 依赖 | 版本 / 说明 |
|---|---|
| DevEco Studio | **26.x**（自带 OpenHarmony SDK **API 26**、hvigor 6.26.4、hdc、jbr） |
| HarmonyOS Flutter SDK | **3.47.7+ohos**（`flutter --version` 需带 `ohos` 支持），并确保 `flutter` 在 PATH |
| Windows | PowerShell 7+（脚本为 `.ps1`） |
| （可选）WSL Ubuntu 24.04 | 仅在需要重新交叉编译原生库时使用 |

### 步骤

```powershell
# 1. 拉代码
git clone https://github.com/<your-fork>/fluxdo.git
cd fluxdo

# 2. 取 Dart 依赖
flutter pub get

# 3. 配置环境（DevEco 路径、SDK 等）
. .\tools\ohos\env.ps1
#   如 DevEco 不在默认路径，先设置：
#   $env:DEVECO_HOME = 'D:\DevEco Studio'

# 4. 构建（真机 release，需要先按方式 A 配好自动签名）
cd tools\ohos
.\build-device-release.ps1 -BuildOnly

#    或构建模拟器包（OpenHarmony 证书，无需华为账号）
.\build-ohos.ps1 -Mode release -Arch ohos-x64
```

> 首次构建前请确认 `ohos/build-profile.json5` 中 `signingConfigs` 为你自己的签名配置
> （仓库默认留空；用 DevEco 自动签名后会写入，**不要提交自己的证书与密码**）。

### 原生库

5 个原生库已预编译提交（`ohos/entry/libs/<abi>/*.so`），**无需自己编译**。
如需重新交叉编译（升级依赖或改原生代码），见 [`docs/ohos/architecture.md`](./docs/ohos/architecture.md)：
在 WSL 内用 OHOS NDK sysroot + clang/lld 编译，脚本为 `tools/ohos/build-*.sh`。

---

## 常见问题（侧载失败排查）

| 报错 / 现象 | 原因 | 解决 |
|---|---|---|
| `error: failed to install bundle. code:9568257 error: fail to verify pkcs7 file` | 签名证书不是设备信任的（用了别人的/OpenHarmony 证书），或 Profile 未包含本机 UDID | 用自己的华为账号做「自动签名」（方式 A），确保签名时设备已连接 |
| `install failed due to grant request permissions failed` | 应用声明了 system_basic 级权限（本移植已移除 `READ_PASTEBOARD` 等受限权限） | 使用本仓库构建产物即可 |
| `hdc list targets` 为空 | 未开 USB 调试 / 未在手机上点「允许调试」/ 数据线仅充电 | 重新插拔，手机上确认授权弹窗 |
| `The type of the target device does not match` / API 版本不符 | 设备系统低于 **API 26（HarmonyOS 7）** | 升级系统；本移植 `compatibleSdkVersion 26.0.0` |
| 打开 DevEco 后 `Project Structure` 灰色 | 工程 sync 失败（`build-profile.json5` 的 SDK 版本/签名配置不合法） | 参照 [`docs/ohos/build.md`](./docs/ohos/build.md#5-常见问题) |
| 构建报 `No permission write to signConfigCheckJson.json` | DevEco 写入了 `signingConfigs`，同时脚本又用 OpenHarmony 证书签名 | 真机签名走 `build-device-release.ps1`；模拟器/开发板走 `build-ohos.ps1`，二者不要混用 |
| 通知不弹出 | 系统侧应用通知开关默认关闭 | 设置 → 通知 → 允许 FluxDO 通知 |
| 应用内更新按钮跳浏览器 | HarmonyOS 不允许第三方应用静默安装 HAP（平台限制） | 从 Releases 下载新版本，按上述方式重新侧载 |

更多：真机验证记录见 [`docs/ohos/device-test.md`](./docs/ohos/device-test.md)，
构建细节与排错见 [`docs/ohos/build.md`](./docs/ohos/build.md)。

---

## 已知限制（平台语义差异，非缺陷）

1. **未上架应用市场**：只能侧载；应用内「检查更新」会跳转浏览器发布页。
2. **应用内更新安装**：HarmonyOS 不允许第三方应用静默安装 HAP。
3. **剪贴板「读」富文本**：`ohos.permission.READ_PASTEBOARD` 属 system_basic 级权限，普通证书无法授予，
   自动回退为纯文本粘贴（写图片不受影响）。
4. **通知**：需要用户在系统设置里手动允许本应用通知。
5. **后台保活**：数据同步类长时任务单次约 10 分钟，需在每次切后台时重新申请（已实现）。

## 文档索引

| 文档 | 内容 |
|---|---|
| [`docs/ohos/`](./docs/ohos/README.md) | 移植文档总入口 |
| [`architecture.md`](./docs/ohos/architecture.md) | 移植架构：平台工程、5 个原生库、ArkTS 桥、Dart 适配、Cloudflare 处理 |
| [`build.md`](./docs/ohos/build.md) | 构建 / 签名 / 安装 / DevEco 与签名排错 |
| [`device-test.md`](./docs/ohos/device-test.md) | 真机已验证项、未覆盖项、测试步骤与复现命令 |
| [`plugin-matrix.md`](./docs/ohos/plugin-matrix.md) | Flutter 插件 HarmonyOS 适配矩阵 |

## 免责声明

- 本项目是 **非官方** 客户端，与 linux.do 官方无关；使用需遵守社区规则。
- 上游项目：https://github.com/Lingyan000/fluxdo ｜ 许可证：[GPL-3.0](./LICENSE)，本分支同样遵循 GPL-3.0。
