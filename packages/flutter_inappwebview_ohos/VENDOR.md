# VENDOR：flutter_inappwebview_ohos（OHOS 适配副本 + JS 调用来源）

| 项 | 内容 |
|---|---|
| 来源仓库 | `https://gitcode.com/CPF-Flutter/flutter_inappwebview.git`，子目录 `flutter_inappwebview_ohos`（原 ref `br_v6.1.5_ohos`） |
| 锁定 SHA | `389cf40dbb647f1df7272de5ea6b3401efe27a75`（与根 pubspec 中 `flutter_inappwebview` / `_platform_interface` 的 git override 同一 commit） |
| 许可证 | Apache-2.0（源文件头部声明） |
| 同步日期 | 2026-11-13 |

## 为什么 vendored

上游 v0.2.30 小程序宿主依赖 inappwebview 6.2.0-beta 的 `JavaScriptHandlerFunctionData`
（`isMainFrame` / `origin` / `requestUrl`）做消息来源校验。鸿蒙只能用 CPF 6.1.5，没有这些信息。
本副本在 ArkTS 侧取得调用方 frame 来源并传到 Dart，供 `lib/modules/mini_apps/mini_app_js_handler_compat.dart` 校验。

## 改动清单（全部带「FluxDO 改动」注释）

1. `pubspec.yaml`：`flutter_inappwebview_platform_interface` 由相对 path
   `../flutter_inappwebview_platform_interface` 改为 `^1.3.0`（vendored 后相对路径失效；
   实际由根 pubspec 的 git override 解析，仍是同一 SHA）。
2. `ohos/.../webview/JavaScriptBridgeInterface.ets`：`_callHandler` 入口同步调用
   `getController().getLastJavascriptProxyCallingFrameUrl()`（try/catch），解析 origin，
   与主文档 URL（忽略 fragment）比较得出 isMainFrame，并传给 channel delegate。
3. `ohos/.../webview/WebViewChannelDelegate.ets`：`onCallJsHandler` 新增 3 个可选参数，
   在发往 Dart 的 map 里**附加** `_ohosFrameUrl` / `_ohosOrigin` / `_ohosIsMainFrame`；既有字段不变。
4. `lib/src/in_app_webview/in_app_webview_controller.dart`：调用 JS handler 前同步设置
   `currentJsCallSource`（`frameUrl` / `origin` / `isMainFrame`），handler 同步部分返回后立即清除。
   handler 签名不变，其他 handler（CF、内置浏览器、WebViewHttpAdapter 等）行为不变。
5. 剔除：`example/`、`test/`、构建产物（`build`、`ohos/build`、`oh_modules`、`.cxx`、`BuildProfile.ets`、lock 文件）。
6. `ohos/.../webview/FrameUrlMatcher.ets`（新增）：真机（HarmonyOS 7 / API 26）上
   `getLastJavascriptProxyCallingFrameUrl()` 返回截断到目录的 URL（`/apps/<uuid>?x` → `/apps/`），
   主框架判定同时接受「完整 URL 相等」与「目录形式相等」。已知风险：同 origin 同目录 iframe 无法区分。
7. `JavaScriptBridgeInterface.ets`：来源日志改 `Log.w`（flutter_ohos 默认 WARN 级别）并按组合限频。
8. `MyCookieManager.ets`：`Expires` 改用 `toUTCString()`（原 `Intl` 输出非法日期）；`deleteCookie(s)`
   的过期串追加 `HttpOnly`（https 再加 `Secure`）——ArkWeb 读不到 HttpOnly 属性，而非 HttpOnly 的
   写入无法覆盖 HttpOnly cookie（`EXCLUDE_OVERWRITE_HTTP_ONLY`）。
9. `in_app_webview/InAppWebView.ets`、`InAppWebViewClient.ets`：https 回环 URL（网络核心指纹探针
   `https://localhost:<port>/fluxdo-probe`）交给 ArkWeb 原生加载，不再经 `@ohos.net.http` 中转
   （后者不信任核心自签证书，且采到的不是浏览器 ClientHello）；证书仍由 Dart 回调仅对核心端点放行。

## 局限

- isMainFrame 靠「调用方 frame URL == 主文档 URL」推断（ArkWeb 无直接接口）。iframe 与主文档
  URL 完全相同会误判为主框架；URL 表示不一致时判为非主框架（fail-closed）。
- `getLastJavascriptProxyCallingFrameUrl` 记录「最近一次」调用，因此必须在 `_callHandler` 入口同步读取。

## 升级/回滚

- 升级：从 CPF 新 commit 重新拷贝，重新应用上面 2–4 的改动，更新本文件 SHA 和根 pubspec。
- 回滚：删除根 pubspec 的 `flutter_inappwebview_ohos` override 与本目录（回到 fork 内相对 path 依赖），
  并把 `compat` 的鸿蒙分支改回不校验（或保持入口隐藏）。
