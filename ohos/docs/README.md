# OHOS 移植文档（已纳入版本控制）

审核发现：这 14 份移植/上架文档原先只存在于工作区 `C:\Users\iceblock\fluxdo\docs\`
（仓库之外，未进 git）。这里是从工作区复制进来的版本化副本，**本目录为权威版本**。

工作区 `..\..\docs\` 保留为历史副本，不再更新。同步（工作区 → 仓库）：

```powershell
robocopy C:\Users\iceblock\fluxdo\docs C:\Users\iceblock\fluxdo\repo\ohos\docs *.md /XO
```

## 文档索引

| 文件 | 内容 |
|---|---|
| [README-ohos.md](README-ohos.md) | 交付总览：一键构建、交付内容、功能状态、已知限制、上架前置 |
| [ohos-port-report.md](ohos-port-report.md) | 移植总报告（技术决策、踩坑、阶段结论） |
| [ohos-port-status.md](ohos-port-status.md) | 移植进度快照 |
| [ohos-acceptance.md](ohos-acceptance.md) | 验收清单（A1–A4x 用例） |
| [ohos-device-test-plan.md](ohos-device-test-plan.md) | 真机测试单（前置/安装/冒烟/功能用例/证据采集） |
| [ohos-device-test-report.md](ohos-device-test-report.md) | 真机测试报告 |
| [ohos-release-plan.md](ohos-release-plan.md) | 上架计划（G0–G7 门禁、风险、AGC 待确认项） |
| [ohos-cf-fix.md](ohos-cf-fix.md) | Cloudflare 挑战的根因与浏览器网络栈兜底 |
| [ohos-plugin-matrix.md](ohos-plugin-matrix.md) | 插件可用性矩阵 + 权限清单 |
| [ohos-pubspec-changes.md](ohos-pubspec-changes.md) | 依赖改动与回滚方式 |
| [ohos-native-strategy.md](ohos-native-strategy.md) | 原生能力补齐策略（Rust/C 交叉编译） |
| [ohos-native-rewrite-feasibility.md](ohos-native-rewrite-feasibility.md) | 原生重写可行性评估 |
| [ohos-arkts-bridges.md](ohos-arkts-bridges.md) | 自研 ArkTS 桥的设计与通道约定 |
| [ohos-build-notes.md](ohos-build-notes.md) | 构建踩坑笔记（hvigor/签名/环境） |
| [ohos-deveco-troubleshooting.md](ohos-deveco-troubleshooting.md) | DevEco Studio 使用问题排查 |

## 本轮审核后的内容修订（2026-10）

- 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` /
  `backgroundModes`）已在 `e63e3be`、`c9578bb` 中**整体移除**（常驻通知栏条目、
  用户反馈收益有限）。文档中相关的「已验证能力」「测试用例」「上架说明」已删除
  或标注为「已移除」，避免交付说明与代码不一致。
- 剪贴板「读富文本」依赖 system_basic 级 `READ_PASTEBOARD`，普通证书拿不到，
  相关实现与 Promise 一并移除；OHOS 富文本粘贴按设计降级纯文本。
- `ohos.permission.PUBLISH_AGENT_REMINDER` 已从最终 HAP 移除（解包 module.json 实测：
  只剩 INTERNET / GET_NETWORK_INFO / CAMERA / MICROPHONE）。注意 hvigor 会把依赖 HAR
  的权限合并进产物，只删应用侧声明无效；因此 `flutter_local_notifications` 已 vendored
  到 `packages/flutter_local_notifications` 并删掉其 HAR 里的条目（见该目录 `VENDOR.md`）。
  `GET_NETWORK_INFO` **要保留**：connectivity_plus 在用，且其 HAR 也自带声明。
- AVIF 解码已在 2026-10 重修：C 侧实现 `max_dim` 盒式降采样、解码上限收到 8192，
  Dart 侧改为常驻后台 isolate；`libohos_avif.so`（x86_64 / arm64）已用新源码重编入库。
  改动 `tools/ohos-avif-decode.c` 后要重编：`wsl bash tools/build-avif-ohos.sh`
  （WSL 本地 NDK 不在时脚本会自动改用 DevEco SDK 的 `native/` 目录）。
- 签名配置不再入库：`ohos/build-profile.json5` 的 `signingConfigs` 必须为空数组，
  提交前跑 `dart tool/check_no_secrets.dart`（`just check-secrets`）。
- git 依赖全部锁定到 commit SHA：`dart tool/check_ohos_pubspec.dart`
  （`just check-pubspec`），跨平台回归用 `--portable` 生成去掉 OHOS override 的
  pubspec。两个守卫在每次 push/PR 由 `.github/workflows/repo-guards.yaml` 运行，
  发版构建（build.yaml）里也会再跑一遍。

## 遗留风险：git 历史里的签名材料

`f23ecc2` 及之前的提交里仍带着 DevEco 自动写入的 debug 签名配置（本机证书路径 +
加密后的 `keyPassword`/`storePassword`）。HEAD 已清理并加了守卫脚本，但**历史仍在**：

- 这些是 DevEco 为本机自动生成的**调试**证书材料，不是正式证书/私钥本体
  （`.p12` 文件本身从未入库，历史里只有路径与加密口令字符串）。
- 若仓库要公开（或已经推送），建议按下面步骤彻底清理历史后再推送：
  ```bash
  pip install git-filter-repo
  git filter-repo --path ohos/build-profile.json5 --invert-paths   # 不保留该文件任何历史版本
  # 或只替换内容：
  git filter-repo --replace-text <(echo 'regex:keyPassword.*==>keyPassword: ""')
  git push --force-with-lease fork main
  ```
- 无论是否清理，都建议换一套调试证书（DevEco 重新自动签名即可生成新的），
  让历史里那串口令彻底失效。

