import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/fit_long_edge.dart';
import 'package:fluxdo/utils/ohos_external_url.dart';

void main() {
  group('OhosExternalUrl.isAllowed', () {
    test('放行 http/https/mailto/tel（大小写不敏感）', () {
      expect(OhosExternalUrl.isAllowed('https://linux.do/t/1'), isTrue);
      expect(OhosExternalUrl.isAllowed('http://example.com'), isTrue);
      expect(OhosExternalUrl.isAllowed('HTTPS://Example.com/a'), isTrue);
      expect(OhosExternalUrl.isAllowed('mailto:a@b.com'), isTrue);
      expect(OhosExternalUrl.isAllowed('tel:10086'), isTrue);
      expect(OhosExternalUrl.isAllowed('  https://linux.do  '), isTrue);
    });

    test('拒绝危险或未知 scheme', () {
      expect(OhosExternalUrl.isAllowed('javascript:alert(1)'), isFalse);
      expect(OhosExternalUrl.isAllowed('file:///data/storage/el2/x'), isFalse);
      expect(OhosExternalUrl.isAllowed('fluxdo://topic/1'), isFalse);
      expect(OhosExternalUrl.isAllowed('intent://x#Intent;end'), isFalse);
      expect(OhosExternalUrl.isAllowed('data:text/html,<b>x</b>'), isFalse);
    });

    test('拒绝无 scheme、空串与无 host 的 http(s)', () {
      expect(OhosExternalUrl.isAllowed(''), isFalse);
      expect(OhosExternalUrl.isAllowed('/t/topic/1'), isFalse);
      expect(OhosExternalUrl.isAllowed('linux.do'), isFalse);
      expect(OhosExternalUrl.isAllowed('https:'), isFalse);
    });

    test('与 ArkTS 桥（FluxdoBridgePlugin.ets）的白名单保持一致', () {
      final ets = File(
        'ohos/entry/src/main/ets/plugins/FluxdoBridgePlugin.ets',
      ).readAsStringSync();
      final bridgeSchemes = RegExp(r"lower\.startsWith\('([a-z]+):")
          .allMatches(ets)
          .map((m) => m.group(1)!)
          .toSet();
      expect(bridgeSchemes, OhosExternalUrl.allowedSchemes);
    });
  });

  group('fitLongEdge', () {
    test('不需要缩放时返回 null', () {
      expect(fitLongEdge(100, 80, null), isNull);
      expect(fitLongEdge(100, 80, 0), isNull);
      expect(fitLongEdge(100, 80, 256), isNull);
      expect(fitLongEdge(256, 256, 256), isNull);
      expect(fitLongEdge(0, 80, 256), isNull);
    });

    test('横图按宽、竖图按高缩到 maxDim', () {
      expect(fitLongEdge(4000, 3000, 256), (256, 192));
      expect(fitLongEdge(3000, 4000, 256), (192, 256));
      expect(fitLongEdge(1204, 800, 256), (256, 170));
    });

    test('极端长宽比时短边至少为 1', () {
      expect(fitLongEdge(10000, 1, 100), (100, 1));
      expect(fitLongEdge(1, 10000, 100), (1, 100));
    });

    test('与 C 侧降采样换算一致（ohos-avif-decode.c 用同样的整数除法）', () {
      final c = File('ohos/tools/ohos-avif-decode.c').readAsStringSync();
      expect(c, contains('out_height = (int)(((int64_t)h * max_dim) / w);'));
      expect(c, contains('out_width = (int)(((int64_t)w * max_dim) / h);'));
    });
  });
}
