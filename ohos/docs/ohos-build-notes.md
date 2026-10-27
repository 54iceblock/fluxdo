# FluxDO × HarmonyOS 7 构建 / 签名 / 安装笔记（task-6 交付）
> ⚠️ **2026-10 审核后状态：本文档部分内容已过时。**
> 后台保活（系统长时任务 DATA_TRANSFER / `KEEP_BACKGROUND_RUNNING` / `backgroundModes`）已在 `e63e3be`、`c9578bb` 中整体移除；
> 剪贴板「读富文本」因依赖 system_basic 级 `READ_PASTEBOARD` 已移除（粘贴降级纯文本）；
> `ohos.permission.PUBLISH_AGENT_REMINDER` 已从应用侧 `module.json5` 删除（最终包仍由依赖 HAR 带入，见 README.md）。
> 以代码与 [README.md](README.md) 末尾的「本轮审核后的内容修订」为准。


> 适用仓库：`C:\Users\iceblock\fluxdo\repo`（Flutter 应用 fluxdo）
> 工具链：Flutter `3.47.7+ohos-0.0.1-pre`（`C:\Users\iceblock\fluxdo\tools\flutter`）+ DevEco Studio 26（`D:\DevEco Studio`，SDK API 26）
> 模拟器：HarmonyOS 7 x86_64，hdc 目标 `127.0.0.1:5555`
> 本文所有结论都来自本机实测；"已验证/未验证"在每节显式标注。

---

## 0. 状态总览（TL;DR）

| 项 | 状态 | 说明 |
|---|---|---|
| `repo/ohos/` OHOS 工程脚手架 | ✅ 已落地 | 36 个文件，含 AppScope / entry / hvigor 配置、权限、深链、图标 |
| `tools/build-ohos.ps1` 一键构建脚本 | ✅ 已写并跑通脚本逻辑 | 构建失败时会打印 hvigor/flutter 关键错误行并定位最新 HAP |
| `tools/ohos-sign.ps1` 签名脚本 | ✅ 已重写并实测 | 修掉 2 个实际 bug（UTF-8 BOM、hap-sign-tool 不覆盖旧文件） |
| 签名 → 安装 → 启动 → 截图链路 | ✅ 已端到端复验 | 用 `scratch\hello` 的 unsigned HAP 复验；`build-ohos.ps1 -SkipBuild -Install` 也实测走通（定位→签名→安装成功），截图见 `.cache\ohos-build\hello-verify.jpeg` |
| `repo` 首次真实构建 | ⏳ 未完成（环境限制） | 本任务执行者（子代理）的沙箱禁止 `dart/flutter` 创建子进程，`flutter` 连 `git` 都起不来；**必须由 Lead 在完整权限会话跑一条命令**，见 §4.3 |
| `repo/.metadata` 补 `ohos` 平台记录 | ⚠️ 未做（越界） | 非构建必需；若要补，见 §7.11（建议手工补，不要跑 `flutter create`） |

---

## 1. 环境准备（每次新开 shell 必做）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
. C:\Users\iceblock\fluxdo\tools\env.ps1
```

`tools\env.ps1` 做的事（**不要跳过**）：

| 变量 | 值 | 原因 |
|---|---|---|
| `FLUTTER_ROOT` | `C:\Users\iceblock\fluxdo\tools\flutter` | 本机 OHOS 分支 Flutter |
| `DEVECO_SDK_HOME` / `OHOS_SDK_HOME` / `HOS_SDK_HOME` | `D:\DevEco Studio\sdk` | flutter doctor / hvigor 找 SDK |
| `JAVA_HOME` | `D:\DevEco Studio\jbr` | hvigor / hap-sign-tool |
| `NODE_HOME` | `D:\DevEco Studio\tools\node` | hvigor 用 DevEco 自带 node |
| `HOME` / `USERPROFILE` / `APPDATA` / `LOCALAPPDATA` / `TEMP` / `TMP` | 全部指向 `C:\Users\iceblock\fluxdo\.home`、`.tmp` | 否则 ohpm/hvigor/flutter 写用户目录会被沙箱拒绝 |
| `PUB_CACHE` | `C:\Users\iceblock\fluxdo\.pub-cache` | pub 缓存必须在可写目录 |
| `NODE_OPTIONS` | `--require C:\Users\iceblock\fluxdo\tools\node-symlink-fallback.js` | **关键坑**：hvigor 的 pnpm 用 symlink，Windows 无开发者模式时 EPERM；该补丁把 symlink 降级为 junction |
| `PATH` | 追加 flutter/bin、DevEco node/ohpm/hvigor、SDK toolchains、jbr | 让 `flutter` / `hvigorw` / `ohpm` / `hdc` 直接可用 |
| `npm_config_node_linker=hoisted` | — | 同上，避免 symlink |

自检：

```powershell
flutter --version          # Flutter 3.47.7 • channel oh-3.47.7-preview
flutter doctor -v          # Flutter / HarmonyOS toolchain 均 OK
hdc list targets           # 127.0.0.1:5555
```

> ⚠️ 沙箱经验：DSH 的 workspace-write 沙箱模式会拦管子进程管道，`flutter`（dart）连 `git -c ... log` 都起不来，报
> `CreateFile failed 5 (拒绝访问)` + `Flutter failed to run "git ...". The flutter tool cannot access the file or directory`。
> 凡是要跑 flutter / hvigor / npm / git 的会话，必须是**完整权限**会话（本任务的子代理做不到）。

---

## 2. `repo/ohos/` 工程结构

```
repo/ohos/
├─ .gitignore                       # 忽略 build/ oh_modules/ local.properties/ package.json/ flutter_assets/ 等
├─ build-profile.json5              # ★ 工程级：SDK 26.0.0、signingConfigs=[]、modules=[entry]
├─ hvigorfile.ts                    # ★ 接入 flutter-hvigor-plugin（在 hvigor 构建里回调 flutter assemble）
├─ hvigorconfig.ts                  # injectNativeModules(...)
├─ hvigor/hvigor-config.json5       # modelVersion 5.1.0
├─ oh-package.json5                 # 工程级 ohpm 包（name=fluxdo，devDep @ohos/hypium 1.0.6）
├─ local.properties                 # ⚠️ 工具生成、已 gitignore（见 §3.5）
├─ AppScope/
│  ├─ app.json5                     # ★ bundleName=com.fluxdo.app、versionCode/versionName、图标/label
│  └─ resources/base/{element/string.json, media/app_icon.png}
└─ entry/
   ├─ .gitignore
   ├─ build-profile.json5           # apiType stageMode；targets default + ohosTest
   ├─ hvigorfile.ts                 # system: hapTasks（插件会向 entry 注入 flutter 任务）
   ├─ oh-package.json5              # 依赖由 flutter 工具/hvigor 插件在构建期注入
   └─ src/
      ├─ main/
      │  ├─ module.json5            # ★ 权限 + backgroundModes + home/深链 skills
      │  ├─ ets/
      │  │  ├─ entryability/EntryAbility.ets      # extends FlutterAbility；注册 GeneratedPluginRegistrant
      │  │  ├─ pages/Index.ets                    # FlutterPage 宿主页（@Entry，LocalStorage viewId）
      │  │  └─ plugins/GeneratedPluginRegistrant.ets  # 工具生成、已 gitignore；此处留空实现兜底
      │  └─ resources/
      │     ├─ base/element/{color.json, string.json}   # 含 CAMERA/MIC 的 reason 文案
      │     ├─ base/media/icon.png
      │     ├─ base/profile/{main_pages.json, buildinfo.json5}  # buildinfo: enable_impeller=true
      │     ├─ en_US/element/string.json / zh_CN/element/string.json
      │     └─ （构建后生成 rawfile/flutter_assets、rawfile/buildinfo.json5，已 gitignore）
      └─ ohosTest/                  # DevEco 测试模块模板（assembleHap 不参与，保留完整性）
```

构建期由工具生成、**不要提交**的文件（`.gitignore` 已覆盖）：
`build/`、`oh_modules/`、`node_modules/`、`.hvigor/`、`oh-package-lock.json5`、`package.json`、`package-lock.json`、`local.properties`、`**/BuildProfile.ets`、`entry/src/main/resources/rawfile/flutter_assets/`、`entry/.../plugins/GeneratedPluginRegistrant.ets`。

> 生成方式说明：本任务环境下 `flutter create --platforms ohos .` 无法执行（沙箱子进程限制），因此 `repo/ohos`
> 是**从 Flutter SDK 自带模板** `tools/flutter/packages/flutter_tools/templates/app/ohos.tmpl/` 逐文件展开并定制的，
> 与 `flutter create` 产物等价（后续 `flutter build hap` 会正常识别 `ohos/` 目录，无需 `.metadata` 标记）。

---

## 3. 关键配置与取值依据

### 3.1 `build-profile.json5`（工程级）

```json5
"signingConfigs": [],                     // ★ 必须空数组，见 §6.3
"compatibleSdkVersion": "26.0.0",         // ★ 必须三段式完整版本
"targetSdkVersion": "26.0.0",
"runtimeOS": "HarmonyOS",
"signingConfig": "default",               // 保持默认（无对应配置时 hvigor 产出 unsigned hap）
```

- **API 26 必须写 `"26.0.0"`**：写 `"5.0.5(17)"`（模板默认）或 `"26"` 都会在 hvigor 阶段报 SDK 版本非法。
- 不写 `abiFilters`：架构由 `flutter build hap --target-platform ohos-x64` 通过 `-p TARGET_PLATFORM=ohos-x64` 传给 hvigor 插件，插件自动注入 `flutter_native_x86_64` 等依赖。

### 3.2 `AppScope/app.json5`

- `bundleName = com.fluxdo.app`（任务指定，与 `--org com.fluxdo` 生成的 `com.fluxdo.fluxdo` 不同，**以本文件为准**）。
- `versionCode=2026102016`、`versionName=0.2.29`，来自 `repo/pubspec.yaml` 的 `version: 0.2.29+2026102016`。
- 注意：`flutter build hap` 会用 pubspec 重新覆盖这两个字段（`hvigor_utils.dart:updateProjectVersion`），也会经 hvigor 插件再覆盖一次（`flutter-hvigor-plugin` 读 `local.properties` 的 `flutter.version*`）。三处保持一致即可。

### 3.3 `entry/src/main/module.json5`

**权限**（依据 `docs/ohos-plugin-matrix.md` §3.1，刻意不声明受限权限）：

| 权限 | 场景 |
|---|---|
| `ohos.permission.INTERNET` | 全部网络（dio / rhttp / webview / 图片） |
| `ohos.permission.GET_NETWORK_INFO` | connectivity_plus 网络状态、VPN 自愈 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台保活（配合 `backgroundModes: ["dataTransfer"]`） |
| `ohos.permission.PUBLISH_AGENT_REMINDER` | 代理提醒（本地通知 fork 使用） |
| `ohos.permission.CAMERA` | 扫码登录 / 拍照（user_grant，带 `reason`+`usedScene`） |
| `ohos.permission.MICROPHONE` | 语音消息（user_grant，带 `reason`+`usedScene`） |

`reason` 引用的 `$string:reason_camera` / `$string:reason_microphone` 已写入 base / zh_CN / en_US 三套 `string.json`。
**不要**声明 `READ_IMAGEVIDEO` / `READ_PASTEBOARD` / `NOTIFICATION_CONTROLLER` / `INSTALL_BUNDLE`（受限/系统权限，三方应用拿不到，见矩阵 §3.2）。

**深链 skills**（对应 `lib/services/deep_link_service.dart`）：

```json5
{
  "entities": ["entity.system.browsable"],
  "actions": ["ohos.want.action.viewData"],
  "uris": [{ "scheme": "fluxdo" }, { "scheme": "discourse" }]
}
```

- `fluxdo://topic/123`、`fluxdo://user/xxx`、`discourse://auth_redirect?...` 已注册。
- `https://linux.do/t/`、`/u/`、`/session/email-login/`（Android 侧有 autoVerify intent-filter）需要先在 AGC 做 **App Linking 域名校验**，再在 `uris` 加 `{ "scheme": "https", "host": "linux.do", "pathStartWith": "/t/" }`；未校验就声明会被系统忽略/告警，故暂未写入（module.json5 内有 TODO 注释）。

### 3.4 图标

- 现状：`AppScope/resources/base/media/app_icon.png`、`entry/src/main/resources/base/media/icon.png`（及 ohosTest）暂用 `repo/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`（192×192）拷贝而来。
- **TODO**：用 `repo/assets/logo.svg` / `logo_modern.svg` 转 1024×1024（应用图标）与 216×216（Ability 图标）。本机没有 ImageMagick/inkscape/rsvg，node 也没装 sharp；建议在 CI（或任一装有 `sharp-cli`/`resvg` 的机器）转换后替换，或改用 DevEco Studio 的 Image Asset 工具。

### 3.5 `local.properties`（工具生成，不入库）

```properties
hwsdk.dir=D:\\DevEco Studio\\sdk
nodejs.dir=D:\\DevEco Studio\\tools\\node
flutter.sdk=C:\\Users\\iceblock\\fluxdo\\tools\\flutter
flutter.versionName=0.2.29
flutter.versionCode=2026102016
```

- hvigor 插件从这份文件读取 `flutter.sdk`（`flutter-hvigor-plugin.ts` 第 55–56 行）与版本号，**换机器时路径必须刷新**；正常流程中 `flutter build hap` 会自动重写（`updateLocalProperties`）。
- 该文件已被 `ohos/.gitignore` 忽略；本任务预置了一份可直接用的默认值，保证首次裸构建也能找到 SDK。

### 3.6 `buildinfo.json5`

`entry/src/main/resources/base/profile/buildinfo.json5` 里 `enable_impeller=true`（与 hello 一致）。构建时 Flutter 工具会把它**移动**到 `rawfile/buildinfo.json5`（`copyFlutterBuildInfoFile`，源文件会被删除），这是正常行为，不要手工补回。

---

## 4. 构建

### 4.1 一键脚本（推荐）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
.\tools\build-ohos.ps1 -Install -Launch
```

参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Mode` | `debug` | `debug` / `profile` / `release` |
| `-Arch` | `ohos-x64` | `ohos-x64`（模拟器）/ `ohos-arm64` / `ohos-arm`（真机） |
| `-Flavor` | `default` | 产物目录 `entry\build\<flavor>\outputs\<flavor>` |
| `-BundleName` | `com.fluxdo.app` | 签名用 |
| `-OutHap` | `.cache\ohos-build\fluxdo-<mode>-<arch>-signed.hap` | 签名产物路径 |
| `-NoSign` | 关 | 只构建，输出 unsigned hap |
| `-NoCodesign` | 关 | 给 flutter 传 `--no-codesign`（跳过“未配置签名”检查，exit 0） |
| `-PubGet` | 关 | 构建前先 `flutter pub get`（改过 pubspec 后用） |
| `-SkipBuild` | 关 | 跳过 flutter build，直接对 `entry\build\...` 里已有 HAP 做签名/安装（重签名、离线复用产物时用） |
| `-Install` / `-Launch` | 关 | 构建签名后 `hdc install -r` / `aa start` |
| `-Device` | `127.0.0.1:5555` | hdc 目标 |

脚本行为：

1. dot-source `env.ps1` → 校验 flutter / `repo\ohos` 存在 → 日志写到 `.cache\ohos-build\logs\build-<mode>-<arch>-<时间戳>.log`；
2. `flutter build hap --<mode> --target-platform <arch>`（完整 stdout/stderr 落日志）；
3. 在 `entry\build\<flavor>\outputs\<flavor>` 找最新 `*-unsigned.hap`（兜底全量扫描 `entry\build`），**exit code=1 但产物存在也继续**；
4. 无产物时打印日志里最后 40 条错误行，并按错误特征给出“环境问题（沙箱/权限）”或“依赖/lib 问题”的提示；
5. 调 `tools\ohos-sign.ps1` 签名；6. 按需 install / start，并打印截图命令。

### 4.2 手工等价命令

```powershell
cd C:\Users\iceblock\fluxdo\repo
flutter build hap --debug --target-platform ohos-x64
# 产物：repo\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap
& C:\Users\iceblock\fluxdo\tools\ohos-sign.ps1 -BundleName com.fluxdo.app `
    -InHap C:\Users\iceblock\fluxdo\repo\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap `
    -OutHap C:\Users\iceblock\fluxdo\.cache\ohos-build\fluxdo-debug-x64-signed.hap
```

### 4.3 退出码语义（重要，别被 exit 1 骗了）

`signingConfigs` 为空时，`flutter build hap` 的流程是：
`flutter assemble（Dart 编译）→ hvigorw assembleHap（产出 unsigned hap）→ checkOhosSignedInfo()`。
最后一步发现 `signingConfigs: []` 会直接 `throwToolExit`：

```
请通过DevEco Studio打开ohos工程后配置调试签名(File -> Project Structure -> Signing Configs 勾选Automatically generate signature)
```

**此时 exit code=1，但 `entry-default-unsigned.hap` 已经产出**（见 `ohos_builder.dart`/`hvigor.dart` 的 `checkOhosSignedInfo`）。
→ `build-ohos.ps1` 把“exit≠0 且有 unsigned hap”视为正常，继续签名。
→ 也可加 `-NoCodesign` 跳过该校验，让 flutter 正常 exit 0。

### 4.4 本机（子代理）实测失败点

本任务执行者的 DSH 子代理会话是 workspace-write 沙箱：**禁止程序创建带管道的子进程**。实测对照实验：

```powershell
# node 子进程带管道 → 被拒
node -e "require('child_process').spawnSync('git',['--version'])"   # status=null, error.code=EPERM
# node 子进程继承 stdio → 正常
node -e "require('child_process').spawnSync('git',['--version'],{stdio:'inherit'})"  # status=0
```

因此 `dart`（Flutter 工具本体）拉起 `git` 时必然失败：

```
CreateFile failed 5 (拒绝访问)
Error: Flutter failed to run "git -c log.showSignature=false log -n 1 --pretty=format:%H".
        The flutter tool cannot access the file or directory.
#7  Git.runSync (package:flutter_tools/src/git.dart:114)
#9  new FlutterVersion (package:flutter_tools/src/version.dart:117)
```

日志留存：`.cache\ohos-build\logs\build-debug-ohos-x64-20261021-130153.log`。
**结论：repo 首次构建必须在 Lead 的完整权限会话里执行**（dsource env → `.\tools\build-ohos.ps1`），
届时才会暴露真正的依赖/插件错误（task-4/task-5 的输入），见 §8。

---

## 5. 签名（`tools/ohos-sign.ps1`，本次已重写修复）

### 5.1 原理

不依赖华为账号 / DevEco GUI：用 SDK 自带的 **OpenHarmony 默认证书链 + debug profile 模板** 现场生成
`provisioning profile(p7b)` 和签名 HAP：

1. 从 `D:\DevEco Studio\sdk\default\openharmony\toolchains\lib\OpenHarmony.p12` 导出 leaf/CA/root 证书（缺失时自动导出）；
2. 取 SDK 的 `UnsgnedDebugProfileTemplate.json`，替换 `bundle-name`、`debug-info.device-ids`（当前设备 UDID）、uuid、有效期；
3. `hap-sign-tool.jar sign-profile` → `.cache\signing\profile-tpl.p7b`；
4. `hap-sign-tool.jar sign-app` → 输出 signed HAP。

```powershell
& C:\Users\iceblock\fluxdo\tools\ohos-sign.ps1 -BundleName com.fluxdo.app -InHap <unsigned.hap> -OutHap <signed.hap>
# 可选 -Udid <40位UDID>（默认自动 hdc shell bm get -u 获取）
```

### 5.2 本次修复的两个实际 bug

1. **`ohos-sign.ps1` 无 UTF-8 BOM**：Windows PowerShell 5.1 把无 BOM 的 UTF-8 当 GBK 解析，中文注释后的换行被吞，`$tplRaw = Get-Content ...` 整行变成注释，于是 `ConvertFrom-Json` 收到 null：
   `无法将参数绑定到参数"InputObject"，因为该参数是空值 ... $tpl = $tplRaw | ConvertFrom-Json`。
   → 已把脚本改成 **UTF-8 with BOM**，并在文件头注释里写明约束（以后编辑请保持 BOM）。
2. **hap-sign-tool 不覆盖已存在的输出文件**：重复签名时报
   `ERROR: 11012003 Write file failed / No permission write to file ...profile-tpl.p7b`（不是权限问题！）。
   → 脚本现在每次签名前先删除旧的 `profile-tpl.p7b` 和目标 HAP。

另外把 `cmd /c *.bat` 改成 PS 直接调 `java -jar`（更容易拿到真实退出码），日志落 `.cache\signing\sign-*.log`。

### 5.3 实测结果（hello HAP 复验）

```text
[ohos-sign] bundle=com.fluxdo.hello udid=454D55057494E058383609D94A75277F44F029C4E9A784E7E4F9600000000000
[ohos-sign] sign-profile ...
[ohos-sign] sign-app ...
SIGNED: C:\Users\iceblock\fluxdo\.cache\ohos-build\hello-signed.hap (103583725 bytes) bundle=com.fluxdo.hello ...
```

---

## 6. 安装 / 启动 / 截图（已实测）

```powershell
$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

# 1) 设备
& $hdc list targets                      # 127.0.0.1:5555
# 2) 安装（-r 覆盖安装）
& $hdc -t 127.0.0.1:5555 install -r C:\Users\iceblock\fluxdo\.cache\ohos-build\hello-signed.hap
#    → [Info]App install path:... msg:install bundle successfully.   AppMod finish
# 3) 启动
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.fluxdo.hello
#    → start ability successfully.
# 4) 确认进程
& $hdc -t 127.0.0.1:5555 shell ps -ef | Select-String 'hello'
#    → 20020064  6723  136  com.fluxdo.hello
# 5) 截图
& $hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/hello-verify.jpeg
& $hdc -t 127.0.0.1:5555 file recv /data/local/tmp/hello-verify.jpeg .\hello-verify.jpeg
```

实测截图（Flutter Demo 正常渲染）：`C:\Users\iceblock\fluxdo\.cache\ohos-build\hello-verify.jpeg`（1256×2760 JPEG）。
正式安装 FluxDO 时把 `-b com.fluxdo.hello` 换成 `-b com.fluxdo.app`、HAP 换成 build-ohos.ps1 产出的 signed HAP 即可。

调试辅助：

```powershell
& $hdc -t 127.0.0.1:5555 shell hilog -r            # 看系统日志
& $hdc -t 127.0.0.1:5555 shell aa dump -a         # 已启动的 Ability
& $hdc -t 127.0.0.1:5555 shell bm dump -n com.fluxdo.app   # 已安装 bundle 信息
& $hdc -t 127.0.0.1:5555 uninstall com.fluxdo.app # 卸载
```

---

## 7. 已踩坑清单（症状 → 原因 → 解决）

1. **hvigor 启动即报 symlink/EPERM** → pnpm 默认用 symlink 建 node_modules，Windows 无开发者模式不允许 → `env.ps1` 注入 `NODE_OPTIONS=--require tools\node-symlink-fallback.js`（把 symlink 降级 junction）+ `npm_config_node_linker=hoisted`。**不要绕过 env.ps1**。
2. **hvigor 报 SDK 版本非法** → `compatibleSdkVersion` 必须是 `"26.0.0"` 三段式；`"5.0.5(17)"`（Flutter 模板默认）在 DevEco 26 上不可用。
3. **hvigor 报签名密码相关错误** → hvigor 的签名 material 要求加密密码（长度≥32），明文 "123456" 会失败 → 工程 `signingConfigs` 保持 `[]`，构建后用 `ohos-sign.ps1` 签名。
4. **`flutter build hap` 最后 exit 1，提示“请通过DevEco Studio…配置调试签名”** → 预期行为，unsigned HAP 已产出（§4.3）；脚本容错。
5. **`.ps1` 脚本中文注释导致莫名 `$xxx` 为 null / 行号错乱** → Windows PowerShell 5.1 用 ANSI(GBK) 解析无 BOM UTF-8，注释吞换行 → 所有本目录带中文的 `.ps1` 必须存成 **UTF-8 with BOM**（`tools\ohos-sign.ps1`、`tools\build-ohos.ps1` 已处理；`env.ps1` 目前无 BOM 但全是 ASCII 逻辑，暂时无碍）。用 `[IO.File]::WriteAllText($f, $txt, (New-Object System.Text.UTF8Encoding($true)))` 加 BOM。
6. **签名报 `11012003 Write file failed` / “No permission write to file”** → hap-sign-tool 不覆盖已有输出，先删目标文件（脚本已做）。
7. **`flutter` 报 `CreateFile failed 5`、`The flutter tool cannot access the file or directory`** → 沙箱禁止 dart 创建带管道的子进程；须在完整权限会话运行（§4.4）。
8. **不要跑 `flutter create --platforms ohos .`**（本机沙箱跑不了；且会把已定制的 `ohos/` 文件按模板覆盖）→ 脚手架已手工落地，后续只需 `flutter build hap`。
9. **pub 缓存/用户目录被拒（Creation failed, errno = 5）** → 必须用 `env.ps1` 把 `PUB_CACHE`/`HOME`/`TEMP` 指到 workspace 内。
10. **gitcode/HTTPS 证书问题** → git 需 `-c http.sslBackend=openssl`（pub get / 依赖克隆阶段，属 task-4 范围）。
11. **`repo/.metadata` 没有 ohos 平台记录**（当前只有 android/ios/linux/macos/web/windows）→ 对 `flutter build hap` 无影响（工具按 `ohos/` 目录是否存在判断平台，`project.dart:getSupportedPlatforms`）；若需要与 `flutter create` 产物一致，建议**手工**在 `.metadata` 的 `migration.platforms` 末尾追加：
    ```yaml
        - platform: ohos
          create_revision: 650641656fef1d0578f0bc1ed8f7a35087fc99f3
          base_revision: 650641656fef1d0578f0bc1ed8f7a35087fc99f3
    ```
    （revision 取 `tools/flutter` 的 `git rev-parse HEAD`；本文未改该文件——不在 task-6 写入范围。）

---

## 8. 给 task-4 / task-5 的输入（插件与依赖侧）

hvigor 侧机制（读 `tools/flutter/packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts`）：

- 插件读 `repo/.flutter-plugins-dependencies` 的 `plugins.ohos` 列表；对**每个**插件执行：
  - `build-profile overrides[plugin.name] = file:<plugin.path>/ohos`
  - entry 的 oh-package 依赖里加 `plugin.name`
- 也就是说：**凡是声明了 `ohos` 平台实现的插件，其包目录下必须有合法的 `ohos/` 工程**（`ohos/oh-package.json5`、`ohos/src/main/module.json5`、`ohos/hvigorfile.ts`、`ohos/build-profile.json5`），否则 hvigor 在解析依赖阶段就会报错（报错形如找不到 module.json5 / 依赖路径不存在）。
- 反之，**没有 OHOS 实现的插件**必须让它不出现在 `plugins.ohos` 列表里（即 fork/override 的 `pubspec.yaml` 不要声明 `platforms: ohos`），否则需要自己补 `ohos/` 桥。
- 插件还依赖 `local.properties` 的 `flutter.sdk` 与入口 `entry/hvigorfile.ts` 保持 `system: hapTasks, plugins: []` 形式（本工程已是该形式，**勿改**）。

预计 `repo` 首次真实构建会按这个顺序暴露问题，排查顺序：

1. `flutter pub get`（插件解析、git 依赖 ref、TLS）；
2. `flutter assemble`（Dart 编译：lib 层平台分支 / 插件 Dart API）；
3. `hvigorw assembleHap`（ohos 工程、插件 `ohos/` 模块、oh-package 依赖、签名配置、SDK 版本）；
4. 签名/安装/启动（本笔记 §5/§6 已验证工具链本身 OK）。

构建日志：`.cache\ohos-build\logs\build-<mode>-<arch>-<时间戳>.log`，脚本失败时会把最后 40 条错误行直接打印到终端。

---

## 9. Lead 验收清单（完整权限会话执行）

```powershell
cd C:\Users\iceblock\fluxdo
Set-ExecutionPolicy -Scope Process Bypass -Force; . .\tools\env.ps1
flutter --version                                   # 3.47.7 oh-3.47.7-preview
hdc list targets                                    # 127.0.0.1:5555
git -C repo status --short | Select-String 'ohos'   # 新建 ohos/ 目录
.\tools\build-ohos.ps1                             # ① 首次构建：把失败日志交给 task-4/5
# 依赖/代码修复后：
.\tools\build-ohos.ps1 -Install -Launch             # ② 端到端：构建→签名→安装→启动
& hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/fluxdo.jpeg
& hdc -t 127.0.0.1:5555 file recv /data/local/tmp/fluxdo.jpeg .\fluxdo.jpeg
```

验收通过标准：
- `repo\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap` 存在；
- `.cache\ohos-build\fluxdo-debug-ohos-x64-signed.hap` 存在；
- `hdc install` 输出 `install bundle successfully`；
- `aa start` 输出 `start ability successfully`，截图能看到 FluxDO UI（不再是 hello 的 Demo 页）。
