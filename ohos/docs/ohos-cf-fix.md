# HarmonyOS 7 上 Cloudflare 403 专项修复（task-7）

> 更新：2026-10-21（第 4 轮：回退第 3 轮的「浏览器栈优先」回归，恢复可用性）
> 目标：让 FluxDO 在 HarmonyOS 7（API 26 模拟器）上通过 linux.do 的 Cloudflare 盾
> 关联：`docs/ohos-port-status.md` §2（现象）、§6（复现命令）
> 第 1 轮（cookie 同步诊断）§1~§5；第 2 轮（假 200 误判根因）；第 3 轮（浮层 UX）§7；
> 第 4 轮（回归修复）§8。

---

## 1. 结论（第 2 轮，已由实测日志确认）

**根因不是 cookie 同步丢失，而是「验证在 CF 挑战真正开始前就被判定通过」。**

实测日志关键三行：

```
[CookieStrategy][OHOS] read url=https://linux.do primary=4 merged=4 names=4 hasCfClearance=false
[CfChallenge] main frame verification navigation reached origin (200)，验证入口当前无盾，结束验证页面
[CfChallenge][OHOS] 6s 内未从 ArkWeb 读到 cf_clearance（探测 14 次）
```

`main frame verification navigation reached origin (200)` 只可能来自
`_CfChallengePageState._handleVerifyNavigationResponse()`（`onNavigationResponse` 回调）。
而 **`flutter_inappwebview_ohos` 的这条回调是伪造的**：

`...\flutter_inappwebview_ohos\ohos\src\main\ets\components\plugin\webview\in_app_webview\InAppWebViewClient.ets`

```ets
// onLoadIntercept = 主文档「请求发出之前」
if (customSettings.useOnNavigationResponse && request.isMainFrame()) {
  return this.handleOnNavigationResponse(requestUrl, request.isMainFrame());
}

private buildNavigationResponseMap(url, isForMainFrame) {
  ...
  responseMap.set('headers', new Map<string, Any>());  // ← 恒空 Map
  responseMap.set('statusCode', 200);                  // ← 恒 200
}
// ALLOW 分支：cancel 原请求 + setTimeout(loadUrl) 重放
//   "ArkWeb does not reliably resume the original load after a sync wait"
```

后果（两个叠加）：

1. `_isVerifyOriginResponse()` 看到 `url=/challenge`、`statusCode=200`、`headers={}`
   → `cf-mitigated` 判据失效 → 返回 true → **验证立即「成功」结束，CF 挑战页根本
   还没加载/还没跑 JS**，ArkWeb 自然永远拿不到 `cf_clearance`（实测只有 4 枚非
   HttpOnly cookie：`g_state/_cfuvid/_ga/_ga_1X49KS6K0M`）；
2. 该分支还返回 `NavigationResponseAction.CANCEL`，OHOS 插件据此取消原导航
   （`onLoadIntercept` 返回 true）+ 用 `loadUrl` 重放，会进一步打断 challenge 的
   POST / 重定向。

这解释了为什么第 1 轮的三条猜想（HttpOnly 导不出 / 深层 URL 过滤 / cookie 落地
延迟）都不成立：**ArkWeb 里压根没有这枚 cookie，因为它没真正过盾。**

> 宿主机 Node 直连的对照实验（Lead 做的）：`status 403, server cloudflare,
> cf-mitigated: challenge` —— 原生非浏览器栈一律被挑战，**必须靠 WebView 会话**。

---

## 2. 本轮改动（对应 Lead 的优先级 1/2/3）

### 2.1 修正「假 200」误判 —— 根因修复（优先级 1）

`repo/lib/services/cf_challenge_service.dart`

- `_buildChallengeWebView` 的 `initialSettings`：
  ```dart
  useShouldOverrideUrlLoading: !PlatformUtils.isOhos,
  useOnNavigationResponse: !PlatformUtils.isOhos,
  ```
  OHOS 上让 ArkWeb **像真实浏览器一样自己跑完导航**，只保留真实回调：
  `onLoadStart / onLoadStop / onProgressChanged / onReceivedHttpError /
  onReceivedError` + DOM 探测 + JS 桥（`onChallengeNavigation`）。
- `_handleVerifyNavigationResponse()`：OHOS 直接 `ALLOW` 并打日志
  `[CfChallenge][OHOS] 忽略 onNavigationResponse（插件伪造 status/headers）`，
  双保险（即使插件仍回调也不会误判）。
- `_schedulePageReadyFallback()` / `_scheduleLoadStopFallback()`：把 OHOS 也纳入
  定时兜底（原先只对 Windows/Linux 开），防「某次导航没触发 onLoadStop」时验证页
  永久挂起（连超时计时器都不会启动）。
- 新增判定关键日志（前缀保持 `[CfChallenge]`，方便 hilog grep）：
  - `[CfChallenge][OHOS] pageReady via <reason>` —— 证明 onLoadStop 通路正常；
  - `[CfChallenge][OHOS] 检测到挑战页，交给 ArkWeb 自行过盾` —— 证明真的看到了盾；
  - `[CfChallenge][OHOS] 结束验证: seenChallenge=<bool> reason=<...>` ——
    **seenChallenge 必须为 true**，否则又是「没见盾就结束」的误判；
  - `[CfChallenge][OHOS] clearance 归因: webView=<n chars|absent> jar=<...>`
    —— 挑战跑完后 ArkWeb 里到底有没有这枚 cookie。

### 2.2 让「自动切浏览器网络栈」真正触发（优先级 1）

上一轮写的兜底没触发，原因已定位：`requestCanUseWebViewAdapter()` 把
**HTML 导航请求（`Accept: text/html`）和非 XHR 的 GET 一律排除**，而失败的正是
`GET https://linux.do/`（首页预加载）→ `canUseBrowserStack=false`。

`repo/lib/services/network/adapters/platform_adapter.dart`

- OHOS 上放宽这两条限制（`ohosAllowNavigationFetch`）：主站（`canUseWebView` 已限定
  host==linux.do）的 HTML GET 也允许交给 WebView 适配器；二进制流仍排除。
  这样 `PreloadedData` 首页、话题页 HTML 都能由 ArkWeb 内核带 cookie 去取。

`repo/lib/services/network/interceptors/cf_challenge_interceptor.dart`

- 新增判定行（无论是否触发兜底都打，避免下次再「猜」）：
  ```
  [Dio][OHOS] 重试仍被 CF 挡: hasClearance=<0|1> canUseBrowserStack=<0|1> autoFallback=<0|1> silent=<0|1>
  ```
- 自动兜底成功：
  `[Dio][OHOS] 浏览器网络栈重放成功: status=200 url=...`。
- 兜底失败：记一次 `startIneffectiveClearanceCooldown()`（60s 冷却），避免每个请求
  反复弹验证页（原代码在 fallback 失败分支提前 return，跳过了冷却）。
- 静默请求也覆盖（原逻辑 `!isSilent` 才询问；启动期请求因此直接失败）。
- **验证没拿到成功结果时也兜底**：`result != true`（用户取消 / 超时 / 冷却期 / 无 UI）
  时，OHOS 上同样直接切浏览器网络栈重放一次并保持兼容模式，日志：
  `[Dio][OHOS] 验证未成功(result=...)，直接切浏览器网络栈重放: <METHOD> <URL>`
  → 成功 `[Dio][OHOS] 浏览器网络栈重放成功: status=...`。
  这样即使 ArkWeb 某次挑战失败/被用户关掉，也不会把用户丢在 403 错误页。

### 2.3 OHOS 强制浏览器网络栈方案（优先级 3，已实现但默认关闭）

`repo/lib/services/network/webview/webview_adapter_settings_service.dart`

```dart
/// HarmonyOS 上强制把主站请求交给 ArkWeb 网络栈（不写 SharedPreferences）。
static bool forceWebViewTransportOnOhos = false;

/// 运行时切换（立即重算 effectiveEnabled）
void applyOhosForceTransport(bool value);
```

- `_syncEffectiveEnabled()` 现在 = `enabled || sessionFallbackEnabled || ohosForceTransportEnabled`。
- 打开方式（二选一）：
  1. 代码：`WebViewAdapterSettingsService.forceWebViewTransportOnOhos = true;`
     （改默认值，或在 `main()` 初始化后、首个请求前设置）；
  2. 运行时：调用 `WebViewAdapterSettingsService.instance.applyOhosForceTransport(true)`。
- 打开后**所有主站请求**都走 `WebViewHttpAdapter`（WebView 内 JS fetch，天然带
  ArkWeb 的 HttpOnly cookie），完全不依赖 cf_clearance 能不能导出。
- 为什么默认关闭：优先让「CF 自愈 → 验证通过后同步 clearance → 原生请求」这条快路径
  跑一次，用 §4 的日志确认 ArkWeb 现在到底有没有这枚 cookie；若没有或反复弹盾，
  再打开本开关（最终兜底，代价是主站请求都经 WebView，比原生慢）。

---

## 3. ArkWeb 的 cookie 能力边界（Lead 问题 2 的结论：不需要 ArkTS 桥）

查了 API 26 SDK 的 `D:\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.web.webview.d.ts`，
`WebCookieManager` 的**全部** cookie 读接口是：

| 接口 | 返回 | 说明 |
|---|---|---|
| `fetchCookieSync(url, incognito?)` | `string` | "obtain all cookie values. Cookie values are separated by semicolons" —— 即该 URL 的 **Cookie 头**（含 HttpOnly） |
| `fetchCookie(url)` 系列 | `Promise<string>` / callback | 同上，异步版 |
| `getCookie(url)` | `string` | 已标记 `@deprecated`，等价 `fetchCookieSync` |
| `configCookie* / saveCookie* / clearAllCookiesSync / clearSessionCookieSync` | — | 只有写/删 |

**没有任何接口能返回 cookie 属性**（domain/path/HttpOnly/expires），也没有
`getAllCookies`。inappwebview 的 `MyCookieManager.ets` 已经用了能力最强的
`fetchCookieSync`，因此**写 ArkTS 桥读「全量 cookie」不会比现有链路多出任何信息**
——桥能拿到的也只是同一串 `name=value`。`fetchCookieSync` 文档明确是「all cookie
values」，理论上包含 HttpOnly；本轮修好挑战判定后，`[CfChallenge][OHOS] clearance
归因` 这行就能给出结论（`webView=<n chars>` 即表示 HttpOnly 可读）。

> 结论：**不需要 ArkTS cookie 桥**；若 `webView=absent`，说明挑战仍未通过，回到 §5-③。

---

## 4. Lead 验证步骤

> 需要 `danger-full-access`（沙箱禁止 dart 创建子进程）。

### 4.1 构建前静态检查（可选）

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; . C:\Users\iceblock\fluxdo\tools\env.ps1
cd C:\Users\iceblock\fluxdo\repo
flutter analyze lib
```

本会话已用 Lead 的 `.tmp/analyzerproj`（`dart run bin/analyze.dart`）验证：
`lib/services/cf_challenge_service.dart` + `lib/services/network` →
`SUMMARY files=72 errors=0 warnings=0`。

### 4.2 构建 / 安装 / 启动

```powershell
C:\Users\iceblock\fluxdo\tools\build-ohos.ps1 -Install -Launch
```

### 4.3 抓日志（等首页加载/验证流程跑完，约 30~90s）

```powershell
$hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell hilog |
  Select-String '\[Dio\]|\[CfChallenge\]|\[BoundarySync\]|CookieStrategy|WebViewAdapter|\[VERIFY\]' |
  Tee-Object C:\Users\iceblock\fluxdo\.cache\cf-fix-hilog2.txt
```

### 4.4 判据（按顺序看）

| # | 日志 | 结论 |
|---|---|---|
| A | `[CfChallenge][OHOS] pageReady via onLoadStop` | onLoadStop 通路正常 |
| B | `[CfChallenge][OHOS] 检测到挑战页，交给 ArkWeb 自行过盾` | **挑战真的开始跑了**（上一轮没有这行） |
| C | `[CfChallenge][OHOS] 结束验证: seenChallenge=true reason=...` | 挑战跑完才结束（`seenChallenge=false` 即仍误判） |
| D | `[CfChallenge][OHOS] clearance 归因: webView=<n chars> jar=<n chars>` | **核心判据**：ArkWeb 有没有 cf_clearance / 有没有进 jar |
| E | `[Dio] Retry cookies: ✓ 包含 cf_clearance` + 首页正常 | **理想达标**（原生链路全通） |
| F | `[Dio][OHOS] 重试仍被 CF 挡: hasClearance=0 canUseBrowserStack=1 autoFallback=1` → `[Dio][OHOS] 浏览器网络栈重放成功: status=200` | **兜底达标**（走 ArkWeb 网络栈，功能可用） |
| F2 | `[Dio][OHOS] 验证未成功(result=...)` → `[Dio][OHOS] 浏览器网络栈重放成功: status=200` | 同上（验证被取消/超时时的兜底） |

三种结果对应的下一步见 §5。

---

## 5. 结果分支与下一步

### ① D 行 `webView=<n chars>`、`jar=<n chars>` 且 E 行出现 → 完成

ArkWeb 过盾并签发了可读的 `cf_clearance`，原生链路恢复正常。

### ② D 行 `webView=<n chars>` 但 `jar=absent` → 只剩持久化问题

说明读得到、写不进 jar。下一步：抓应用内 `LogWriter` JSON（cookie_trace /
`[BoundarySync]` 落盘日志），看 `saveFromResponseTrusted` 之后的 domain/hostOnly；
重点怀疑 OHOS 返回的 cookie 没有 domain 属性时走了哪条兜底分支。

### ③ D 行 `webView=absent`（挑战跑完仍没 cookie）→ 走兜底 / 强制模式

说明 CF 对 ArkWeb 仍不放行（UA/指纹判定）。按顺序：
1. 确认 F 行出现且首页能加载 —— 即浏览器网络栈兜底已生效，功能可用；
2. 若 F 行没出现，看紧随的 `[WebViewAdapter] Init failed:` / `[WebViewAdapter]`
   错误（JS bridge 或 CORS 不可用）；此时打开 §2.3 的强制开关再试；
3. UA 方向（`lib/constants.dart`，**不在本任务写入范围**）：OHOS 上
   `AppConstants.initUserAgent()` 取的是 `WebviewController.getDefaultUserAgent()`，
   `_sanitizeUserAgent()` 没有 OHOS 分支 → dio 与 WebView 都会带
   `OpenHarmony ... ArkWeb/x.y Mobile`。CF 对 ArkWeb UA 的判定与主流 Chrome UA
   不同，建议给 OHOS 补一段 sanitize，把 UA 归一成 Android Chrome，并保证
   dio / WebView 两侧字符串完全一致（UA 是 cf_clearance 的绑定因子之一）。

---

## 6. 回滚

```powershell
cd C:\Users\iceblock\fluxdo\repo
git checkout -- lib/services/cf_challenge_service.dart `
                lib/services/network/interceptors/cf_challenge_interceptor.dart `
                lib/services/network/adapters/platform_adapter.dart `
                lib/services/network/webview/webview_adapter_settings_service.dart `
                lib/services/network/cookie/boundary_sync_service.dart `
                lib/services/network/cookie/strategy/platform_cookie_strategy.dart
Remove-Item lib/services/network/cookie/strategy/ohos_cookie_strategy.dart
```

只关掉「自动切浏览器网络栈」：把 `cf_challenge_interceptor.dart` 里
`final ohosAutoFallback = ...` 改成 `false && ...`；诊断日志保留。
只关掉 OHOS 强制模式：`forceWebViewTransportOnOhos` 保持 `false`（默认）。

---

## 7. 第 3 轮：UX 收口（冷启动不再弹「安全验证」浮层）

### 7.1 现象与原因

实测（Lead）：CF 修复后数据全部正常，但**每次冷启动**仍会弹一次「安全验证」浮层
（文案「当前没有需要完成的安全验证」）；点浮层里的「重新尝试验证」不消失，必须
「退出」→ 再点底层页面的「重试连接」两步才恢复。

原因有三层：

1. **首个主站请求先走原生栈**：`PreloadedData` 的 `GET https://linux.do/` 走
   dart:io → 必 403（CF 挑战所有非浏览器客户端）→ 触发验证浮层；
2. **浏览器栈兜底发生在「请求失败之后」**，浮层已经弹出来了；
3. **浮层停在 noChallenge 状态不会自愈**：CF 过盾后会先跳一次
   about:blank / 中间页，`_handleVerifyOriginFallback` 的探测窗口（1.8s / 8s）内
   可能拿不到源站文档 → 置 `_originFallbackNeedsAction` → 显示「当前没有需要
   完成的安全验证」+ 重试/退出按钮；此时**没有任何后续探测**，点「重新尝试
   验证」只是重载到同一状态 → 永远不消失。

### 7.2 改动（两条都做了，对应 Lead 的要求 1 与 2）

**A. 冷启动首个主站 GET 直接走浏览器栈（不再先撞 403）**

- `repo/lib/services/network/adapters/platform_adapter.dart`
  `_GatewayAdapterWrapper._shouldUseWebView()` 增加 `_preferBrowserStackOnOhos()`：
  OHOS 上**主站（host==linux.do）的 GET/HEAD**（非二进制流、非 /cdn-cgi/、
  非 message-bus）从第一个请求起就交给 `WebViewHttpAdapter`。
  日志（每会话一次）：
  `[CfChallenge][OHOS] 首次即走浏览器栈: GET https://linux.do/`

- `repo/lib/services/network/adapters/webview_http_adapter.dart`
  OHOS 的适配器引导页从 `data:` 文档改成**真实 origin 文档**：
  1. `loadUrl('https://linux.do/robots.txt')` —— 这次真实导航会让 **ArkWeb 自己
     在 headless 里跑一遍 CF 挑战**（用户不可见）；
  2. `_awaitOhosCfSettled()` 轮询 DOM（400ms/次，上限 10s），等挑战页标记
     （`cf_chl_opt/challenge-running/challenge-stage/cf-turnstile`）消失；
  3. `stopLoading()` + `document.write` 空壳文档（同源 origin=linux.do）；
  4. 之后所有 JS fetch 由 ArkWeb 发出，天然带 `cf_clearance`。
  同时 OHOS 上改用 `WebViewSettings.headlessCf`（不屏蔽图片/不强制缓存策略），
  与验证页配置一致，提高挑战一次通过率。
  日志：`[CfChallenge][OHOS] 浏览器栈 headless 文档已就绪（sawChallenge=...）`
  或 `... 等待 CF 挑战结束超时`。

**B. 兜底成功自动关闭浮层（不需要用户两步）**

- `repo/lib/services/cf_challenge_service.dart`
  - `CfChallengeService.dismissActiveVerificationAsSuccess()`：外部已用浏览器栈
    做成请求时，主动走正常收场路径（`_finishFromOriginResponse` → 清理 Overlay /
    同步 cookie / 放行路由 / 关闭浮层）。页面 State 在 `initState` 登记、`dispose`
    注销。
  - 日志：`[CfChallenge][OHOS] 兜底成功，自动关闭浮层（reason=...）`
  - 新增 **noChallenge 浮层自愈轮询**：进入「当前没有需要完成的安全验证」状态后
    每 1.5s 重探一次（最多 24 次），页面一旦落到源站文档即自动收场，日志：
    `[CfChallenge][OHOS] 浮层自愈：页面已落到源站文档，自动收场（attempt=N）`。
- `repo/lib/services/network/interceptors/cf_challenge_interceptor.dart`
  - **弹浮层之前**先用浏览器网络栈重放（`_replayViaBrowserStack`），成功直接
    返回、全程无感；失败才回退到验证浮层。日志：
    `[CfChallenge][OHOS] 首次即走浏览器栈: <METHOD> <URL> (mode=...)`；
  - 所有兜底重放成功路径统一调用 `dismissActiveVerificationAsSuccess()`；
  - 重放失败会回滚 `skipCfChallenge/skipCfBlock/skipWebViewAdapter` 与临时兼容
    开关，不影响后续原有验证流程。

### 7.3 第 3 轮判据日志

| 日志 | 含义 |
|---|---|
| `[CfChallenge][OHOS] 首次即走浏览器栈: GET https://linux.do/` | 冷启动首个主站 GET 已直接走 ArkWeb（**期望出现**，且随后不应出现验证浮层） |
| `[CfChallenge][OHOS] 浏览器栈 headless 文档已就绪（sawChallenge=true, ...ms）` | headless 里 CF 挑战自己过了（最理想：全程无感） |
| `[CfChallenge][OHOS] 兜底成功，自动关闭浮层（reason=pre_verify / retry_blocked_fallback / verify_incomplete）` | 若曾弹过浮层，已被自动关闭 |
| `[CfChallenge][OHOS] 浮层自愈：页面已落到源站文档，自动收场（attempt=N）` | 停在 noChallenge 的浮层自行消失 |
| `[CfChallenge][OHOS] 浏览器栈 headless 等待 CF 挑战结束超时` | headless 没能自己过盾（可能是交互式 Turnstile）→ 会回退到验证浮层，由用户点一下 |

验收标准（Lead 的判定）：**冷启动后无需任何手动点击即可看到话题列表**。
若仍弹浮层：看是「headless 等待超时」还是「首次即走浏览器栈未成功」，
再考虑打开 §2.3 的 `forceWebViewTransportOnOhos = true`（让所有主站请求
含 POST 都走浏览器栈）。

---

## 8. 第 4 轮：回退「浏览器栈优先」回归（恢复可用性）

### 8.1 回归现象（Lead 实测，07:23 冷启动，未点任何按钮）

```
[CfChallenge][OHOS] 首次即走浏览器栈: GET https://linux.do
[WebViewAdapter] Controller created
[CfChallenge][OHOS] 浏览器栈 headless 文档已就绪（sawChallenge=false, 349ms）
[WebViewAdapter] Page loaded: https://linux.do/robots.txt
（之后 70s+ 再无任何 [Dio]/[WebViewAdapter] 日志）
```
界面一直停在启动页；点「跳过」后主框架显示「连接超时」。

### 8.2 根因

第 3 轮的 ①（主站 GET 从第一个请求就交给 WebViewAdapter）+ ②（引导页换成
真实 origin 文档 robots.txt + document.write 空壳）组合在 ArkWeb 上不可用：

- `_awaitOhosCfSettled()` 在 349ms 就判定「文档已就绪（sawChallenge=false）」——
  此时 robots.txt 的导航其实还没真正完成（DOM 只是文档骨架）；
- 紧接着 `stopLoading()` + `document.write` 把这次导航搅乱，之后注入的 JS
  fetch 既没有正常返回、也没有报错，**响应回不到 Dart**；
- 该请求是冷启动首请求（预加载），没有其它请求兜底 → 界面卡在启动页。

结论：**data: 引导页那条路是通的（第 2 轮已验证），真实 origin 引导页不行**。
（ArkWeb 对 `loadData(baseUrl:)` 文档的 origin 处理是 Android 兼容语义，JS fetch
同源可用；而「真实导航 + document.write」组合的时序不可控。）

### 8.3 修复

1. **回退 ①**：`platform_adapter.dart` 删除 `_preferBrowserStackOnOhos()`，
   `_shouldUseWebView()` 恢复第 2 轮行为（只在 `effectiveEnabled` 时走浏览器栈）。
   → 冷启动首请求回到 dio 原生栈（快、必 403），再由拦截器兜底，不再挂死。
2. **回退 ②**：`webview_http_adapter.dart`
   - 引导页恢复 `loadData(data: 空壳, baseUrl: linux.do)`（OHOS 与 Android 同路径）；
   - 恢复 `WebViewSettings.headless`（不再用 headlessCf）；
   - 恢复 `onReceivedError` 完成 `pageLoadCompleter` 的原行为；
   - 删除 `_awaitOhosCfSettled()` / `_isCfChallengeHtml()`。
3. **保留第 3 轮全部浮层改进**（这些是好的，与传输层无关）：
   - 拦截器「弹浮层之前先 `_replayViaBrowserStack`」；
   - `dismissActiveVerificationAsSuccess()` 兜底成功自动关闭浮层；
   - noChallenge 浮层自愈轮询；
   - `forceWebViewTransportOnOhos` 强制开关（默认 false）。
4. **新增「绝不挂死」保证**：
   - `_replayViaBrowserStack` 加 **12s 硬超时**：超时/失败一律回滚会话兼容开关
     并返回 null，让流程继续走验证浮层或错误处理，不会把请求吊住；
   - `webview_http_adapter.dart` 增加 OHOS fetch 打点（hilog 可见）：
     `[WebViewAdapter][OHOS] fetch start ...` / `fetch js eval done` /
     `fetch js error ...` / `fetch timeout ...` / `fetch done status=... bodyLen=...`。
     下次再出现「响应回不到 Dart」，这组日志能直接定位卡在注入、桥回传还是超时。

### 8.4 第 4 轮验收（Lead 冷启动，不点任何按钮）

1. **30s 内出现话题列表**（第 2 轮路径：dio 403 → 兜底 → 浏览器栈出数据）；
2. 日志里能看到 `[WebViewAdapter][OHOS] fetch start` → `fetch js eval done` →
   `fetch done status=200`（或 `fetch timeout`，超时也会自动回退）；
3. 若弹过验证浮层，应出现 `[CfChallenge][OHOS] 兜底成功，自动关闭浮层` 或
   `[CfChallenge][OHOS] 浮层自愈：... 自动收场`，且最终无需手动点击。

若冷启动仍超时：抓 `[WebViewAdapter][OHOS]` 那组打点回传；同时可临时打开
`forceWebViewTransportOnOhos = true` 验证「浏览器栈能不能出数据」，但该开关
同样依赖 `webview_http_adapter` 的 JS fetch 回传，需以打点结论为准。

---

## 9. 第 5 轮（最后一轮）：OHOS 默认强制浏览器栈 + ArkWeb clearance 优先判据

### 9.1 为什么第 4 轮浮层还是不会自动关闭

第 4 轮已确认「不再挂死」，但冷启动 65s 后浮层仍停在「当前没有需要完成的安全
验证」。原因是**验证完成判定仍只依赖 DOM**：OHOS 上 CF 过盾后会先跳一次
中间页/空白页，`_hasLoadedOriginDocument()`（要求 `getUrl()` 仍是 `/challenge`
且 `document.readyState==='complete'` 且无挑战标记）拿不到稳定信号，于是：

- `_handleVerifyOriginFallback` 探测超时 → 置 `_originFallbackNeedsAction`
  → 显示 noChallenge 浮层；
- 而 `showManualVerify` 的 `result` 永远不返回 → 拦截器不会重试、也不会走
  `dismissActiveVerificationAsSuccess`；
- 用户点「重新尝试验证」只是重载同一状态 → 浮层不消失，必须「退出 → 重试连接」。

**关键洞察**：CF 挑战通过后一定会把 `cf_clearance` 写进 ArkWeb 的 cookie store，
而 OHOS 的 `fetchCookieSync(url)` 能读到它（第 2 轮已验证插件用的就是这个 API）。
这比「DOM 是否已到源站」可靠得多，且与浮层 UI 状态无关。

### 9.2 本轮改动

1. **`webview_adapter_settings_service.dart`**：
   `forceWebViewTransportOnOhos` 默认值改为 **`true`**（OHOS 上主站请求从第一个
   起就走 ArkWeb 网络栈）。第 4 轮已把引导页回退为可用的
   `loadData(空壳, baseUrl:linux.do)`，所以不再有第 3 轮的挂死风险。
2. **`platform_adapter.dart`**：OHOS 上 WebView 栈单次 fetch 加 **12s 硬超时**；
   超时/异常时自动 **回退原生 dio** 并关闭本次会话的强制开关
   （`applyOhosForceTransport(false)`），日志：
   `[WebViewAdapter][OHOS] fetch 失败，回退原生并关闭强制浏览器栈: ...`。
   保证「浏览器栈坏掉也不会吊死冷启动」。
3. **`cf_challenge_service.dart`**：新增 **ArkWeb cf_clearance 优先判据**，三处
   探测点（任一命中即按成功收场并关闭浮层）：
   - `_pollVerificationDocument()`（每秒轮询）：
     `[CfChallenge][OHOS] 轮询发现 ArkWeb 已有 cf_clearance（N chars），自动收场`；
   - `_handleVerifyOriginFallback()` 探测循环：
     `[CfChallenge][OHOS] 探测到 ArkWeb 已有 cf_clearance（N chars），判定挑战已通过`；
   - noChallenge 浮层自愈轮询：
     `[CfChallenge][OHOS] 浮层自愈：ArkWeb 已有 cf_clearance（N chars），自动收场（attempt=N）`。
4. 第 4 轮的 12s 硬超时、第 3 轮的 `dismissActiveVerificationAsSuccess`、浮层
   自愈轮询全部保留。

### 9.3 冷启动预期路径（不点任何按钮）

```
[WebViewAdapter][OHOS] fetch start GET https://linux.do id=1
[WebViewAdapter][OHOS] fetch js eval done id=1 (Nms)
[WebViewAdapter][OHOS] fetch done id=1 status=200 bodyLen=...   ← 理想：直接出数据
```
若 ArkWeb 里还没有 clearance（首次装包/过期）：
```
[WebViewAdapter][OHOS] fetch done ... status=403
[CfChallenge][OHOS] 首次即走浏览器栈: GET https://linux.do ...
（验证页在后台/前台跑 CF 挑战）
[CfChallenge][OHOS] 轮询发现 ArkWeb 已有 cf_clearance（N chars），自动收场
[Dio][OHOS] 浏览器网络栈重放成功(pre_verify / retry_blocked_fallback): status=200
```
→ 30s 内出列表。

若 12s 超时回退：
```
[WebViewAdapter][OHOS] fetch 失败，回退原生并关闭强制浏览器栈: TimeoutException...
```
→ 回退到第 4 轮行为（原生 403 → 验证 → 浏览器栈兜底）。**回退后仍能出数据**，
但模拟器环境可能回到「需手动退出 + 重试连接」的两步限制（真实设备住宅 IP 下
CF 通常静默通过，不受影响）。



