import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'ohos_compat.dart';
import 'platform_utils.dart';

/// 剪贴板的统一出口。
///
/// 背景：`super_clipboard` 没有 OHOS 原生实现（`super_native_extensions` 的
/// `DynamicLibrary.process().lookup(...)` 在 OHOS 上会抛 `ArgumentError`），所以：
///
/// - **写文本**：一律走 Flutter 自带的 `Clipboard.setData`，全平台可用；
/// - **写图片**：非 OHOS 走 `super_clipboard`（保留原义的 PNG 语义）；
///   OHOS 走自研 ArkTS 桥（`writeImageToPasteboard`：PNG → PixelMap → 系统剪贴板），
///   失败且有可读文本（如图片 URL）时退化为复制文本；
/// - **读 HTML**：OHOS 走自研桥（`readClipboardHtml`），其它平台由调用方走
///   `super_clipboard`（本类不碰 `SystemClipboard`，避免 OHOS 上取 instance 抛异常）。
///
/// 关键点：OHOS 上 **不要** 触碰 `SystemClipboard.instance`。
abstract final class ClipboardUtils {
  static const MethodChannel _ohosChannel = MethodChannel('com.fluxdo/ohos');

  /// 是否有 super_clipboard（图片/富文本）能力（OHOS 为 false，改用自研桥）。
  static bool get supportsRichClipboard => OhosCompat.supportsRichClipboard;

  /// OHOS 是否支持经自研桥访问富内容剪贴板（写图片 / 读 HTML）。
  static bool get supportsOhosRichClipboard => PlatformUtils.isOhos;

  /// 复制纯文本（全平台可用，不依赖任何插件）。
  static Future<void> copyText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  /// 复制 PNG 位图。
  ///
  /// 返回 `true` 表示图片已写入系统剪贴板；返回 `false` 表示写入失败，
  /// 此时若有 [fallbackText] 会退化为复制该文本（调用方据此换文案）。
  static Future<bool> copyPngImage(
    Uint8List bytes, {
    String? fallbackText,
  }) async {
    if (PlatformUtils.isOhos) {
      try {
        await _ohosChannel.invokeMethod<bool>(
          'writeImageToPasteboard',
          <String, Object>{'bytes': bytes},
        );
        return true;
      } catch (e) {
        debugPrint('[ClipboardUtils] OHOS 写入图片剪贴板失败: $e');
      }
    } else if (supportsRichClipboard) {
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

  /// 读取系统剪贴板中的 HTML 片段。
  ///
  /// 仅 OHOS 实现（走 ArkTS 桥）；其它平台返回 `null`，由调用方走
  /// `super_clipboard` 的富文本读取路径。
  static Future<String?> readHtml() async {
    if (!PlatformUtils.isOhos) return null;
    try {
      final html = await _ohosChannel.invokeMethod<String>('readClipboardHtml');
      if (html == null || html.trim().isEmpty) return null;
      return html;
    } catch (e) {
      debugPrint('[ClipboardUtils] OHOS 读取剪贴板 HTML 失败: $e');
      return null;
    }
  }
}
