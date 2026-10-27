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

  // 下面几组断言钉住的是「只在模拟器上才暴露」的两个缺陷的修复。
  // 没有它们，下次重构很容易把顺序改回去，问题又会静默复发。
  group('OHOS 平台分支顺序（真机回归）', () {
    /// 去掉注释，避免说明性文字里的关键字造成误判。
    String stripComments(String src) => src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('外链主路径必须走 ArkTS 桥白名单，不能只靠 canLaunchUrl', () {
      final src = stripComments(
        File('lib/utils/link_launcher.dart').readAsStringSync(),
      );
      final body = RegExp(
        r'Future<void> launchExternalLink\(([\s\S]*?)\n\}',
      ).firstMatch(src)?.group(0);
      expect(body, isNotNull, reason: '未找到 launchExternalLink');
      final ohosIndex = body!.indexOf('_openExternallyOnOhos');
      final canLaunchIndex = body.indexOf('canLaunchUrl');
      expect(ohosIndex, greaterThan(-1), reason: '外链主路径没走 OHOS 桥');
      // canLaunchUrl 对带处理程序的自定义 scheme 返回 true，会绕过白名单
      expect(
        canLaunchIndex == -1 || ohosIndex < canLaunchIndex,
        isTrue,
        reason: 'OHOS 分支必须在 canLaunchUrl 之前 return',
      );
    });

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
