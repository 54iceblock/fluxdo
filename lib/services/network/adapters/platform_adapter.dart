import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../../../l10n/s.dart';
import '../../network_logger.dart';
import '../core/net_core_http_adapter.dart';
import '../core/net_core_service.dart';
import '../flux_request_spec.dart';
import '../cookie/csrf_session_trace.dart';
import '../system_proxy_service.dart';
import '../webview/site_webview_runtime.dart';
import '../webview/webview_adapter_settings_service.dart';
import '../../../utils/platform_utils.dart';
import 'adapter_log_metadata.dart';
import 'core_fallback_service.dart';
import 'webview_http_adapter.dart';

/// 当前使用的适配器类型
enum AdapterType {
  /// 网络核心：进程内 Rust 栈，按 WebView 指纹出站（默认）
  core,

  /// Dart IO 应急路径：核心不可用时顶上，指纹差但能用
  emergency,

  /// WebView 适配器：兼容模式 / CF 恢复 / Windows 兜底
  webview,
}

/// 当前适配器生效的原因（用于 UI 解释"为什么是这个引擎"）
enum AdapterReason {
  /// 核心正常工作
  core,

  /// 核心在跑但指纹模板还没采到，暂按默认档出站
  coreWarmingUp,

  /// 核心不可用，已降级到应急路径
  fallback,

  /// 用户开启了兼容模式
  webview,
}

/// 当前生效的适配器及其原因
class EffectiveAdapter {
  const EffectiveAdapter(this.type, this.reason);

  final AdapterType type;
  final AdapterReason reason;
}

/// 全局变量：记录当前使用的适配器类型
AdapterType? _currentAdapterType;

/// 获取当前使用的适配器类型
AdapterType? getCurrentAdapterType() => _currentAdapterType;

AdapterType? tryParseAdapterType(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final type in AdapterType.values) {
    if (type.name == value) {
      return type;
    }
  }
  return null;
}

/// 获取适配器类型的显示名称
String getAdapterDisplayName(AdapterType type) {
  switch (type) {
    case AdapterType.core:
      return S.current.network_adapterCore;
    case AdapterType.emergency:
      return S.current.network_adapterEmergency;
    case AdapterType.webview:
      return S.current.network_adapterWebView;
  }
}

/// 创建一个 HttpClientAdapter，用于外部服务（如 AI 请求）复用应用网络配置
HttpClientAdapter createExternalHttpAdapter() =>
    _WebViewAware(_DynamicAdapter());

/// 配置平台适配器
void configurePlatformAdapter(Dio dio, {bool preferWebViewFallback = false}) {
  if (Platform.isWindows && preferWebViewFallback) {
    configureWebViewFallbackAdapter(dio);
    return;
  }
  dio.httpClientAdapter = _WebViewAware(_DynamicAdapter());
  _currentAdapterType = resolveEffectiveAdapter().type;
}

/// 配置 WebView 适配器（仅 Windows 显式兜底）
void configureWebViewFallbackAdapter(Dio dio) {
  final adapter = WebViewHttpAdapter();
  dio.httpClientAdapter = adapter;
  _currentAdapterType = AdapterType.webview;
  adapter
      .initialize()
      .then((_) {
        NetworkLogger.log('[DIO] Windows 兜底：使用 WebView 适配器');
      })
      .catchError((e) {
        NetworkLogger.log('[DIO] WebView 适配器初始化失败: $e', level: 'error');
      });
}

/// 实时解析当前生效的适配器及原因（UI 单一数据源）。
///
/// 不依赖请求触发，读取各 service 当前状态即时推算，
/// 与 [_DynamicAdapter] 每次请求时的判断完全同源。
EffectiveAdapter resolveEffectiveAdapter() {
  if (CoreFallbackService.instance.hasFallenBack) {
    return const EffectiveAdapter(
      AdapterType.emergency,
      AdapterReason.fallback,
    );
  }
  final core = NetCoreService.instance;
  if (!core.isRunning) {
    return const EffectiveAdapter(
      AdapterType.emergency,
      AdapterReason.fallback,
    );
  }
  return EffectiveAdapter(
    AdapterType.core,
    (core.status.templateReady || core.status.templateSource == 'builtin')
        ? AdapterReason.core
        : AdapterReason.coreWarmingUp,
  );
}

/// 应急路径：Dart SDK 自带，不占体积，仅核心不可用时启用。
///
/// 跟随系统代理，与 WebView 保持同一出口（cf_clearance 绑 IP，
/// 出口不一致会导致 CF 验证无限循环）。findProxy 每个请求求值，
/// 系统代理开关变化即时生效。
HttpClientAdapter _createEmergencyAdapter() {
  NetworkLogger.log('[DIO] 网络核心不可用，启用 Dart IO 应急路径', level: 'warning');
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (uri) {
        final proxy = SystemProxyService.instance.effectiveProxyUrl;
        if (proxy == null) return 'DIRECT';
        final parsed = Uri.tryParse(proxy);
        // dart:io HttpClient 不支持 SOCKS 代理，该场景保持直连。
        if (parsed == null || parsed.scheme.startsWith('socks'))
          return 'DIRECT';
        return 'PROXY ${parsed.host}:${parsed.port}';
      };
      return client;
    },
  );
}

/// WebView 包装：兼容模式下主域名的 API 请求改由浏览器内核代发。
class _WebViewAware implements HttpClientAdapter {
  _WebViewAware(this._inner) {
    WebViewAdapterSettingsService.instance.effectiveNotifier.addListener(
      _handleWebViewSettingChanged,
    );
  }

  final HttpClientAdapter _inner;
  WebViewHttpAdapter? _webViewAdapter;

  WebViewHttpAdapter _getWebViewAdapter() =>
      _webViewAdapter ??= WebViewHttpAdapter();

  /// HarmonyOS：WebView 栈单次 fetch 的硬上限。
  ///
  /// 第 3 轮回归实测过 WebViewAdapter 在 OHOS 上会挂死（JS fetch 结果回不到
  /// Dart）。这里在传输层再加一道上限：超时/异常时**回退原生 dio**，并关闭
  /// 本次会话的强制浏览器栈开关，保证冷启动绝不会被吊死（原生会 403，但会
  /// 进入 CF 验证流程，最终仍能出数据）。
  static const Duration _ohosWebViewFetchTimeout = Duration(seconds: 12);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_shouldUseWebView(options)) {
      _currentAdapterType = AdapterType.webview;
      setRequestAdapterLogName(options, AdapterType.webview.name);
      CsrfSessionTrace.captureDispatch(options, browserManaged: true);
      final adapter = _getWebViewAdapter();
      if (!PlatformUtils.isOhos) {
        return adapter.fetch(options, requestStream, cancelFuture);
      }
      try {
        return await adapter
            .fetch(options, requestStream, cancelFuture)
            .timeout(
              _ohosWebViewFetchTimeout,
              onTimeout: () => throw TimeoutException(
                'OHOS webview fetch timeout '
                '(${_ohosWebViewFetchTimeout.inSeconds}s)',
              ),
            );
      } on TimeoutException catch (e) {
        // 挂死（第 3 轮回归那种）：回退原生，并暂停本会话的 WebView 适配器
        // （含持久化兼容模式开启的情况），避免后续每个请求都白等 12s。
        NetworkLogger.log(
          '[WebViewAdapter][OHOS] fetch 超时，回退网络核心并暂停本会话 WebView 适配器: $e',
          level: 'warning',
        );
        WebViewAdapterSettingsService.instance.suspendOhosWebViewForSession();
        try {
          adapter.close(force: true);
        } catch (_) {}
        // 适配器已被 force 关闭，丢弃实例，下次按需重建。
        if (identical(_webViewAdapter, adapter)) _webViewAdapter = null;
        return _inner.fetch(options, requestStream, cancelFuture);
      } catch (e) {
        // 其它异常（JS 报错 / 桥不可用等）：只本次回退原生，保留强制开关。
        NetworkLogger.log(
          '[WebViewAdapter][OHOS] fetch 失败，本次回退网络核心: $e',
          level: 'warning',
        );
        return _inner.fetch(options, requestStream, cancelFuture);
      }
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    WebViewAdapterSettingsService.instance.effectiveNotifier.removeListener(
      _handleWebViewSettingChanged,
    );
    _webViewAdapter?.close(force: force);
    _webViewAdapter = null;
    _inner.close(force: force);
  }

  void _handleWebViewSettingChanged() {
    if (WebViewAdapterSettingsService.instance.effectiveEnabled) {
      return;
    }
    // 关闭当前调用者，已发出的请求继续持有运行时租约直到结束。
    _webViewAdapter?.close(force: false);
    _webViewAdapter = null;
  }

  bool _shouldUseWebView(RequestOptions options) {
    // HarmonyOS 回归说明（2026-10-21 第 3 轮 → 第 4 轮）：
    // 曾经让「主站 GET 从第一个请求起就走浏览器栈」以避免冷启动 403 弹浮层，
    // 但实测 headless WebView 的 JS fetch 响应回不到 Dart（请求挂死 70s+），
    // 冷启动直接卡在启动页。已回退为第 2 轮行为：**dio 先请求 → 403 →
    // 再由 CfChallengeInterceptor 用浏览器网络栈重放**（已验证能出数据）。
    // 浮层体验问题由 cf_challenge_service / cf_challenge_interceptor 的
    // 自动关闭 + 自愈轮询解决，不再改传输层优先级。
    if (!WebViewAdapterSettingsService.instance.effectiveEnabled) {
      return false;
    }
    // HarmonyOS：启动 session bootstrap 在后台独占 WebView 时，适配器请求只能
    // 排队并等到 12s 超时（真机首批请求 12.3s 后回退 core）。此期间直接走网络核心。
    if (PlatformUtils.isOhos &&
        SiteWebViewRuntime.instance.backgroundExclusiveBusy) {
      return false;
    }
    return requestCanUseWebViewAdapter(options);
  }
}

/// 判断请求本身是否能由 WebView 适配器承载，不考虑当前兼容模式开关。
/// 用于 CF 恢复在弹出兼容提示前确认该请求确实可以被浏览器网络栈接管。
bool requestCanUseWebViewAdapter(RequestOptions options) {
  final uri = options.uri;
  if (options.spec.skipWebViewAdapter) {
    return false;
  }
  // CF 的 /cdn-cgi/ 端点(challenge-platform 等)必须走原生栈,
  // 不能被 WebView 适配器接管。
  if (uri.path.startsWith('/cdn-cgi/')) {
    return false;
  }

  final resourceKind = options.extra[WebViewHttpAdapter.resourceKindExtraKey]
      ?.toString();
  final method = options.method.toUpperCase();
  final isBinaryResponse =
      options.responseType == ResponseType.stream ||
      options.responseType == ResponseType.bytes;

  // 当前 WebView fetch 运行在 linux.do origin；跨域图片即使浏览器能显示，
  // JS 也不能读取响应字节。图片流仅允许同源请求，其它 stream 请求
  //（MessageBus、下载等）仍不走 WebView。
  if (resourceKind == WebViewHttpAdapter.resourceKindImage) {
    return (method == 'GET' || method == 'HEAD') &&
        isBinaryResponse &&
        WebViewAdapterSettingsService.instance.canUseWebView(uri);
  }

  if (!WebViewAdapterSettingsService.instance.canUseWebView(uri)) {
    return false;
  }
  if (isBinaryResponse) {
    return false;
  }

  final accept = _requestHeaderValue(options.headers, 'Accept').toLowerCase();
  final requestedWith = _requestHeaderValue(
    options.headers,
    'X-Requested-With',
  );

  // HarmonyOS：CF 的 cf_clearance 是 HttpOnly cookie，ArkWeb 只有
  // `WebCookieManager.fetchCookieSync(url)` 一个读出口，原生 dio 侧永远拿不到它
  // → 主站请求必然 403。而 WebView 内核（ArkWeb）自己带这枚 cookie，所以
  // OHOS 上必须放宽「只接管 JSON/XHR」的限制，允许把首页预加载这类
  // HTML 导航请求也交给 WebView 适配器，否则 CF 兜底在 OHOS 上永远不生效
  // （实测：PreloadedData 的 GET https://linux.do Accept: text/html 被这里
  // 直接判 false，导致「自动切浏览器网络栈」分支压根没进入）。
  final ohosAllowNavigationFetch = PlatformUtils.isOhos;

  final explicitlyHtml =
      accept.contains('text/html') || accept.contains('application/xhtml+xml');
  if (explicitlyHtml && !ohosAllowNavigationFetch) {
    return false;
  }
  final apiLikeGet =
      requestedWith == 'XMLHttpRequest' ||
      uri.path.endsWith('.json') ||
      accept.contains('application/json') ||
      accept.contains('text/javascript');
  if ((method == 'GET' || method == 'HEAD') &&
      !apiLikeGet &&
      !ohosAllowNavigationFetch) {
    return false;
  }

  return method == 'GET' ||
      method == 'HEAD' ||
      method == 'POST' ||
      method == 'PUT' ||
      method == 'PATCH' ||
      method == 'DELETE';
}

String _requestHeaderValue(Map<String, dynamic> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toString().toLowerCase() == name.toLowerCase()) {
      return _requestHeaderValueToString(entry.value);
    }
  }
  return '';
}

String _requestHeaderValueToString(Object? value) {
  if (value == null) return '';
  if (value is Iterable) {
    return value
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
  }
  return value.toString().trim();
}

/// 在网络核心与应急路径之间按需切换。
///
/// 只有这两档：核心是常规栈，应急路径仅在核心整体不可用时顶上。
class _DynamicAdapter implements HttpClientAdapter {
  final Map<AdapterType, HttpClientAdapter> _delegates = {};
  bool _hasFallenBack = false;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError(
        "Can't establish connection after the adapter was closed.",
      );
    }
    // 冷启动早期核心可能还在启动：等它一下，别让首批请求用应急路径的指纹撞 CF
    final core = NetCoreService.instance;
    if (!core.isRunning &&
        core.isAvailable &&
        !CoreFallbackService.instance.hasFallenBack) {
      await core.whenFirstStarted();
    }
    final desiredType = resolveEffectiveAdapter().type;
    final delegate = _ensureDelegate(desiredType);
    setRequestAdapterLogName(options, desiredType.name);
    _currentAdapterType = desiredType;
    if (desiredType != AdapterType.core)
      CsrfSessionTrace.captureDispatch(options);
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  HttpClientAdapter _ensureDelegate(AdapterType desiredType) {
    final hasFallenBack = CoreFallbackService.instance.hasFallenBack;
    if (_hasFallenBack != hasFallenBack) {
      _hasFallenBack = hasFallenBack;
      // 不强杀：在途请求各自走完，核心适配器本身是无状态的
      for (final delegate in _delegates.values) {
        delegate.close(force: false);
      }
      _delegates.clear();
    }
    return _delegates.putIfAbsent(
      desiredType,
      () => switch (desiredType) {
        AdapterType.core => NetCoreHttpAdapter(),
        AdapterType.emergency => _createEmergencyAdapter(),
        AdapterType.webview => WebViewHttpAdapter(),
      },
    );
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    for (final delegate in _delegates.values) {
      delegate.close(force: force);
    }
    _delegates.clear();
  }
}
