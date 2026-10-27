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
