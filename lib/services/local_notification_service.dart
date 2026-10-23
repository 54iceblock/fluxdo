import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../l10n/s.dart';
import '../pages/chat/channel/chat_channel_page.dart';
import '../pages/topic_detail_page/topic_detail_page.dart';
import '../utils/notification_navigation.dart';
import '../utils/platform_utils.dart';

/// 全局 NavigatorKey，用于通知点击时导航
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// APK 更新通知的固定 ID，便于复用/取消同一条进度通知
const int apkUpdateNotificationId = 99001;

const String _apkUpdateChannelId = 'apk_update';

/// 本地系统通知服务
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionGranted = false;

  /// 初始化通知服务
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
    const windowsSettings = WindowsInitializationSettings(
      appName: 'FluxDO',
      appUserModelId: 'Com.FluxDO.FluxDO',
      guid: 'e965ef8c-b676-47c1-b6e7-297d63942974',
    );
    // OHOS：flutter_local_notifications 22.x 在 OHOS 平台强制要求
    // `InitializationSettings.ohos` 非空（否则 initialize 直接抛 ArgumentError）。
    // defaultIcon 是 entry HAP 里的 media 资源名，这里用 module.json5 的
    // `$media:icon`（entry/src/main/resources/base/media/icon.png）。
    const ohosSettings = OhosInitializationSettings('icon');

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
      ohos: ohosSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    _initialized = true;
    debugPrint('[LocalNotification] 初始化完成');
    
    // 请求通知权限（Android 13+ / OHOS 系统通知授权）
    await _requestPermission();
  }

  /// 通知点击回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[LocalNotification] 通知被点击: payload=${response.payload}');

    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    // payload 格式: "topic:{topicId}[:{postNumber}]" 或
    // "message:{topicId}[:{postNumber}]"(私信,走私信平行视界栈)或
    // "chat:{channelId}"(聊天,直达聊天窗)。
    if (payload.startsWith('chat:')) {
      final channelId = int.tryParse(payload.substring(5));
      if (channelId == null) return;
      final chatPage = ChatChannelPage(channelId: channelId);
      final chatContext = navigatorKey.currentContext;
      if (chatContext != null && chatContext.mounted) {
        openNotificationPage(chatContext, chatPage);
        return;
      }
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => chatPage),
      );
      return;
    }
    final isMessage = payload.startsWith('message:');
    if (!isMessage && !payload.startsWith('topic:')) return;
    final parts = payload.substring(isMessage ? 8 : 6).split(':');
    final topicId = int.tryParse(parts[0]);
    final postNumber = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (topicId == null) return;

    debugPrint(
      '[LocalNotification] 跳转到${isMessage ? "私信" : "话题"}: $topicId, 帖子: $postNumber',
    );

    // 与应用内通知落点一致:大屏页面弹窗、窄屏全屏路由(私信/话题
    // 同一入口,不再写工作区栈/切 tab)。拿不到 context(冷启动时通知
    // 先于根 widget 树就绪)退化为直接 push。
    final page = TopicDetailPage(
      topicId: topicId,
      scrollToPostNumber: postNumber,
    );
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      openNotificationPage(context, page);
      return;
    }
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  /// 请求通知权限
  Future<void> _requestPermission() async {
    // Android 13+ 需要运行时通知权限
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      _permissionGranted = granted ?? false;
      debugPrint('[LocalNotification] Android 权限: $_permissionGranted');
      return;
    }

    // HarmonyOS：弹系统「允许通知」授权框（notificationManager.requestEnableNotification）。
    // 失败（例如 Ability 尚未绑定）时按已授权继续 —— 真正的 publish 仍会由
    // 系统拦截并给出结果，不能让通知链路因为一次权限查询失败而整体静默。
    final ohosPlugin = _plugin.resolvePlatformSpecificImplementation<
        OhosFlutterLocalNotificationsPlugin>();
    if (ohosPlugin != null) {
      try {
        final granted = await ohosPlugin.requestNotificationsPermission();
        _permissionGranted = granted ?? true;
      } catch (e) {
        debugPrint('[LocalNotification] OHOS 权限请求失败，按已授权继续: $e');
        _permissionGranted = true;
      }
      debugPrint('[LocalNotification] OHOS 权限: $_permissionGranted');
      return;
    }

    // 其余平台默认已授权
    _permissionGranted = true;
  }

  /// 显示通知
  Future<void> show({
    required String title,
    required String body,
    int? id,
    int? topicId,
    int? postNumber,
    bool isPrivateMessage = false,
    int? chatChannelId,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (!_permissionGranted) {
      debugPrint('[LocalNotification] 权限未授予，跳过通知');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'discourse_notifications',
      S.current.notification_channelDiscourse,
      channelDescription: S.current.notification_channelDiscourseDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails();

    // OHOS 侧必须给 OhosNotificationDetails（slotType 决定通知渠道归类）。
    final ohosDetails = OhosNotificationDetails(
      OhosNotificationSlotType.SOCIAL_COMMUNICATION,
      slotDesc: S.current.notification_channelDiscourseDesc,
      importance: OhosImportance.high,
      autoCancel: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: const WindowsNotificationDetails(),
      ohos: ohosDetails,
    );

    final notificationId = id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000);
    
    // 构建 payload 用于点击回调:私信用 message: 前缀,走私信自己的
    // 平行视界栈,不能跟普通话题共用 topic: 前缀(否则左栏会显示信息流)。
    // chat 通知用 chat: 前缀直达聊天窗。
    String? payload;
    if (chatChannelId != null) {
      payload = 'chat:$chatChannelId';
    } else if (topicId != null) {
      final prefix = isPrivateMessage ? 'message' : 'topic';
      payload = postNumber != null
          ? '$prefix:$topicId:$postNumber'
          : '$prefix:$topicId';
    }
    
    try {
      await _plugin.show(id: notificationId, title: title, body: body, notificationDetails: details, payload: payload);
      debugPrint('[LocalNotification] 已发送: $title, payload=$payload');
    } catch (e) {
      // OHOS：系统未授权/通知被禁用时 publish 会抛 PlatformException，
      // 通知失败不应影响业务调用方（MessageBus / 聊天提醒）。
      debugPrint('[LocalNotification] 发布通知失败: $e');
    }
  }

  /// 显示 APK 下载进度通知（持续更新同一条）。
  ///
  /// indeterminate=true 时显示无限循环进度条（用于"连接中/校验中"等阶段）。
  Future<void> showApkProgress({
    required String title,
    String? body,
    int progress = 0,
    bool indeterminate = false,
    int id = apkUpdateNotificationId,
  }) async {
    // HarmonyOS：不支持应用内更新安装（三方应用不能静默装 HAP），
    // 且下载进度通知依赖 OHOS 的 Download 模板（部分设备 isSupportTemplate
    // 返回 false，插件会抛错），所以整条链路直接跳过。
    if (PlatformUtils.isOhos) {
      debugPrint('[LocalNotification] OHOS 跳过 APK 下载进度通知: $title');
      return;
    }
    if (!_initialized) {
      await initialize();
    }
    if (!_permissionGranted) return;

    final androidDetails = AndroidNotificationDetails(
      _apkUpdateChannelId,
      S.current.update_notification_channel,
      channelDescription: S.current.update_notification_channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      indeterminate: indeterminate,
      ongoing: true,
      onlyAlertOnce: true,
      channelShowBadge: false,
      playSound: false,
      enableVibration: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      ohos: OhosNotificationDetails(
        OhosNotificationSlotType.SERVICE_INFORMATION,
        slotDesc: S.current.update_notification_channelDesc,
        importance: OhosImportance.low,
        ongoing: true,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      ),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[LocalNotification] 发布进度通知失败（已跳过）: $e');
    }
  }

  /// 显示 APK 下载完成通知（点击触发安装由 ota_update 自行发起 intent，
  /// 这里只是给用户一个可点击的入口拉起 App，不需要 payload）。
  Future<void> showApkComplete({
    required String title,
    required String body,
    int id = apkUpdateNotificationId,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    if (!_permissionGranted) return;

    final androidDetails = AndroidNotificationDetails(
      _apkUpdateChannelId,
      S.current.update_notification_channel,
      channelDescription: S.current.update_notification_channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      ohos: OhosNotificationDetails(
        OhosNotificationSlotType.SERVICE_INFORMATION,
        slotDesc: S.current.update_notification_channelDesc,
        importance: OhosImportance.high,
        autoCancel: true,
      ),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[LocalNotification] 发布完成通知失败: $e');
    }
  }

  /// 取消指定通知
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id: id);
  }
}
