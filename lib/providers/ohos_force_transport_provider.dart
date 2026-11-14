import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/network/webview/webview_adapter_settings_service.dart';

/// 鸿蒙「主站请求走浏览器内核」的用户持久化选择，供设置页开关读写。
///
/// 只反映用户选择，不受 12 秒超时回退造成的会话临时值影响。
final ohosForceTransportProvider =
    NotifierProvider<OhosForceTransportNotifier, bool>(
      OhosForceTransportNotifier.new,
    );

class OhosForceTransportNotifier extends Notifier<bool> {
  @override
  bool build() {
    final service = WebViewAdapterSettingsService.instance;
    void sync() => state = service.ohosForcePersistent;
    service.ohosForcePersistentNotifier.addListener(sync);
    ref.onDispose(() => service.ohosForcePersistentNotifier.removeListener(sync));
    return service.ohosForcePersistent;
  }

  /// 写入持久化并立即生效（无需重启）。
  Future<void> set(bool value) =>
      WebViewAdapterSettingsService.instance.setOhosForceTransport(value);
}
