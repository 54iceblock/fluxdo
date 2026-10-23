# 构建 / 签名 / 安装

本页面向开发者，说明如何从源码构建 HarmonyOS 包、签名并安装。
普通用户的侧载步骤见 [README-ohos.md](../../README-ohos.md#侧载安装)。

## 1. 环境准备

| 依赖 | 要求 |
|---|---|
| 操作系统 | Windows 10/11（脚本为 PowerShell） |
| DevEco Studio | **26.x**，含 OpenHarmony SDK **API 26**、hvigor、hdc、jbr |
| HarmonyOS Flutter SDK | **3.47.7+ohos**（`flutter --version` 带 `ohos`），并加入 PATH |
| DevEco 位置 | 默认 `C:\Program Files\Huawei\DevEco Studio`；不在默认位置时设置 `DEVECO_HOME` |
| （可选）WSL Ubuntu 24.04 | 仅重新交叉编译原生库时需要 |

脚本路径约定：仓库内 `tools/ohos/`；工作区（放 `.cache` 产物的目录）默认取仓库的上级目录，
可用 `FLUXDO_WS` 覆盖。环境变量一次性配置：

```powershell
$env:DEVECO_HOME = 'D:\DevEco Studio'     # 按实际安装位置
. .\tools\ohos\env.ps1                    # 设置 DEVECO_SDK_HOME / NODE_HOME / PATH / PUB_CACHE 等
flutter pub get
```

## 2. 构建方式

### 2.1 真机 release（华为证书签名）—— 商用 HarmonyOS 设备

前提：用 DevEco 打开 `ohos/` 目录 → 登录华为账号 →
`File → Project Structure → Signing Configs` 勾选 **Automatically generate signature** → OK。
这一步会把 `signingConfigs`（含加密口令）写进 `ohos/build-profile.json5`，并生成绑定当前设备 UDID 的调试 Profile。

```powershell
cd tools\ohos
.\build-device-release.ps1                 # 构建 release + 签名 + 安装 + 启动
.\build-device-release.ps1 -BuildOnly      # 只构建（产物 entry-default-signed.hap）
.\build-device-release.ps1 -Device <序列号> # 多设备时指定
```

产物：`ohos/entry/build/default/outputs/default/entry-default-signed.hap`（约 204 MB，双 ABI）。

### 2.2 模拟器 / OpenHarmony 开发板（OpenHarmony 默认证书）

不需要华为账号，脚本用 SDK 自带的 OpenHarmony.p12 生成 `debug` Profile 并签名：

```powershell
cd tools\ohos
.\build-ohos.ps1 -Mode release -Arch ohos-x64 -Install -Launch     # 模拟器
.\build-ohos.ps1 -Mode release -Arch ohos-arm64 -Install -Launch   # 开发板（arm64）
.\build-ohos.ps1 -Mode debug -Arch ohos-x64                        # debug（调试用）
.\build-ohos.ps1 -NoSign                                           # 只构建，出 unsigned HAP
```

> 两套签名互斥：`build-ohos.ps1` 假定 `signingConfigs` 为空；如果 DevEco 已写入华为签名配置，
> 请改用 `build-device-release.ps1`，否则 hvigor 内置签名与手工签名会冲突。

### 2.3 仅用 hvigor 构建

```powershell
cd ohos
hvigorw --mode module -p module=entry@default -p product=default -p buildMode=release assembleHap
```

DevEco 图形界面等价入口：`Build → Build Hap(s)/APP(s) → Build Hap(s)`
（中文：**构建 → 编译 Hap(s)/APP(s) → 编译 Hap(s)**）。
注意：DevEco 的 **Run ▶ 永远构建 debug 包**；要 release 必须走 Build Hap(s)。

## 3. 签名

HarmonyOS 要求 HAP 必须被设备信任的证书签名。三种情况：

| 场景 | 证书 | 工具 |
|---|---|---|
| 商用 HarmonyOS 设备（真机） | 华为开发者证书（调试证书 + 绑定 UDID 的 Profile） | DevEco 自动签名；签名由 hvigor 完成 |
| 模拟器 / OpenHarmony 开发板 | OpenHarmony 默认证书链 | `tools/ohos/ohos-sign.ps1`（自动生成 profile + 签名） |
| 自有证书（AGC 申请） | 自己的 p12 / cer / p7b | `hap-sign-tool`，参数见 `tools/ohos/sign-hap.ps1` |

`ohos-sign.ps1` 用法：

```powershell
cd tools\ohos
.\ohos-sign.ps1 -BundleName com.fluxdo.app -InHap <unsigned.hap> -OutHap <signed.hap>
```

它会：导出 OpenHarmony 证书链 → 用 SDK 模板生成含设备 UDID 的 debug Profile → `hap-sign-tool sign-profile` → `sign-app`。

## 4. 安装 / 启动

```powershell
hdc list targets                                   # 确认设备
hdc install -r entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.fluxdo.app
```

## 5. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `9568257 fail to verify pkcs7 file` | 签名证书不被设备信任（用了别人的/OpenHarmony 证书），或 Profile 未含本机 UDID | 用自己华为账号自动签名（§2.1） |
| `install failed due to grant request permissions failed` | 声明了 system_basic 级权限（如 `READ_PASTEBOARD`） | 本仓库已不声明这类权限；不要手动加回 |
| `Project Structure` 灰色 / DevEco 打开即报错 | 工程 sync 失败；常见原因：`build-profile.json5` 的 SDK 版本非法、路径含空格、构建脚本类型检查报错 | 见下方「DevEco 排查」 |
| `No permission write to signConfigCheckJson.json` | DevEco 写入了 `signingConfigs`，同时脚本又用 OpenHarmony 证书签名 | 真机走 §2.1，模拟器走 §2.2，不要混用 |
| `spawn java ENOENT` | hvigor daemon 缓存了旧 PATH（没有 jbr） | `hvigorw --stop-daemon` 后重跑 |
| 构建脚本类型检查报错（TS2742 / TS2550 等） | DevEco 构造命令带 `--enable-build-script-type-check`，而 Flutter 的 hvigor 插件/各 hvigorfile 存在类型问题 | 仓库已附带修复：`tools/ohos/fix-hvigorfile-typecheck.ps1`，并按需应用 `docs/ohos/patches/flutter-hvigor-plugin-typecheck.patch` |
| Dart/Flutter 报「无法写入 .flutter_tool_state / .dart-tool」 | 工作区被打了低完整性（Low IL）标签，dart 以低权限运行 | `tools/ohos/fix-integrity-labels.ps1` 恢复为 Medium |
| `hdc list targets` 为空 | 未开 USB 调试 / 未在手机确认授权 / 线材仅充电 | 重新插拔并确认弹窗 |

### DevEco 排查要点

1. `build-profile.json5` 的 `compatibleSdkVersion` / `targetSdkVersion` 必须是完整三段式 `"26.0.0"`
   （API 10–25 才是 `5.0.0(12)` 这种形式）。
2. DevEco 安装路径**不能含空格**（`D:\DevEco Studio` 会导致 hvigor 启动 `ohpm.bat` 时参数被拆断）；
   推荐 `C:\Users\<you>\DevEcoStudio` 这类无空格路径。
3. 若 DevEco 打开工程后自动写入 `signingConfigs`，脚本化构建前需把它恢复为 `[]`
   （真机构建请直接用 §2.1 专用脚本）。
4. 构建报 `TS2742 hvigor/types` / FlowOS 插件类型错误时，运行
   `tools/ohos/fix-hvigorfile-typecheck.ps1` 后 `hvigorw --stop-daemon` 再构建。

## 6. 原生库

5 个原生库已随仓库提交，普通构建无需编译。重新编译（需 WSL + OHOS NDK）：

```bash
# 在 WSL 中，先 export FLUXDO_WS=/mnt/c/Users/<you>/fluxdo, OHOS_NDK=...
bash tools/ohos/build-doh-ohos.sh
bash tools/ohos/build-rhttp-ohos.sh
bash tools/ohos/build-avif-ohos.sh
bash tools/ohos/build-native-animated-image-ohos.sh
bash tools/ohos/build-quickjs-ohos.sh
```

产物会写入 `ohos/entry/libs/{x86_64,arm64-v8a}/`。原理与踩坑见 [architecture.md](./architecture.md#3-自编译原生库5-个)。
