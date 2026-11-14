import 'package:fluxdo/services/network/webview/webview_adapter_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WebViewAdapterSettingsService 会话兼容模式', () {
    late SharedPreferences prefs;
    late WebViewAdapterSettingsService service;

    setUp(() async {
      service = WebViewAdapterSettingsService.instance;
      service.resetForTest();
      SharedPreferences.setMockInitialValues({
        'webview_adapter_enabled': false,
      });
      prefs = await SharedPreferences.getInstance();
      await service.initialize(prefs);
    });

    tearDown(() {
      service.resetForTest();
    });

    test('临时启用只改变会话状态，不修改持久化设置', () {
      service.enableSessionFallback();

      expect(service.enabled, false);
      expect(service.persistentEnabled, false);
      expect(service.sessionFallbackEnabled, true);
      expect(service.effectiveEnabled, true);
      expect(prefs.getBool('webview_adapter_enabled'), false);
    });

    test('退出临时兼容后恢复持久化设置决定的有效状态', () async {
      await service.setEnabled(true);
      service.enableSessionFallback();
      service.disableSessionFallback();

      expect(service.enabled, true);
      expect(service.sessionFallbackEnabled, false);
      expect(service.effectiveEnabled, true);
      expect(prefs.getBool('webview_adapter_enabled'), true);
    });

    test('重置会话状态不会关闭用户持久化兼容模式', () async {
      await service.setEnabled(true);
      service.enableSessionFallback();
      service.resetSessionFallback();

      expect(service.persistentEnabled, true);
      expect(service.sessionFallbackEnabled, false);
      expect(service.effectiveEnabled, true);
    });

    test('effectiveNotifier 仅跟随实际分流状态', () async {
      var notifications = 0;
      void listener() => notifications++;
      service.effectiveNotifier.addListener(listener);
      addTearDown(() => service.effectiveNotifier.removeListener(listener));

      service.enableSessionFallback();
      await service.setEnabled(true);
      service.disableSessionFallback();
      await service.setEnabled(false);

      expect(notifications, 2);
      expect(service.effectiveEnabled, false);
    });

    test('OHOS 强制浏览器栈持久化默认 false，未设置时会话值也为 false', () {
      expect(service.ohosForcePersistent, false);
      expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, false);
      expect(prefs.getBool('ohos_force_webview_transport'), isNull);
    });

    test('setOhosForceTransport 写入持久化并同步会话值', () async {
      await service.setOhosForceTransport(true);

      expect(service.ohosForcePersistent, true);
      expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, true);
      expect(prefs.getBool('ohos_force_webview_transport'), true);
    });

    test('initialize 以持久化值作为会话起点', () async {
      service.resetForTest();
      SharedPreferences.setMockInitialValues({
        'ohos_force_webview_transport': true,
      });
      final p = await SharedPreferences.getInstance();
      await service.initialize(p);

      expect(service.ohosForcePersistent, true);
      expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, true);
    });

    test('超时回退 applyOhosForceTransport 只改会话值，不写持久化', () async {
      await service.setOhosForceTransport(true);
      service.applyOhosForceTransport(false);

      expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, false);
      expect(service.ohosForcePersistent, true);
      expect(prefs.getBool('ohos_force_webview_transport'), true);
    });

    test('用户再次切换会覆盖回退造成的会话 false', () async {
      await service.setOhosForceTransport(true);
      service.applyOhosForceTransport(false);
      await service.setOhosForceTransport(true);

      expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, true);
    });

    test('resetForTest 清空 OHOS 持久化与会话值', () async {
      await service.setOhosForceTransport(true);
      service.resetForTest();

      expect(service.ohosForcePersistent, false);
      expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, false);
    });

    group('OHOS ArkWeb 挂死后暂停本会话', () {
      setUp(() => WebViewAdapterSettingsService.debugIsOhosOverride = true);
      tearDown(() => WebViewAdapterSettingsService.debugIsOhosOverride = null);

      test('持久化兼容模式开启时也会暂停，且不写持久化', () async {
        await service.setEnabled(true);
        expect(service.effectiveEnabled, true);

        service.suspendOhosWebViewForSession();

        expect(service.ohosWebViewSuspended, true);
        expect(service.effectiveEnabled, false);
        expect(service.persistentEnabled, true);
        expect(prefs.getBool('webview_adapter_enabled'), true);
        expect(
          service.shouldUseWebView(Uri.parse('https://linux.do/latest.json')),
          false,
        );
      });

      test('会话兼容模式与强制浏览器栈同样被暂停', () async {
        await service.setOhosForceTransport(true);
        service.enableSessionFallback();

        service.suspendOhosWebViewForSession();

        expect(service.effectiveEnabled, false);
        expect(WebViewAdapterSettingsService.forceWebViewTransportOnOhos, false);
        expect(service.ohosForcePersistent, true);
      });

      test('用户重新切换任一开关即恢复', () async {
        await service.setEnabled(true);
        service.suspendOhosWebViewForSession();
        await service.setEnabled(true);
        expect(service.effectiveEnabled, true);

        service.suspendOhosWebViewForSession();
        await service.setOhosForceTransport(false);
        expect(service.effectiveEnabled, true);
      });
    });

    test('非 OHOS 平台不会暂停', () async {
      WebViewAdapterSettingsService.debugIsOhosOverride = false;
      addTearDown(() => WebViewAdapterSettingsService.debugIsOhosOverride = null);
      await service.setEnabled(true);

      service.suspendOhosWebViewForSession();

      expect(service.ohosWebViewSuspended, false);
      expect(service.effectiveEnabled, true);
    });

    test('临时兼容仍排除 MessageBus 与非主站请求', () {
      service.enableSessionFallback();

      expect(
        service.shouldUseWebView(Uri.parse('https://linux.do/latest.json')),
        true,
      );
      expect(
        service.shouldUseWebView(
          Uri.parse('https://linux.do/message-bus/abc/poll'),
        ),
        false,
      );
      expect(
        service.shouldUseWebView(Uri.parse('https://cdn.linux.do/image.png')),
        false,
      );
    });
  });
}
