# DevEco Studio 打开 `repo/ohos` 后 `File → Project Structure` 灰色：诊断与处理

> 环境：DevEco Studio 26.0.0.821（内置 @ohos/hvigor 6.26.4），工程 `C:\Users\iceblock\fluxdo\repo\ohos`

## 1. 结论

`Project Structure` 灰色不是工程文件损坏，而是 **DevEco 的 hvigor 同步（sync）失败**，
IDE 因此禁用了工程结构/签名配置入口。日志证据（`%LOCALAPPDATA%\Huawei\DevEcoStudio26.0\log\idea.log`）：

```
INFO  HvigorRunConfiguration - "D:\DevEco Studio\tools\node\node.exe" "...\hvigorw.js" --sync -p product=default ...
INFO  HvigorRunConfiguration - Launch failed. null
WARN  PreBuildSync - Sync failed! hvigor sync success status: false
WARN  ExternallyAddedFilesProcessorImpl - Cannot find project config directory for non-default and non-directory based project ohos
```

手工复现同一命令，得到三层叠加原因：

| # | 现象 | 根因 | 状态 |
|---|---|---|---|
| 1 | `Invalid value of 'DEVECO_SDK_HOME' in the system environment path` | 系统/用户环境变量未设置 SDK 路径 | ✅ 已修（写入用户级 `DEVECO_SDK_HOME=D:\DevEco Studio\sdk`） |
| 2 | `Failed to find the executable 'node' command` | 同上，`NODE_HOME`/PATH 未包含 DevEco 自带 node | ✅ 已修（`NODE_HOME` + PATH 追加 node/ohpm/hvigor/toolchains） |
| 3 | `ohpm install failed` → `FATAL ERROR: JavaScript heap out of memory` | hvigor 用 `--target_path` 构建依赖图时 ohpm 内存爆炸（本工程 30+ 个本地 `file:` 依赖）；把 node 堆调到 8 GB 仍在 11 分钟后 OOM | ⚠️ 未解（ohpm 侧问题） |

另外发现：**DevEco 安装在带空格的 `D:\DevEco Studio`**（官方要求安装路径不含空格）。
`hvigorw.js` 里 ohpm 路径由 `__dirname` 拼出（`D:\DevEco Studio\tools\ohpm\bin\ohpm.bat`），
而 hvigor 用 `spawnSync(cmd, ['/d','/c', 命令], { windowsVerbatimArguments: true })` 启动它，
空格路径在这种参数传递下会被 cmd 拆断（表现为 `'...' is not recognized ...`）。
这也是偶发 `Failed to find the executable 'node'` 的来源之一。

## 2. 已做的修复（本机）

- 用户级环境变量：`DEVECO_SDK_HOME`、`NODE_HOME`、`JAVA_HOME`、`OHOS_SDK_HOME`，
  并在用户 PATH 追加 `tools\node`、`tools\ohpm\bin`、`tools\hvigor\bin`、`sdk\default\openharmony\toolchains`；
- 用户级 `NODE_OPTIONS=--max-old-space-size=16384`（给 ohpm/hvigor 更大堆，缓解 OOM）；
- 删除过期的 `repo\ohos\.idea`（备份在 `.cache\idea-backup-ohos.zip`），让 IDE 重建工程模型；
- 停止残留 hvigor daemon（daemon 会缓存旧环境，改环境变量后必须 `hvigorw --stop-daemon`）；
- 创建无空格 junction `D:\DevEcoStudio → D:\DevEco Studio`（备用，可删）。

> 改完环境变量后 **必须重启 DevEco Studio** 才会生效（IDE 进程继承的是启动时的环境）。

## 3. 处理建议（按优先级）

### 方案 A：真机测试不需要 Project Structure（最快）

签名由 `tools/ohos-sign.ps1` 用 OpenHarmony 默认证书链完成，CLI 一条命令即可：

```powershell
cd C:\Users\iceblock\fluxdo
.\tools\build-ohos.ps1 -Mode release -Arch ohos-arm64 -Device auto -Install -Launch
```

适用于**开发板 / OpenHarmony 设备 / 已信任 OpenHarmony 根证书的设备**。

### 方案 B：商用 HarmonyOS 设备（需华为证书）

1. **推荐：把 DevEco 重装到无空格路径**（如 `D:\DevEcoStudio`），这是官方要求；
   重装后 `Project Structure` 的签名配置一般即可用。重装后需同步更新：
   - `tools/env.ps1` 的 `$TOOL_HOME`；
   - 用户环境变量 `DEVECO_SDK_HOME` / `NODE_HOME` / `JAVA_HOME` / PATH；
   - `repo/ohos/local.properties` 的 `hwsdk.dir` / `nodejs.dir`。
2. 若重装后 sync 仍因 ohpm OOM 失败，可改用 **AGC 手工签名**（不经过 DevEco）：
   - AppGallery Connect 创建应用 → 申请调试证书 `.cer` + 调试 Profile `.p7b`（Profile 里绑定设备 UDID）；
   - 用 `hap-sign-tool` 或扩展后的 `tools/ohos-sign.ps1`（支持自定义 p12/cer/p7b）签名 HAP；
   - 设备端 `hdc install`。

### 方案 C：让本工程适配 DevEco sync（不推荐，成本高）

ohpm 的 `--target_path` 依赖图 OOM 与 30+ 个 `file:` 本地依赖有关，
需要减少本地依赖数量（例如把插件 HAR 预编译成远程/本地包），改造量大、收益低。

## 4. 复现/验证命令

```powershell
# 1) 复现 DevEco 的同步（改完环境变量后先停 daemon）
& 'D:\DevEco Studio\tools\node\node.exe' 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.js' --stop-daemon
& 'D:\DevEco Studio\tools\node\node.exe' 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.js' --sync -p product=default --debug

# 2) 只看 ohpm 命令行与错误
#    正常应为 "start to execute ohpm install" 后无 FATAL；失败时看 heap out of memory
```

---

## 5. 最终结论（DevEco 重装到无空格路径后）

重装到 **`C:\Users\iceblock\DevEcoStudio`**（无空格）后，按下面顺序处理，`hvigorw --sync` 已 **退出码 0**：

1. 工具链引用全部更新为新路径：
   - `tools/env.ps1` 的 `$TOOL_HOME`；
   - `tools/build-ohos.ps1` / `tools/ohos-sign.ps1` / 各 `.bat` 签名脚本里的 hdc/java/hap-sign-tool 路径；
   - `repo/ohos/local.properties` 的 `hwsdk.dir` / `nodejs.dir`；
   - 用户级环境变量 `DEVECO_SDK_HOME` / `NODE_HOME` / `JAVA_HOME` / `OHOS_SDK_HOME` / `TOOL_HOME` 与 PATH。
2. **修掉真正的拦路虎**：`repo/ohos/build-profile.json5` 里 `targetSdkVersion` 是坏的 `"1"`，
   新 SDK 严格校验直接拒绝（`00306042 Check the project's build-profile.json5`）。
   改成 `"26.0.0"` 后 sync 立即通过（提交 `bcd6680`）。
3. 用户级 `NODE_OPTIONS=--max-old-space-size=16384` 保留（ohpm 依赖图构建吃内存）。

验证命令与结果：

```powershell
cd repo\ohos
& "$env:TOOL_HOME\tools\node\node.exe" "$env:TOOL_HOME\tools\hvigor\bin\hvigorw.js" --sync -p product=default
# → exit=0，日志末尾：Finished :wakelock_plus_harmonyos:init... / Finished ::init...
```

`flutter build hap --release --target-platform ohos-arm64` 也验证通过（114.1 MB，85.6s）。

**所以 `Project Structure` 灰色的两个真实原因**：
① `targetSdkVersion` 值非法（主因，直接导致 sync 失败）；
② DevEco 装在带空格路径（次因，导致 hvigor 启动 ohpm 偶发失败）。

重启 DevEco 后 `File → Project Structure` 应可正常打开并配置签名。

---

## 6. 补充：DevEco 内构建报 "Flutter failed to write to .flutter_tool_state"（已修复）

用户在 DevEco 里点构建（`assembleHap`）时报：

```
Error: Flutter failed to write to a file at "C:\Users\iceblock\AppData\Roaming\.flutter_tool_state".
hvigor ERROR: Failed :entry:default@FlutterTask...  Error Code: 00308018
```

### 根因（关键发现）

DSH 沙箱此前给工作区打过 **Low Mandatory Level（低完整性）标签**：

```
C:\Users\iceblock\fluxdo                    Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)
C:\Users\iceblock\fluxdo\...\dart.exe       Mandatory Label\Low Mandatory Level:(I)(NW)
```

于是**工作区内的 `dart.exe` 以低完整性运行**（实测：同一批处理里 node=Medium、dart=Low），
低完整性进程无法写入 Medium 的 `%APPDATA%`，于是：

| 阶段 | 报错 | 原因 |
|---|---|---|
| Flutter 启动 | `failed to write ...\.flutter_tool_state` | 工具状态文件写不了 |
| Dart native assets | `PathAccessException: Creation failed, path = ...\.dart-tool` | 无法创建目录 |
| 打包 | `spawn java ENOENT` | hvigor daemon 缓存了旧 PATH（无 jbr） |

### 修复

```powershell
# 1) 工作区完整性标签恢复为 Medium（一次性，约 3-6 分钟）
.\tools\fix-integrity-labels.ps1

# 2) 停掉缓存旧环境的 hvigor daemon
& "$env:TOOL_HOME\tools\node\node.exe" "$env:TOOL_HOME\tools\hvigor\bin\hvigorw.js" --stop-daemon
```

修复后实测（DevEco 同款命令）：

```
hvigorw.js --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone \
  assembleHap --analyze=normal --parallel --incremental
→ BUILD SUCCESSFUL in 27 s，entry-default-unsigned.hap 398.5 MB（debug，多 ABI）
```

> 备注：若沙箱以后再次给工作区打 Low 标签（例如新的 DSH 会话以 workspace-write 策略运行），
> 用 `tools\fix-integrity-labels.ps1 -CheckOnly` 检查，需要时再跑修复。
> `%APPDATA%\.flutter_tool_state`、`%APPDATA%\.dart-tool` 已预创建（标签 Medium），可保留。

---

## 7. 补充二：DevEco 构建报 `00305003 Syntax Error: Some type errors hvigorfile.ts`（已修复）

IDE 的构建命令比命令行多一个参数：

```
hvigorw.js --mode module -p product=default assembleHap --analyze=normal --parallel \
  --incremental --enable-build-script-type-check --daemon
```

`--enable-build-script-type-check` 会以 ES2016 + strict 类型检查构建脚本及其依赖，
而 Flutter SDK 自带的 `flutter-hvigor-plugin` 有 4 类类型错误，导致构建失败：

| 错误 | 位置 | 原因 |
|---|---|---|
| `TS2550 replaceAll` | `src/util/file-util.ts` | `replaceAll` 属 ES2021，目标为 ES2016 |
| `TS2339 Property 'name'/'path' does not exist on type 'JSON'` | `src/plugin/flutter-hvigor-plugin.ts` | `findFlutterPlugins` 返回类型写成 `JSON[]` |
| `TS18048 'targetPlatforms' is possibly 'undefined'` | 同上（2 处） | `getParameters` 可能返回 `undefined` |
| `TS7006 Parameter 'plugin' implicitly has an 'any' type` | 同上 | 数组元素未标注类型 |

### 修复（已就地修改 Flutter SDK）

```
tools/flutter/packages/flutter_tools/hvigor/src/util/file-util.ts
tools/flutter/packages/flutter_tools/hvigor/src/plugin/flutter-hvigor-plugin.ts
```

补丁说明见 `docs/patches/flutter-hvigor-plugin-typecheck.patch`。

> 注意：`hvigor/hvigor-config.json5` 里的 `execution.typeCheck: false` **不能**覆盖 IDE 传入的
> `--enable-build-script-type-check`（命令行参数优先），所以必须修源码。

### 验证

```powershell
cd repo\ohos
hvigorw --mode module -p product=default assembleHap --analyze=normal --parallel \
  --incremental --enable-build-script-type-check
→ BUILD SUCCESSFUL in 39 s 965 ms
```

至此 DevEco IDE 内的 Build/Run 与命令行构建都可通过。

---

## 8. 补充三：IDE sync 报 `TS2742 ... hvigor/types`（已修复）

IDE 打开工程时自动跑：

```
hvigorw.js --sync -p product=default --analyze=normal --parallel --incremental \
  --enable-build-script-type-check --daemon
```

报错：

```
error TS2742: The inferred type of 'default' cannot be named without a reference to
'../../../.hvigor/project_caches/<hash>/workspace/node_modules/@ohos/hvigor/types'.
This is likely not portable. A type annotation is necessary.
 at C:/Users/iceblock/fluxdo/repo/ohos/hvigorfile.ts:5:1
```

### 根因

`hvigorfile.ts` 的 `export default { system: xxxTasks, plugins: [...] }` 是**推断类型**，
其类型来自 hvigor 内部缓存目录（`.hvigor/project_caches/<hash>/workspace/node_modules`），
TypeScript 认为该类型“不可移植”，要求显式注解。

> 注意：`@ts-nocheck` **不能**抑制 TS2742（它属于声明生成阶段诊断）；
> `hvigor-config.json5` 里的 `execution.typeCheck: false` 也**不能**覆盖 IDE 传入的命令行开关。

### 修复

给每个 `hvigorfile.ts` 的默认导出对象加 `as any`：

```ts
export default {
    system: appTasks,
    plugins: [flutterHvigorPlugin(path.dirname(__dirname))]
} as any
```

已修复 40 个文件（工程 3 个 + `repo/packages` 示例 + `.pub-cache` 下的插件工程）。
由于 `.pub-cache` 中的补丁可能在 `flutter pub get` / `pub cache repair` 后丢失，
提供了一键脚本：

```powershell
.\tools\fix-hvigorfile-typecheck.ps1          # 重新打补丁
.\tools\fix-hvigorfile-typecheck.ps1 -CheckOnly
```

（配合 §7 的 `docs/patches/flutter-hvigor-plugin-typecheck.patch` 一起，IDE 的
`--enable-build-script-type-check` 即可通过。）

### 验证

```
hvigorw --sync -p product=default --enable-build-script-type-check
  → exit 0，全部模块 init 完成（0 ERROR）
hvigorw --mode module -p product=default assembleHap --enable-build-script-type-check
  → BUILD SUCCESSFUL in 25 s 963 ms
```

**改完记得停 daemon**（会缓存旧的构建脚本解析结果）：

```powershell
& "$env:TOOL_HOME\tools\node\node.exe" "$env:TOOL_HOME\tools\hvigor\bin\hvigorw.js" --stop-daemon
```
