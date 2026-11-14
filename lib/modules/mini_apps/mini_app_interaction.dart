import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/preferences_provider.dart';
import '../../utils/platform_utils.dart';

/// 按运行平台分流，桌面缩窄窗口也不启用移动端的两段下拉。
final miniAppPullEnabledProvider = Provider<bool>((ref) {
  // HarmonyOS：小程序整体关闭，不启用下拉进入小程序
  return !PlatformUtils.isDesktop &&
      !PlatformUtils.isOhos &&
      ref.watch(preferencesProvider.select((p) => p.miniAppPullEnabled));
});
