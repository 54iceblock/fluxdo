import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse_cook_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  group('DiscourseCookService.release', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() async {
      final loaded = await PreloadedDataService().hydrateFromHtml(
        '<meta id="data-discourse-setup">'
        '<script id="data-preloaded" type="application/json">${jsonEncode({
          'currentUser': {'id': 1, 'username': 'tester'},
          'siteSettings': {'max_post_length': 10000},
          'site': {'categories': [], 'top_tags': []},
        })}</script>',
      );
      expect(loaded, isTrue);
    });

    tearDown(() => DiscourseCookService().release(reason: 'test'));

    test('释放后引擎为空，下次 cook 懒重建且结果一致', () async {
      final service = DiscourseCookService();
      final first = await service.cook('**hello**');
      expect(first, contains('<strong>hello</strong>'));
      expect(service.hasEngine, isTrue);

      service.release(reason: 'test');
      expect(service.hasEngine, isFalse);

      final second = await service.cook('**hello**');
      expect(second, first);
      expect(service.hasEngine, isTrue);
    });

    test('重复释放与未初始化时释放都安全', () {
      final service = DiscourseCookService();
      service.release(reason: 'test');
      service.release(reason: 'test');
      expect(service.hasEngine, isFalse);
    });

    test('空闲释放时长为 2 分钟', () {
      expect(DiscourseCookService.idleReleaseDelay, const Duration(minutes: 2));
    });
  });

  group('DiscourseCookService.postProcessCooked', () {
    test('span.mention 转成 a.mention 并拼 baseUri', () {
      const cooked = '<p>hi <span class="mention">@sam_saffron</span>!</p>';
      final result = DiscourseCookService.postProcessCooked(
        cooked,
        baseUri: '',
      );
      expect(
        result,
        '<p>hi <a class="mention" href="/u/sam_saffron">@sam_saffron</a>!</p>',
      );
    });

    test('子路径部署时 href 带 baseUri 前缀', () {
      const cooked = '<p><span class="mention">@alice</span></p>';
      final result = DiscourseCookService.postProcessCooked(
        cooked,
        baseUri: '/forum',
      );
      expect(result, contains('href="/forum/u/alice"'));
    });

    test('多个 mention 全部转换', () {
      const cooked =
          '<p><span class="mention">@a</span> 和 <span class="mention">@b</span></p>';
      final result = DiscourseCookService.postProcessCooked(
        cooked,
        baseUri: '',
      );
      expect(result, contains('href="/u/a"'));
      expect(result, contains('href="/u/b"'));
      expect(result, isNot(contains('<span class="mention">')));
    });

    test('code 块内被转义的 mention 形态不受影响', () {
      // cook 会把 code 内的 < 转义成 &lt;，正则匹配不到，保持原样
      const cooked =
          '<pre><code>&lt;span class="mention"&gt;@x&lt;/span&gt;</code></pre>';
      final result = DiscourseCookService.postProcessCooked(
        cooked,
        baseUri: '',
      );
      expect(result, cooked);
    });

    test('无 mention 时原样返回', () {
      const cooked = '<p>普通段落</p>';
      expect(
        DiscourseCookService.postProcessCooked(cooked, baseUri: ''),
        cooked,
      );
    });
  });

  group('DiscourseCookService.extractOneboxTargets', () {
    test('块级 a.onebox 提取到 blockUrls', () {
      const cooked =
          '<p><a href="https://example.com/page" class="onebox" target="_blank">https://example.com/page</a></p>';
      final t = DiscourseCookService.extractOneboxTargets(cooked);
      expect(t.blockUrls, ['https://example.com/page']);
      expect(t.inlineUrls, isEmpty);
    });

    test('行内 inline-onebox-loading 提取到 inlineUrls', () {
      const cooked =
          '<p>参考 <a href="https://example.com/deep/path" class="inline-onebox-loading">https://example.com/deep/path</a> 这篇</p>';
      final t = DiscourseCookService.extractOneboxTargets(cooked);
      expect(t.blockUrls, isEmpty);
      expect(t.inlineUrls, ['https://example.com/deep/path']);
    });

    test('已展开的 inline-onebox 不再提取', () {
      const cooked =
          '<p><a href="https://example.com/a" class="inline-onebox">标题</a></p>';
      final t = DiscourseCookService.extractOneboxTargets(cooked);
      expect(t.blockUrls, isEmpty);
      expect(t.inlineUrls, isEmpty);
    });

    test('普通链接与 mention 不提取，href 实体解码，重复去重', () {
      const cooked =
          '<p><a href="https://x.com">普通</a>'
          '<a class="mention" href="/u/sam">@sam</a>'
          '<a href="https://example.com/q?a=1&amp;b=2" class="onebox">x</a>'
          '<a href="https://example.com/q?a=1&amp;b=2" class="onebox">x</a></p>';
      final t = DiscourseCookService.extractOneboxTargets(cooked);
      expect(t.blockUrls, ['https://example.com/q?a=1&b=2']);
      expect(t.inlineUrls, isEmpty);
    });
  });
}
