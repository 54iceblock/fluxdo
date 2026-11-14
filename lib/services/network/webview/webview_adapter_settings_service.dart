import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants.dart';
import '../../../utils/platform_utils.dart';
import '../../network_logger.dart';

/// WebView 适配器设置服务
///
/// 开启后，主站 API 请求通过 WebView 内核发送（真正的 Chrome TLS 指纹），
/// 可改善因 TLS 指纹被 Cloudflare 识别为非浏览器客户端导致的登录失效问题。
///
/// 仅对主域名的 API 请求生效，排除：
/// - CDN 图片请求（cdn.linux.do 等子域名）
/// - MessageBus 长轮询（/message-bus/ 路径）
class WebViewAdapterSettingsService {
  WebViewAdapterSettingsService._internal();

  static final WebViewAdapterSettingsService instance =
      WebViewAdapterSettingsService._internal();

  static const _enabledKey = 'webview_adapter_enabled';

  static const _ohosForceTransportKey = 'ohos_force_webview_transport';

  /// HarmonyOS 上当前会话是否强制把主站请求交给 WebView（ArkWeb）网络栈。
  ///
  /// 这是「会话值」：启动时取自用户持久化设置（[ohosForcePersistentNotifier]，
  /// 默认 false，即主站请求走网络核心），用户切换设置时同步更新；
  /// 运行时 12 秒超时自动回退会通过 [applyOhosForceTransport] 临时置为 false，
  /// 该回退只影响当前会话，不写入持久化设置。
  ///
  /// 背景：rhttp 时代鸿蒙没有带指纹的原生栈，linux.do 前置的 Cloudflare 会挑战
  /// 非浏览器客户端，因此曾写死为 true 让 ArkWeb 代发。现在网络核心可用，
  /// 默认改走核心，旧方案保留为用户可切换的对比开关。
  static bool forceWebViewTransportOnOhos = false;

  /// 用户持久化的「鸿蒙主站请求走浏览器内核」开关，默认 false。
  ///
  /// 设置页只监听这个 notifier，避免把超时回退造成的会话值显示成用户选择。
  final ValueNotifier<bool> ohosForcePersistentNotifier = ValueNotifier(false);

  /// 用户持久化的兼容模式开关。
  ///
  /// 设置页只监听这个 notifier，避免把 CF 恢复流程启用的临时兼容模式
  /// 误显示成用户主动修改的永久设置。
  final ValueNotifier<bool> notifier = ValueNotifier(false);

  /// 当前会话的临时兼容模式开关，不写入 SharedPreferences。
  final ValueNotifier<bool> sessionFallbackNotifier = ValueNotifier(false);

  /// 实际用于请求分流的开关。
  ///
  /// 持久化兼容模式、会话临时兼容模式、OHOS 平台强制开关任一开启时均为 true。
  final ValueNotifier<bool> effectiveNotifier = ValueNotifier(false);

  SharedPreferences? _prefs;

  /// 用户持久化设置是否开启。
  bool get enabled => notifier.value;

  bool get persistentEnabled => notifier.value;

  /// 当前会话是否因 CF 恢复流程临时启用了兼容模式。
  bool get sessionFallbackEnabled => sessionFallbackNotifier.value;

  /// 用户持久化的 OHOS 强制浏览器网络栈选择。
  bool get ohosForcePersistent => ohosForcePersistentNotifier.value;

  /// OHOS 当前会话是否正在强制使用浏览器网络栈。
  bool get ohosForceTransportEnabled =>
      forceWebViewTransportOnOhos && PlatformUtils.isOhos;

  /// 当前请求是否应允许使用 WebView 适配器。
  bool get effectiveEnabled => effectiveNotifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_prefs != null) return;
    _prefs = prefs;
    notifier.value = prefs.getBool(_enabledKey) ?? false;
    ohosForcePersistentNotifier.value =
        prefs.getBool(_ohosForceTransportKey) ?? false;
    // 会话值以持久化设置为起点
    forceWebViewTransportOnOhos = ohosForcePersistentNotifier.value;
    _syncEffectiveEnabled();
  }

  /// 用户在设置页切换 OHOS「主站请求走浏览器内核」：写入持久化并立即生效。
  ///
  /// 会话值同步为用户选择（包括覆盖此前超时回退造成的临时 false）。
  Future<void> setOhosForceTransport(bool value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    ohosForcePersistentNotifier.value = value;
    forceWebViewTransportOnOhos = value;
    _syncEffectiveEnabled();
    await prefs.setBool(_ohosForceTransportKey, value);
  }

  /// 运行时临时切换 OHOS 会话强制开关（会立即重算 effectiveEnabled）。
  ///
  /// 只改会话值，不写入持久化设置；超时自动回退走这里。
  void applyOhosForceTransport(bool value) {
    if (forceWebViewTransportOnOhos == value) {
      _syncEffectiveEnabled();
      return;
    }
    forceWebViewTransportOnOhos = value;
    _syncEffectiveEnabled();
    // release 下 debugPrint 被置空，改走 NetworkLogger 落盘到应用日志
    NetworkLogger.log(
      '[WebViewAdapter][OHOS] 会话强制浏览器网络栈 = $value '
      '(persistent=${ohosForcePersistentNotifier.value}, '
      'effective=${effectiveNotifier.value})',
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    notifier.value = value;
    _syncEffectiveEnabled();
    await prefs.setBool(_enabledKey, value);
  }

  /// 仅在当前应用会话启用临时兼容模式。
  void enableSessionFallback() {
    _setSessionFallbackEnabled(true);
  }

  /// 退出当前会话的临时兼容模式。
  void disableSessionFallback() {
    _setSessionFallbackEnabled(false);
  }

  /// 在登录会话结束时清除临时兼容状态。
  ///
  /// 该操作不会修改用户持久化的兼容模式设置。
  void resetSessionFallback() {
    _setSessionFallbackEnabled(false);
  }

  /// 判断请求是否应走 WebView 适配器
  bool shouldUseWebView(Uri uri) {
    if (!effectiveEnabled) return false;
    return canUseWebView(uri);
  }

  /// 判断目标地址是否属于 WebView 适配器可覆盖的范围，不考虑当前是否启用。
  bool canUseWebView(Uri uri) {
    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    // 仅主域名（排除 CDN、ping 等子域名）
    if (uri.host != baseHost) return false;
    // 排除 MessageBus 长轮询
    if (uri.path.startsWith('/message-bus/')) return false;
    return true;
  }

  void _setSessionFallbackEnabled(bool value) {
    if (sessionFallbackNotifier.value == value) return;
    sessionFallbackNotifier.value = value;
    _syncEffectiveEnabled();
  }

  void _syncEffectiveEnabled() {
    effectiveNotifier.value =
        enabled || sessionFallbackEnabled || ohosForceTransportEnabled;
  }

  /// 重置单例内部状态，仅用于测试，使 initialize() 可重新执行。
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    notifier.value = false;
    sessionFallbackNotifier.value = false;
    effectiveNotifier.value = false;
    ohosForcePersistentNotifier.value = false;
    forceWebViewTransportOnOhos = false;
  }
}
