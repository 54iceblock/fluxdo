import 'package:flutter/services.dart';

import '../../utils/platform_utils.dart';

/// HarmonyOS 长时任务（后台保活）桥。
///
/// HarmonyOS 应用切到后台后普通进程会被挂起；通过 ArcTS 侧的
/// `backgroundTaskManager.startBackgroundRunning(..., DATA_TRANSFER, ...)`
/// 申请长时任务，可让进程在后台继续运行（消息轮询/通知检查依赖此能力）。
///
/// 注意：数据同步类长时任务单次最长约 10 分钟，系统到点会结束；
/// 因此每次应用切后台都重新申请（[start] 幂等，已运行则直接返回）。
class OhosBackgroundTask {
  OhosBackgroundTask._();

  static final OhosBackgroundTask instance = OhosBackgroundTask._();

  static const MethodChannel _channel = MethodChannel('com.fluxdo/ohos');

  bool _running = false;

  bool get isRunning => _running;

  /// 申请长时任务；失败返回 false（不影响前台使用）。
  Future<bool> start() async {
    if (!PlatformUtils.isOhos) return false;
    if (_running) return true;
    try {
      await _channel.invokeMethod<bool>('startContinuousTask');
      _running = true;
      return true;
    } catch (e) {
      // 常见失败：设备不支持该后台模式 / 未在 module.json5 声明 backgroundModes
      return false;
    }
  }

  /// 结束长时任务（回到前台后调用）。
  Future<void> stop() async {
    if (!PlatformUtils.isOhos || !_running) return;
    try {
      await _channel.invokeMethod<bool>('stopContinuousTask');
    } catch (_) {
      // 忽略：系统可能已自行结束
    }
    _running = false;
  }
}
