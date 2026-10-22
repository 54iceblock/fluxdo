/// cook 渲染的 JS 引擎封装（IO 平台实现）。
///
/// 通过条件导入被 DiscourseCookService 使用；web 平台走
/// cook_js_engine_stub.dart（恒不可用）。
///
/// HarmonyOS：flutter_js 没有原生库，改用自编 QuickJS（libohos_quickjs.so，
/// 见 tools/build-quickjs-ohos.sh 与 lib/services/cook/ohos_quickjs.dart）。
library;

import 'package:flutter_js/flutter_js.dart';

import '../../utils/ohos_compat.dart';
import '../../utils/platform_utils.dart';
import 'ohos_quickjs.dart';

/// 是否支持在本平台跑 JS cook。
final bool cookJsSupported = OhosCompat.supportsCookJs;

/// 裸 JS 引擎薄封装：eval 代码、取字符串结果。
///
/// Android/Windows/Linux = QuickJS（flutter_js），iOS/macOS = JavaScriptCore（FFI），
/// HarmonyOS = 自编 QuickJS 桥。
class CookJsEngine {
  CookJsEngine()
    : _ohos = PlatformUtils.isOhos ? OhosQuickJs.create() : null,
      _runtime = PlatformUtils.isOhos
          ? null
          : getJavascriptRuntime(
              // cook 管线纯字符串运算，不需要 fetch/xhr 注入
              xhr: false,
            );

  final OhosQuickJs? _ohos;
  final JavascriptRuntime? _runtime;

  /// 引擎版本（用于日志）。
  String get engineVersion => _ohos != null
      ? 'ohos-quickjs ${OhosQuickJs.version ?? 'unknown'}'
      : 'flutter_js';

  /// 释放引擎资源（HarmonyOS 的 QuickJS 上下文需要显式释放）。
  void dispose() {
    _ohos?.dispose();
  }

  /// eval 一段 JS，返回其字符串结果；JS 抛错/引擎错误返回 null 并携带错误。
  ///
  /// [onError] 收到错误描述（用于日志），返回 null 表示失败。
  String? evaluate(String code, {void Function(String error)? onError}) {
    final ohos = _ohos;
    if (ohos != null) {
      final res = ohos.evaluate(code);
      if (res.isError) {
        onError?.call(res.error ?? 'unknown');
        return null;
      }
      return res.result;
    }
    try {
      final result = _runtime!.evaluate(code);
      if (result.isError) {
        onError?.call(result.stringResult);
        return null;
      }
      return result.stringResult;
    } catch (e) {
      onError?.call(e.toString());
      return null;
    }
  }
}
