import 'dart:io';

import 'package:flutter/foundation.dart';

/// 平台工具类 — 统一平台检测逻辑
class PlatformUtils {
  PlatformUtils._();

  @visibleForTesting
  static bool? debugDesktopOverride;

  /// 是否运行在 HarmonyOS / OpenHarmony（鸿蒙 NEXT）
  ///
  /// OHOS Flutter SDK 给 dart:io 的 Platform 增加了 `isOhos`。
  /// 为了在非 OHOS 的 Flutter SDK 上也能编译（其他五端 CI），
  /// 这里通过 operatingSystem 字符串判断，避免直接引用不存在的 getter。
  static bool get isOhos => !kIsWeb && Platform.operatingSystem == 'ohos';

  /// 是否运行在桌面操作系统（macOS / Windows / Linux）
  static bool get isDesktop =>
      debugDesktopOverride ??
      (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux));

  /// 是否运行在移动操作系统（Android / iOS / HarmonyOS）
  static bool get isMobile =>
      debugDesktopOverride == null
      ? (!kIsWeb &&
            (Platform.isAndroid ||
                Platform.isIOS ||
                Platform.operatingSystem == 'ohos'))
      : !debugDesktopOverride!;
}
