import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../constants.dart';
import '../../../utils/frame_jank_monitor.dart';
import '../../../utils/platform_utils.dart';
import '../../auth_session.dart';
import '../../webview_settings.dart';
import '../../windows_webview_environment_service.dart';
import '../cookie/webview_cookie_priming.dart';
import 'shared_browser_resource.dart';

/// 同源后台任务的唯一实例所有者。业务服务仅持有任务租约。
class SiteWebViewRuntime {
  SiteWebViewRuntime._() {
    _resources = SharedBrowserResource<SiteWebView>(
      create: _create,
      destroy: (view) => view.dispose(),
    );
    AuthSession().generationChanges.addListener(_resources.invalidate);
  }

  static final instance = SiteWebViewRuntime._();
  late final SharedBrowserResource<SiteWebView> _resources;
  final _responses = <String, void Function(String)>{};
  int _nextRequestId = 0;
  int _created = 0;
  Completer<void> _interrupted = Completer<void>();

  Future<void> get interrupted => _interrupted.future;

  Future<void> suspendAndDrain() {
    if (!_interrupted.isCompleted) _interrupted.complete();
    return _resources.suspendAndDrain();
  }

  void resume() {
    _interrupted = Completer<void>();
    _resources.resume();
  }

  String nextRequestId() => 'site_${++_nextRequestId}';

  void registerResponse(String id, void Function(String) callback) {
    _responses[id] = callback;
  }

  void removeResponse(String id) => _responses.remove(id);

  Future<BrowserResourceLease<SiteWebView>> acquire({
    bool exclusive = false,
    Future<void>? cancelled,
  }) => _resources.acquire(exclusive: exclusive, cancelled: cancelled);

  /// 是否有后台任务正在独占 WebView（如启动预加载移交到后台的 session bootstrap）。
  ///
  /// 独占期间经 WebView 适配器的请求只能在 acquire 处排队；HarmonyOS 上排队会
  /// 一直等到适配器 12s 超时，调用方可据此直接改走网络核心。
  bool get backgroundExclusiveBusy => _backgroundExclusive > 0;
  int _backgroundExclusive = 0;

  /// 标记一个后台独占任务的开始；返回的回调在任务结束时调用（可重复调用，仅生效一次）。
  void Function() beginBackgroundExclusive() {
    _backgroundExclusive++;
    var ended = false;
    return () {
      if (ended) return;
      ended = true;
      _backgroundExclusive--;
    };
  }

  Future<SiteWebView> _create() async {
    final view = SiteWebView();
    view.webView = HeadlessInAppWebView(
      webViewEnvironment: Platform.isWindows
          ? WindowsWebViewEnvironmentService.instance.environment
          : null,
      initialSettings: WebViewSettings.headless,
      initialUserScripts: WebViewSettings.compatPolyfillScripts,
      onReceivedServerTrustAuthRequest: (_, challenge) =>
          WebViewSettings.handleServerTrustAuthRequest(challenge),
      onWebViewCreated: (controller) {
        view.controller = controller;
        WebViewSettings.applyWindowsHeadlessMemoryTarget(controller);
        WebViewSettings.registerJsErrorReporter(controller);
        controller.addJavaScriptHandler(
          handlerName: 'fetchResult',
          callback: (args) {
            if (args.isNotEmpty && args.first is Map) {
              final data = args.first as Map;
              final id = data['requestId']?.toString();
              if (id != null) {
                _responses[id]?.call(data['result']?.toString() ?? '');
              }
            }
          },
        );
      },
      onLoadStop: (_, url) => view.didLoad(url),
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true) {
          view.didFail(StateError('后台页面加载失败: ${error.type}'));
        }
      },
    );
    try {
      FrameJankMonitor.logEvent('WEBVIEW', 'SiteRuntime create #${++_created}');
      await view.webView.run();
      try {
        await WebViewCookiePriming.instance.prime(AppConstants.baseUrl);
      } catch (error) {
        debugPrint('[SiteRuntime] Cookie priming 失败，继续初始化: $error');
      }
      await view.resetDocument();
      return view;
    } catch (_) {
      await view.dispose();
      rethrow;
    }
  }
}

/// 仅独占租约可以导航；共享租约只允许在既有文档内执行脚本。
class SiteWebView {
  late final HeadlessInAppWebView webView;
  late final InAppWebViewController controller;
  Completer<void>? _load;

  void didLoad(WebUri? url) {
    // run() 的初始 about:blank 事件不能完成后续同源页面的加载等待。
    if (url == null) return;
    // OHOS 插件的 onPageEnd 回报 loadData 文档时 url 可能是 data: URL（host 为空，
    // 插件仅内部用 baseUrl 映射），而插件按 URL 去重 onLoadStop，重复 loadData 的
    // 同步事件可能被吞掉，原 host 判断会白等满 30s。OHOS 上收到 data: URL 的
    // onLoadStop 即视为本次 loadData 文档加载完成（仅 OHOS 特判，未经真机验证）。
    final isOhosLoadData =
        PlatformUtils.isOhos && url.toString().startsWith('data:');
    if (!isOhosLoadData && url.host != Uri.parse(AppConstants.baseUrl).host) {
      return;
    }
    final load = _load;
    if (load != null && !load.isCompleted) load.complete();
  }

  void didFail(Object error) {
    final load = _load;
    if (load != null && !load.isCompleted) load.completeError(error);
  }

  Future<void> load(
    Future<void> Function() navigate, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final load = Completer<void>();
    _load = load;
    unawaited(load.future.then<void>((_) {}, onError: (Object _) {}));
    try {
      await navigate();
      await load.future.timeout(timeout);
    } finally {
      if (identical(_load, load)) _load = null;
    }
  }

  /// 建立新的同源文档，清掉旧定时器、脚本和桥状态，保留原生实例与 Cookie。
  Future<void> resetDocument() async {
    const html =
        '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        '<body></body></html>';
    if (Platform.isWindows) {
      await load(
        () => controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri('${AppConstants.baseUrl}/robots.txt'),
          ),
        ),
      );
      await controller.evaluateJavascript(
        source:
            'document.open();document.write(${jsonEncode(html)});document.close();',
      );
    } else if (PlatformUtils.isOhos) {
      // OHOS 插件按 URL 去重 onLoadStop：刚加载过 baseUrl 同址页面（如启动预加载的
      // 首页）时，loadData 的完成事件可能被吞掉，永远等不到。loadData 本身已
      // 提交导航，这里只给一个短等待，超时按“已完成”继续，绝不再白等 30s；
      // 若文档确实没换成功，后续 bootstrap 脚本的 origin 检查会快速失败。
      try {
        await load(
          () => controller.loadData(
            data: html,
            baseUrl: WebUri(AppConstants.baseUrl),
            mimeType: 'text/html',
            encoding: 'utf-8',
          ),
          timeout: const Duration(seconds: 4),
        );
      } on TimeoutException {
        debugPrint('[SiteRuntime] OHOS loadData 未收到 onLoadStop，按已加载继续');
      }
    } else {
      await load(
        () => controller.loadData(
          data: html,
          baseUrl: WebUri(AppConstants.baseUrl),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
      );
    }
  }

  Future<void> dispose() async {
    try {
      await webView.dispose();
    } finally {
      if (Platform.isWindows) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      FrameJankMonitor.logEvent('WEBVIEW', 'SiteRuntime dispose');
      debugPrint('[SiteRuntime] 后台实例已回收');
    }
  }
}
