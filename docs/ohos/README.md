# HarmonyOS 移植文档

本目录是 FluxDO HarmonyOS 7 移植的文档。普通用户请先看仓库根目录的
[README-ohos.md](../../README-ohos.md)（含侧载安装步骤）。

| 文档 | 面向 | 内容 |
|---|---|---|
| [architecture.md](./architecture.md) | 开发者 | 移植架构：平台工程、5 个原生库、ArkTS 桥、Dart 侧适配 |
| [build.md](./build.md) | 开发者 | 构建 / 签名 / 安装 / 常见报错（DevEco 与命令行） |
| [device-test.md](./device-test.md) | 测试 / 用户 | 真机已验证项、未覆盖项、测试步骤与复现命令 |
| [plugin-matrix.md](./plugin-matrix.md) | 开发者 | Flutter 插件 HarmonyOS 适配矩阵 |

## 状态速览

- 目标系统：HarmonyOS 7（API 26）
- 真机验证设备：HUAWEI HBN-AL00，HarmonyOS 7.0.0.109（API 26）
- 原生库：5 个已预编译并随仓库提交（rhttp / doh_proxy / libavif+dav1d / 动图解码 / QuickJS）
- 安装方式：应用未上架应用市场，仅支持**侧载**（需用自己的华为开发者证书签名）

## 构建一句话

```powershell
# 真机 release（需先按 README-ohos.md 用 DevEco 生成自动签名）
.\tools\ohos\build-device-release.ps1

# 模拟器 / OpenHarmony 开发板（OpenHarmony 默认证书，无需华为账号）
.\tools\ohos\build-ohos.ps1 -Mode release -Arch ohos-x64 -Install -Launch
```

详细步骤见 [build.md](./build.md)。
