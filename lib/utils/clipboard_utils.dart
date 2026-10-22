import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'ohos_compat.dart';

/// 剪贴板的统一出口。
///
/// 背景：`super_clipboard` 没有 OHOS 原生实现（`super_native_extensions` 的
/// `DynamicLibrary.process().lookup('super_native_extensions_init_message_channel_context')`
/// 在 OHOS 上会抛 `ArgumentError: Failed to lookup symbol`），所以：
///
/// - **写文本**：一律走 Flutter 自带的 `Clipboard.setData`，全平台可用；
/// - **写图片**：非 OHOS 继续走 `super_clipboard`（保留原先的 PNG 语义），
///   OHOS 上按 [OhosCompat.supportsRichClipboard] 关闭并降级——有可读文本
///   （如图片 URL）时退化为复制文本，没有就返回 false 由调用方提示；
/// - **读富内容**（粘贴 html / 粘贴图片）：OHOS 上直接返回不可用，由调用方
///   回落到 TextField 的纯文本粘贴。
///
/// 关键点：OHOS 上 **不要** 触碰 [SystemClipboard.instance]（它会在取
/// instance 时就初始化原生上下文并抛异常），所有调用必须先看能力开关。
abstract final class ClipboardUtils {
  /// 当前平台是否支持图片/富文本剪贴板（OHOS 为 false）。
  static bool get supportsRichClipboard => OhosCompat.supportsRichClipboard;

  /// 复制纯文本（全平台可用，不依赖任何插件）。
  static Future<void> copyText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  /// 复制 PNG 位图。
  ///
  /// 返回 `true` 表示图片已写入系统剪贴板；返回 `false` 表示当前平台不支持
  /// （OHOS），此时若有 [fallbackText] 会退化为复制该文本（调用方据此换文案）。
  static Future<bool> copyPngImage(
    Uint8List bytes, {
    String? fallbackText,
  }) async {
    if (supportsRichClipboard) {
      try {
        final clipboard = SystemClipboard.instance;
        if (clipboard != null) {
          final item = DataWriterItem();
          item.add(Formats.png(bytes));
          await clipboard.write([item]);
          return true;
        }
        debugPrint('[ClipboardUtils] 系统剪贴板不可用');
      } catch (e) {
        debugPrint('[ClipboardUtils] 写入图片剪贴板失败: $e');
      }
    }
    if (fallbackText != null && fallbackText.isNotEmpty) {
      await copyText(fallbackText);
    }
    return false;
  }
}
