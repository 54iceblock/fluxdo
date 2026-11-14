import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 小程序 JS 消息数据。
///
/// 上游使用 flutter_inappwebview 6.2.0-beta 的 `JavaScriptHandlerFunctionData`
/// （带 isMainFrame / origin / requestUrl 来源信息）。本分支 inappwebview 固定在
/// 6.1.5（CPF fork），回调签名只有 `(List<dynamic> arguments)`，拿不到来源，
/// 因此这里只保证 [args]；来源字段为 null，表示「平台未提供」。
class MiniAppJsMessage {
  const MiniAppJsMessage({
    required this.args,
    this.isMainFrame,
    this.origin,
    this.requestUrl,
  });

  final List<dynamic> args;

  /// 是否来自主框架；6.1.5 无此信息，恒为 null。
  final bool? isMainFrame;

  /// 消息来源 origin；6.1.5 无此信息，恒为 null。
  final Uri? origin;

  /// 发起消息的页面 URL；6.1.5 无此信息，恒为 null。
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
    callback: (List<dynamic> arguments) =>
        handler(MiniAppJsMessage(args: arguments)),
  );
}
