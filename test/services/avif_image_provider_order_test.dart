import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AVIF 解码顺序的源码级回归测试。
///
/// 背景：OHOS 引擎的 `ImageDescriptor.encoded` + `instantiateCodec` 对 AVIF
/// **会成功返回 codec，但取到的帧是空图**（系统 `AvifDecoderImpl` 只解析容器头）。
/// 因此 `_tryPlatformAvifCodec` 里必须先试自编 libavif（`_tryOhosAvifCodec`），
/// 再把引擎 codec（`_tryEngineAvifCodec`）当兜底——顺序一旦被重构改回去，
/// 正文里的 AVIF 就会静默显示成全灰占位符，且日志里没有任何错误。
///
/// 这个断言只在模拟器/真机实测中才暴露过，普通单测覆盖不到，所以用源码顺序兜住。
void main() {
  /// 去掉注释，避免说明性文字里的关键字造成误判。
  String stripComments(String src) => src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('AVIF 解码顺序（真机回归）', () {
    test('AVIF 必须自编 libavif 优先，引擎 codec 只能兜底', () {
      final src = stripComments(
        File('lib/services/avif_image_provider.dart').readAsStringSync(),
      );
      final body = RegExp(
        r'Future<ui\.Codec\?> _tryPlatformAvifCodec\(([\s\S]*?)\n\}',
      ).firstMatch(src)?.group(0);
      expect(body, isNotNull, reason: '未找到 _tryPlatformAvifCodec');
      final ohosIndex = body!.indexOf('_tryOhosAvifCodec');
      final engineIndex = body.indexOf('_tryEngineAvifCodec');
      expect(ohosIndex, greaterThan(-1));
      expect(engineIndex, greaterThan(-1));
      // 引擎对 AVIF 会「成功返回 codec 但取帧为空」，先试引擎就永远到不了自编库
      expect(
        ohosIndex < engineIndex,
        isTrue,
        reason: 'OHOS 必须先试自编 libavif，否则 AVIF 图片会显示破损占位符',
      );
    });
  });
}
