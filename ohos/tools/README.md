# OHOS 构建 / 签名工具链

FluxDO HarmonyOS 版（API 26）的构建、签名与原生库交叉编译脚本。**本目录是权威版本**，
改动请在这里提交；发布帖 / 文档里引用的命令都指向本文件。

---

## 1. 前置条件

| 组件 | 版本 / 要求 | 说明 |
|---|---|---|
| 操作系统 | Windows 11 | 目前只在 Windows 上验证过（脚本是 PowerShell） |
| DevEco Studio | **26.0**（HarmonyOS SDK **API 26 / 7.0.0**） | 提供 hvigor / ohpm / hdc / JDK / Node |
| Flutter | **3.47.7 + OHOS 分支**（`oh-3.47.7-preview`，Dart 3.13.5） | 官方 Flutter 没有 `ohos` target，必须用鸿蒙社区分支 |
| Windows 开发者模式 | 建议开启 | 否则 hvigor 建 symlink 会 `EPERM`（脚本有 junction 兜底，但仍建议开） |
| WSL2 + Ubuntu 24.04 | 仅重编原生库时需要 | 5 个 `.so` 已入库，普通构建不需要 |

Flutter OHOS SDK 默认放在仓库的 `tools/flutter/`（`env.ps1` 里的 `$FLUTTER` 指向它）；
放别处就改这一行。

---

## 2. 三步跑起来

### 第一步：改路径（3 处）

`ohos/tools/env.ps1` 顶部：

```powershell
$WS        = 'D:\code\fluxdo'          # 本仓库根目录
$TOOL_HOME = 'D:\DevEco Studio'        # DevEco Studio 安装目录
$FLUTTER   = Join-Path $WS 'tools\flutter'   # Flutter OHOS SDK 位置（默认值，可不动）
```

`ohos/tools/build-ohos.ps1` 的参数默认值：

```powershell
[string]$RepoRoot = 'D:\code\fluxdo'    # 或每次命令行传 -RepoRoot
```

> `env.ps1` 会把 `HOME` / `TEMP` / `PUB_CACHE` 全部重定向到工作区内，用来绕开 ohpm、hvigor、
> Dart 在系统目录上的 ACL 问题。**每个新终端都要先 dot-source 它**，不要跳过。

### 第二步：构建

```powershell
. .\ohos\tools\env.ps1
.\ohos\tools\build-ohos.ps1 -Mode release -Arch ohos-arm64
```

产物：

- 未签名：`ohos\entry\build\default\outputs\default\entry-default-unsigned.hap`
- 脚本签名（OpenHarmony 默认证书，**只能装模拟器 / 开发板**）：`.cache\ohos-build\fluxdo-{debug|release}-*.hap`

常用参数：

```powershell
.\ohos\tools\build-ohos.ps1 -NoSign                 # 只构建，不签名
.\ohos\tools\build-ohos.ps1 -PubGet                 # 先 flutter pub get
.\ohos\tools\build-ohos.ps1 -Install -Launch        # 构建 + 签名 + 装到已连接设备并启动
.\ohos\tools\build-ohos.ps1 -Device auto            # 自动取第一个在线设备（默认 127.0.0.1:5555 模拟器）
```

### 第三步：装到自己的手机

商业 HarmonyOS 设备只信任华为签发的证书，必须自己签一次：

1. **DevEco 自动签名（推荐）**：DevEco Studio 打开 `ohos/` 工程 →
   `File > Project Structure > Signing Configs` → 勾 **Automatically generate signature**
   （需登录华为账号）→ 用生成的证书对 HAP 签名；profile 里必须包含目标设备 UDID。
2. **手工签名**：`hap-sign-tool` + DevEco 产出的 `.p7b` / `.cer` / `.p12`，
   参数见 `sign-*.bat`、`gen-app-cert.bat`。
3. **安装**：

   ```powershell
   hdc install -r .cache\ohos-build\fluxdo-release-ohos-arm64-signed.hap
   hdc shell aa start -a EntryAbility -b com.fluxdo.app
   ```

> **为什么不直接发 HAP？** 鸿蒙调试证书与设备 UDID 绑定，别人签好的包装不到你机子上；
> release 证书要走应用市场备案。所以现阶段只能「源码 + 自签」。

---

## 3. 常见报错

| 现象 | 原因 | 处理 |
|---|---|---|
| `fail to verify pkcs7 file` / 错误码 `9568257` | OpenHarmony 默认证书在商业设备上不被信任 | 改用 DevEco 自动签名（华为账号） |
| 构建末尾打印「请通过 DevEco Studio 配置调试签名」并 `exit 1` | `flutter build hap` 在 hvigor 之后做签名检查 | **正常现象**：unsigned HAP 已产出，`build-ohos.ps1` 会接着手工签名 |
| `EPERM ... symlink` / `operation not permitted` | Windows 未开开发者模式，或沙箱禁止建链接 | 开开发者模式；确认 `NODE_OPTIONS` 加载了 `node-symlink-fallback.js` |
| `compatibleSdkVersion` 校验失败 | API 26 的写法是 `"26.0.0"`，不是 `5.0.0(12)` | 改 `ohos/build-profile.json5` |
| Flutter 首次运行卡在下载 Dart SDK | 脚本用 PowerShell 下载，schannel 不通 | 用 `ohos/tools/dl.js`（Node 原生 TLS）预下载到 `bin/cache/dart-sdk` |
| 首屏 403 / Cloudflare 一直转 | 模拟器 IP 触发 CF 挑战 | 应用内已内置 WebView 网络栈兜底；真机一般无此问题 |
| `.ps1` 中文脚本语法错 | 文件不是 UTF-8 **BOM**，PowerShell 5.1 按 GBK 解析 | 另存为 UTF-8 with BOM |
| hvigor 拒绝明文签名口令 | hvigor 要求 ≥32 位密文口令 | 保持 `signingConfigs: []`，用脚本签名 |
| `module.json5` schema 报错（`backgroundModes`） | 该字段属 ability 级配置，不在 module 根 | 删掉；长时任务相关配置已整体移除 |
| 安装时报 `install bundle failed`（`INSTALL_FAILED_VERIFY_APP_PKCS7_FAIL`） | 证书链或 UDID 不匹配 | 重新生成 profile，确认 UDID = `hdc shell bm get -u` 的输出 |

---

## 4. 原生库（改源码后才需要重编）

5 个 `.so` 已入库到 `ohos/entry/libs/{arm64-v8a,x86_64}/`，普通构建直接用。改动 C/Rust
源码后，在 **WSL2 + Ubuntu 24.04** 里交叉编译（脚本头部注释写了完整工具链版本）：

```bash
bash ohos/tools/build-doh-ohos.sh                    # Rust DOH 网关 → libdoh_proxy.so
bash ohos/tools/build-rhttp-ohos.sh                  # Rust reqwest + FRB → librhttp.so
bash ohos/tools/build-native-animated-image-ohos.sh  # 原生动图解码
bash ohos/tools/build-avif-ohos.sh                   # libavif + dav1d → libohos_avif.so
bash ohos/tools/build-quickjs-ohos.sh                # QuickJS + ohos-quickjs-bridge.c
```

交叉链接缺 `libgcc` unwind 符号时，用 `build-ohos-unwind-stub.sh` + `ohos-unwind-stub.c` 兜底。

---

## 5. 脚本清单

| 文件 | 用途 |
|---|---|
| `env.ps1` | 环境变量（`FLUTTER_ROOT` / `DEVECO_SDK_HOME` / `PUB_CACHE` / `NODE_OPTIONS`），每个新终端先 dot-source |
| `build-ohos.ps1` | 一键构建：`flutter build hap` → 找 unsigned HAP → 签名 → 可选安装/启动 |
| `ohos-sign.ps1` | 用 OpenHarmony 默认证书链 + 按 bundleName 生成 debug profile 后签名（无需华为账号，仅模拟器/开发板） |
| `build-device-release.ps1` | 真机 release 构建（arm64）成套流程 |
| `sign-hap.ps1` / `sign-*.bat` / `gen-app-cert.bat` | `hap-sign-tool` 的原始命令封装（手工排查用） |
| `verify-profile.bat` | 校验 p7b profile |
| `fix-hvigorfile-typecheck.ps1` | 让 DevEco 的 `--enable-build-script-type-check` 通过 |
| `fix-integrity-labels.ps1` | 修 Windows 低完整性标签导致的构建失败 |
| `node-symlink-fallback.js` | 无 symlink 权限时把链接降级为 junction |
| `mock-discourse/server.py` | 本地 mock Discourse（配 `--dart-define=FLUXDO_BASE_URL`），用于无网/无账号联调 |
| `dl.js` | 用 Node 原生 TLS 下载（绕开 schannel 问题） |
| `build-*-ohos.sh` | WSL 内交叉编译 5 个原生库 |

签名口令一律从环境变量读取，**不要把真实口令写进脚本**：

```powershell
$env:FLUXDO_SIGN_PWD = '<密钥库口令>'   # 不设时回落到 OpenHarmony 默认的公开口令
```

---

## 6. AVIF 原生库（`libohos_avif.so`）的来源与校验

`.so` 是**二进制入库**的，仓库 CI 不编译 OHOS（`build.yaml` 矩阵只有 android/ios/macos/windows），
因此把「哪个源码 + 什么工具链 + 期望哈希」固定下来，便于复核二进制有没有被掉包、
或源码改了却没重编。

| 项 | 值 |
|---|---|
| 源码（权威） | `ohos/tools/ohos-avif-decode.c`（导出 `ohos_avif_decode` / `ohos_avif_free`，含 `downscale_rgba_box` 降采样） |
| 构建脚本 | `ohos/tools/build-avif-ohos.sh`（WSL 内交叉编译） |
| libavif | 1.4.2，源码副本 `b1e4d33` |
| dav1d | 1.5.4，静态库，`-Denable_asm=false`，源码副本 `9433da2` |
| OHOS NDK | 26.0.0.105（API 26），clang `resource-dir=.../llvm/lib/clang/15.0.4` |
| 主机构建环境 | Ubuntu 24.04（WSL2）：clang 18.1.3 / cmake 3.28.3 / meson 1.3.2 / ninja 1.11.1 / nasm 2.16.01 |
| 目标 ABI | `arm64-v8a`（aarch64-linux-ohos）、`x86_64`（x86_64-linux-ohos） |

**入库二进制的校验值（2026-10-27 复核，重编后逐字节一致）**

| 产物 | 大小 | SHA-256 |
|---|---|---|
| `ohos/entry/libs/arm64-v8a/libohos_avif.so` | 898,968 B | `0B0170BAE75AE495111EB30BD27483E7BE470CB5F14386E0A4D3D7F5B2B6930E` |
| `ohos/entry/libs/x86_64/libohos_avif.so` | 1,068,200 B | `68F88BC4B8ED4611E43B11E020AF2FAEB6275864582D295E804530DB7A870504` |

**复核步骤**

```powershell
# 1) 入库二进制是否与上表一致
Get-FileHash -Algorithm SHA256 ohos\entry\libs\*\libohos_avif.so
# 2) 需要重编时（WSL 内，需 clang/cmake/meson/ninja/nasm）
bash ohos/tools/build-avif-ohos.sh
# 3) 重编后哈希变化时，至少确认导出符号与内嵌字符串没问题
llvm-nm -D --defined-only ohos/entry/libs/arm64-v8a/libohos_avif.so | grep ohos_avif
#    期望：T ohos_avif_decode / T ohos_avif_free
strings ohos/entry/libs/arm64-v8a/libohos_avif.so | grep -i 'users\\'
#    期望：无输出（不能把本机绝对路径打进产物）
```

> 交叉编译产物通常无法逐字节复现（时间戳、构建路径会进 `.comment` / `__FILE__`），
> 因此哈希只作为「入库二进制是否由当前提交的源码产出」的指纹，不作为「能否重建」的判据；
> 判据是导出符号 + 运行时行为（`avif_probe` 日志或真机表现）。
> 改 `ohos-avif-decode.c` 之后必须重编，并把上表两行哈希一起更新。
