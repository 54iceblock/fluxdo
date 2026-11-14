import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../utils/platform_utils.dart';

/// 小程序 JS 消息数据。
///
/// 上游使用 flutter_inappwebview 6.2.0-beta 的 `JavaScriptHandlerFunctionData`
/// （带 isMainFrame / origin / requestUrl 来源信息）。本分支 inappwebview 固定在
/// 6.1.5（CPF fork），回调签名只有 `(List<dynamic> arguments)`：
/// - 鸿蒙：使用 vendored 的 `flutter_inappwebview_ohos`（packages/ 下），ArkTS 侧在
///   `_callHandler` 入口取得调用方 frame 来源并随消息传到 Dart，这里在回调入口同步读取；
/// - 其他平台：拿不到来源，来源字段为 null，表示「平台未提供」。
class MiniAppJsMessage {
  const MiniAppJsMessage({
    required this.args,
    this.isMainFrame,
    this.origin,
    this.requestUrl,
  });

  final List<dynamic> args;

  /// 是否来自主框架；平台未提供时为 null。
  final bool? isMainFrame;

  /// 消息来源 origin；平台未提供时为 null。
  final Uri? origin;

  /// 发起消息的 frame URL；平台未提供时为 null。
  final Uri? requestUrl;
}

/// 静音页面媒体。6.2.0-beta 的 `controller.setMuted` 在 6.1.5 不存在，
/// 降级为用脚本把页面内 audio/video 元素静音（只影响主文档已有元素，
/// 之后新建的媒体元素不受控）。
Future<void> setMiniAppMuted(
  InAppWebViewController controller,
  bool muted,
) async {
  await controller.evaluateJavascript(
    source:
        "document.querySelectorAll('audio,video').forEach(function(m){m.muted=$muted;});",
  );
}

typedef MiniAppJsHandler = dynamic Function(MiniAppJsMessage message);

@visibleForTesting
bool? debugMiniAppRequireSourceOverride;

/// 当前平台是否必须拿到消息来源才放行小程序消息。
///
/// 鸿蒙：来源由 vendored 插件提供，缺失（null）一律拒绝（fail-closed）。
/// 其他平台：仍是 6.1.5，没有来源信息，保持「有值才校验」的旧行为。
bool get miniAppRequiresMessageSource =>
    debugMiniAppRequireSourceOverride ?? PlatformUtils.isOhos;

/// requestUrl 的 path 是否对应入口 [entry]。
///
/// 真机实测（HarmonyOS 7 / API 26）：ArkWeb 的 getLastJavascriptProxyCallingFrameUrl
/// 返回截断到「最后一个 /」的目录形式（`/apps/<uuid>?embed_mode=true` → `/apps/`）。
/// - [allowDirectoryForm] 为 false：path 必须与入口完全相等（其他平台行为不变）；
/// - 为 true（仅鸿蒙）：另接受「以 / 结尾且等于入口 path 目录形式」的 requestUrl。
/// 风险：同 origin 同目录的 iframe（如入口 /apps/a、iframe /apps/b）与主框架不可区分；
/// 不同目录 / 跨 origin 仍会被拒绝，后者另由 origin 校验与宿主 token 兜底。
@visibleForTesting
bool miniAppRequestPathMatchesEntry(
  Uri requestUrl,
  Uri? entry, {
  required bool allowDirectoryForm,
}) {
  if (entry == null) return false;
  if (requestUrl.path == entry.path) return true;
  if (!allowDirectoryForm) return false;
  final reqPath = requestUrl.path;
  if (!reqPath.endsWith('/')) return false;
  final entryPath = entry.path;
  final dir = entryPath.substring(0, entryPath.lastIndexOf('/') + 1);
  return reqPath == dir;
}

/// 小程序消息来源校验（纯函数，便于单测）。
///
/// - [requireSource] 为 true：`isMainFrame` 必须为 true，`origin`、`requestUrl`
///   必须存在，任一缺失即拒绝；此模式（鸿蒙）下 requestUrl 的 path 可为目录形式；
/// - [requireSource] 为 false：来源字段为 null 时跳过对应校验；
/// - 来源字段有值时，两种模式都严格比对 [entry] 的 scheme / host / port
///   （requestUrl 另比对 path）。
bool isMiniAppMessageSourceAllowed(
  MiniAppJsMessage message,
  Uri? entry, {
  required bool requireSource,
}) {
  if (requireSource &&
      (message.isMainFrame != true ||
          message.origin == null ||
          message.requestUrl == null)) {
    return false;
  }
  if (message.isMainFrame == false) return false;
  final origin = message.origin;
  if (origin != null &&
      !(origin.scheme == entry?.scheme &&
          origin.host == entry?.host &&
          origin.port == entry?.port)) {
    return false;
  }
  final requestUrl = message.requestUrl;
  if (requestUrl != null &&
      !(requestUrl.scheme == entry?.scheme &&
          requestUrl.host == entry?.host &&
          requestUrl.port == entry?.port &&
          miniAppRequestPathMatchesEntry(
            requestUrl,
            entry,
            allowDirectoryForm: requireSource,
          ))) {
    return false;
  }
  return true;
}

/// 来源校验被拒绝的原因（与 [isMiniAppMessageSourceAllowed] 的判定顺序一致，
/// 仅用于诊断日志与限频分组）；放行时返回 null。
String? miniAppSourceRejectReason(
  MiniAppJsMessage message,
  Uri? entry, {
  required bool requireSource,
}) {
  if (requireSource) {
    if (message.isMainFrame == null ||
        message.origin == null ||
        message.requestUrl == null) {
      return 'source_missing';
    }
    if (message.isMainFrame != true) return 'not_main_frame';
  }
  if (message.isMainFrame == false) return 'not_main_frame';
  final origin = message.origin;
  if (origin != null &&
      !(origin.scheme == entry?.scheme &&
          origin.host == entry?.host &&
          origin.port == entry?.port)) {
    return 'origin_mismatch';
  }
  final requestUrl = message.requestUrl;
  if (requestUrl != null &&
      !(requestUrl.scheme == entry?.scheme &&
          requestUrl.host == entry?.host &&
          requestUrl.port == entry?.port &&
          miniAppRequestPathMatchesEntry(
            requestUrl,
            entry,
            allowDirectoryForm: requireSource,
          ))) {
    return 'request_url_mismatch';
  }
  return null;
}

/// 读取 vendored 鸿蒙插件在「本次 handler 调用」期间设置的来源信息。
///
/// 必须在 handler 回调入口、第一个 await 之前同步调用：插件在调用 handler 前设置、
/// handler 同步部分返回后清除，Dart 单线程逐条处理消息，因此不会串号。
/// 读取失败（插件不是 vendored 版本、字段缺失）返回 null；鸿蒙下由
/// [isMiniAppMessageSourceAllowed] fail-closed 拒绝。
@visibleForTesting
Map<String, Object?>? readOhosJsCallSource(InAppWebViewController controller) {
  try {
    final source = (controller.platform as dynamic).currentJsCallSource;
    if (source is Map) return Map<String, Object?>.from(source);
  } catch (_) {}
  return null;
}

Uri? _parseUri(Object? value) =>
    value is String && value.isNotEmpty ? Uri.tryParse(value) : null;

/// 由来源 map（`frameUrl` / `origin` / `isMainFrame`）构造消息。
@visibleForTesting
MiniAppJsMessage buildMiniAppJsMessage(
  List<dynamic> arguments,
  Map<String, Object?>? source,
) {
  if (source == null) return MiniAppJsMessage(args: arguments);
  final isMainFrame = source['isMainFrame'];
  return MiniAppJsMessage(
    args: arguments,
    isMainFrame: isMainFrame is bool ? isMainFrame : null,
    origin: _parseUri(source['origin']),
    requestUrl: _parseUri(source['frameUrl']),
  );
}

/// 在 6.1.5 API 上注册小程序 JS handler，把 arguments 包装成 [MiniAppJsMessage]。
///
/// 升级到 6.2.0-beta 后，只需把本函数改成读取 `JavaScriptHandlerFunctionData`
/// 填充来源字段，调用方无需改动。
void addMiniAppJsHandler(
  InAppWebViewController controller,
  String handlerName,
  MiniAppJsHandler handler,
) {
  controller.addJavaScriptHandler(
    handlerName: handlerName,
    callback: (List<dynamic> arguments) {
      // 必须先于任何 await 同步读取来源。
      // 非鸿蒙插件没有该字段，读取失败返回 null（保持「平台未提供」语义）。
      final source = readOhosJsCallSource(controller);
      return handler(buildMiniAppJsMessage(arguments, source));
    },
  );
}
