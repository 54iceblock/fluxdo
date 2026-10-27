# OHOS 构建 / 签名工具链（已纳入版本控制）

审核发现：这套脚本原先只存在于工作区 `C:\Users\iceblock\fluxdo\tools\`（仓库之外），
**完全没有进 git** —— 一旦机器损坏或换机，构建链路（交叉编译命令、签名流程、
hvigor 补丁）全部不可复现。这里是从工作区复制进来的版本化副本。

## 权威版本与同步

- **权威版本：本目录**（`repo/ohos/tools/`），改动请在这里提交。
- 工作区 `..\..\tools\` 是日常构建用的工作副本（脚本内部大量使用
  `C:\Users\iceblock\fluxdo\...` 绝对路径，保持原位最省事）。
- 同步（工作区 → 仓库），提交前执行：

```powershell
robocopy C:\Users\iceblock\fluxdo\tools C:\Users\iceblock\fluxdo\repo\ohos\tools `
  *.ps1 *.bat *.cmd *.sh *.c *.js /S /XO
```

## 脚本清单

| 文件 | 用途 |
|---|---|
| `env.ps1` | 环境（PUB_CACHE / HOME / NODE_OPTIONS / hvigor 依赖），每个新终端先 dot-source |
| `build-ohos.ps1` | 一键构建：`flutter build hap` → 找 unsigned hap → `ohos-sign.ps1` 签名 → 可选 hdc install/launch |
| `ohos-sign.ps1` | 用 OpenHarmony 默认证书链 + 按 bundleName 生成 debug profile 后签 HAP（无需华为账号） |
| `sign-hap.ps1` | 同上，早期版本（保留以兼容旧命令） |
| `sign-*.bat`、`gen-app-cert.bat` | hap-sign-tool 的原始命令行封装（调试/手工排查用） |
| `verify-profile.bat` | 验证 p7b profile |
| `build-avif-ohos.sh` | WSL 交叉编译 libavif + dav1d → `libohos_avif.so` |
| `build-quickjs-ohos.sh` | WSL 编译 QuickJS → `libohos_quickjs.so`（配 `ohos-quickjs-bridge.c`） |
| `build-doh-ohos.sh` | WSL 编译 Rust `core/doh_proxy` → `libdoh_proxy.so` |
| `build-rhttp-ohos.sh` | WSL 编译 `packages/rhttp`（reqwest + FRB）→ `librhttp.so` |
| `build-native-animated-image-ohos.sh` | WSL 编译动图解码 → `libnative_animated_image_codec.so` |
| `build-ohos-unwind-stub.sh` / `ohos-unwind-stub.c` | 交叉链接缺 libgcc unwind 符号时的占位实现 |
| `ohos-avif-decode.c` | AVIF 解码包装（导出 `ohos_avif_decode` / `ohos_avif_free`，含 max_dim 降采样） |
| `fix-hvigorfile-typecheck.ps1` | 修 hvigorfile.ts 让 DevEco 的 `--enable-build-script-type-check` 通过 |
| `fix-integrity-labels.ps1` | 修 Windows 低完整性标签导致的构建失败 |
| `node-symlink-fallback.js` | Windows 无 symlink 权限时把链接降级为 junction |
| `mock-discourse/server.py` | 真机联调用的本地 mock Discourse（配 `--dart-define=FLUXDO_BASE_URL`） |
| `publish-release.ps1` / `dl.js` | 发布辅助 |

## 口令约定

签名口令一律从环境变量读取，**不要把真实口令写回脚本**：

```powershell
$env:FLUXDO_SIGN_PWD = '<密钥库口令>'   # 不设时回落到 OpenHarmony 默认的公开口令 123456
```

> 调试证书链（OpenHarmony 默认）口令是公开值，仅够本机/开发板调试；正式证书
> 请走 DevEco 自动签名或自建证书，并把口令放进环境变量。

## AVIF 原生库（`libohos_avif.so`）的来源与校验

`.so` 是**二进制入库**的，CI 不编译 OHOS（`build.yaml` 矩阵只有 android/ios/macos/windows），
所以这里把「哪个源码 + 什么工具链 + 期望的哈希」固定下来，便于复核二进制有没有被替换、
或者源码改了却没重编。

| 项 | 值 |
|---|---|
| 源码（权威） | `ohos/tools/ohos-avif-decode.c`（本目录；导出 `ohos_avif_decode` / `ohos_avif_free`，含 `downscale_rgba_box` 降采样） |
| 构建脚本 | `ohos/tools/build-avif-ohos.sh`（WSL 内交叉编译） |
| libavif | 1.4.2（`AVIF_VERSION_MAJOR/MINOR/PATCH`），源码 `~/.cache` 副本 `b1e4d33` |
| dav1d | 1.5.4，静态库，`-Denable_asm=false`，源码副本 `9433da2` |
| OHOS NDK | 26.0.0.105（API 26），clang `resource-dir=.../llvm/lib/clang/15.0.4` |
| 主机构建环境 | Ubuntu 24.04（WSL2）：clang 18.1.3 / cmake 3.28.3 / meson 1.3.2 / ninja 1.11.1 / nasm 2.16.01 |
| 目标 ABI | `arm64-v8a`（aarch64-linux-ohos）、`x86_64`（x86_64-linux-ohos） |

**入库二进制的校验值（2026-10-27 复核，且已重编验证可复现）**

| 产物 | 大小 | SHA-256 |
|---|---|---|
| `ohos/entry/libs/arm64-v8a/libohos_avif.so` | 898,968 B | `0B0170BAE75AE495111EB30BD27483E7BE470CB5F14386E0A4D3D7F5B2B6930E` |
| `ohos/entry/libs/x86_64/libohos_avif.so` | 1,068,200 B | `68F88BC4B8ED4611E43B11E020AF2FAEB6275864582D295E804530DB7A870504` |

> **可复现性结论（2026-10-27 实测）**：在 Ubuntu-24.04 WSL 里用上述工具链、按
> `build-avif-ohos.sh` 从 `ohos/tools/ohos-avif-decode.c` 重新交叉编译两个 ABI，
> 产物与入库二进制的 **SHA-256 完全一致**（大小也一致），说明入库 `.so` 确实由当前
> 提交的源码产出，没有夹带未入库的改动。重编日志见 `.tmp/avif-rebuild/`。

**复核步骤**

```powershell
# 1) 看当前入库二进制的哈希是否与上表一致
Get-FileHash -Algorithm SHA256 repo\ohos\entry\libs\*\libohos_avif.so
# 2) 需要重编时（WSL 内，需 clang/cmake/meson/ninja/nasm）
bash ohos/tools/build-avif-ohos.sh
# 3) 重编后哈希不一致时，至少确认导出符号与内嵌字符串没问题
llvm-nm.exe -D --defined-only repo\ohos\entry\libs\arm64-v8a\libohos_avif.so | Select-String ohos_avif
#    期望：T ohos_avif_decode / T ohos_avif_free
strings repo\ohos\entry\libs\arm64-v8a\libohos_avif.so | Select-String 'C:\\Users'
#    期望：无输出（不能把本机绝对路径打进产物）
```

> 交叉编译产物通常无法逐字节复现（时间戳、构建路径会进 `.comment` / `__FILE__`），
> 因此哈希只作为「和本次提交的二进制是否同一份」的指纹，不作为「能否重建」的判据；
> 判据是导出符号 + 行为（`ohos/tools` 里的 `avif_probe` 或真机日志）。
>
> 改 `ohos-avif-decode.c` 之后必须重编并把上表两行哈希一起更新，否则入库二进制与源码脱节。

