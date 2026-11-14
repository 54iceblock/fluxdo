import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/modules/mini_apps/mini_app_js_handler_compat.dart';

final _entry = Uri.parse('https://linux.do/apps/abc?embed_mode=true');

MiniAppJsMessage _msg({
  bool? main = true,
  String? origin = 'https://linux.do',
  String? url = 'https://linux.do/apps/abc?embed_mode=true',
}) => MiniAppJsMessage(
  args: const [],
  isMainFrame: main,
  origin: origin == null ? null : Uri.parse(origin),
  requestUrl: url == null ? null : Uri.parse(url),
);

void main() {
  group('buildMiniAppJsMessage', () {
    test('无来源时字段全为 null', () {
      final m = buildMiniAppJsMessage([1], null);
      expect(m.args, [1]);
      expect(m.isMainFrame, isNull);
      expect(m.origin, isNull);
      expect(m.requestUrl, isNull);
    });

    test('有来源时填充字段，类型不对的字段视为缺失', () {
      final m = buildMiniAppJsMessage(
        const [],
        {
          'isMainFrame': true,
          'origin': 'https://linux.do',
          'frameUrl': 'https://linux.do/apps/abc',
        },
      );
      expect(m.isMainFrame, true);
      expect(m.origin, Uri.parse('https://linux.do'));
      expect(m.requestUrl?.path, '/apps/abc');
      final bad = buildMiniAppJsMessage(
        const [],
        {'isMainFrame': 'yes', 'origin': 1, 'frameUrl': ''},
      );
      expect(bad.isMainFrame, isNull);
      expect(bad.origin, isNull);
      expect(bad.requestUrl, isNull);
    });
  });

  group('isMiniAppMessageSourceAllowed', () {
    test('requireSource=true（鸿蒙）：主框架且来源匹配才放行', () {
      expect(
        isMiniAppMessageSourceAllowed(_msg(), _entry, requireSource: true),
        true,
      );
    });

    test('requireSource=true：任一来源缺失即拒绝（fail-closed）', () {
      for (final m in [
        const MiniAppJsMessage(args: []),
        _msg(main: null),
        _msg(origin: null),
        _msg(url: null),
      ]) {
        expect(
          isMiniAppMessageSourceAllowed(m, _entry, requireSource: true),
          false,
        );
      }
    });

    test('iframe（isMainFrame=false）在两种模式下都拒绝', () {
      for (final require in [true, false]) {
        expect(
          isMiniAppMessageSourceAllowed(
            _msg(main: false),
            _entry,
            requireSource: require,
          ),
          false,
        );
      }
    });

    test('requireSource=false（其他平台）：缺失来源跳过校验', () {
      expect(
        isMiniAppMessageSourceAllowed(
          const MiniAppJsMessage(args: []),
          _entry,
          requireSource: false,
        ),
        true,
      );
    });

    test('有值时严格比对 origin / host / port / path', () {
      for (final require in [true, false]) {
        expect(
          isMiniAppMessageSourceAllowed(
            _msg(origin: 'https://evil.example'),
            _entry,
            requireSource: require,
          ),
          false,
        );
        expect(
          isMiniAppMessageSourceAllowed(
            _msg(origin: 'https://linux.do:8443'),
            _entry,
            requireSource: require,
          ),
          false,
        );
        expect(
          isMiniAppMessageSourceAllowed(
            _msg(url: 'https://linux.do/apps/other'),
            _entry,
            requireSource: require,
          ),
          false,
        );
        expect(
          isMiniAppMessageSourceAllowed(
            _msg(),
            null,
            requireSource: require,
          ),
          false,
        );
      }
    });
  });

  group('鸿蒙目录形式 requestUrl（ArkWeb 截断到最后一个 /）', () {
    test('主框架目录形式放行（requireSource=true）', () {
      expect(
        isMiniAppMessageSourceAllowed(
          _msg(url: 'https://linux.do/apps/'),
          _entry,
          requireSource: true,
        ),
        true,
      );
    });

    test('不同目录 / 跨 origin / 缺失一律拒绝', () {
      for (final m in [
        _msg(url: 'https://linux.do/mock/'),
        _msg(url: 'https://linux.do/'),
        _msg(url: 'https://linux.do/apps/x/'),
        _msg(url: 'https://evil.example/apps/'),
        _msg(origin: 'https://evil.example', url: 'https://linux.do/apps/'),
        _msg(url: null),
        _msg(main: false, url: 'https://linux.do/apps/'),
      ]) {
        expect(
          isMiniAppMessageSourceAllowed(m, _entry, requireSource: true),
          false,
        );
      }
    });

    test('非鸿蒙模式不接受目录形式', () {
      expect(
        isMiniAppMessageSourceAllowed(
          _msg(url: 'https://linux.do/apps/'),
          _entry,
          requireSource: false,
        ),
        false,
      );
      expect(
        miniAppSourceRejectReason(
          _msg(url: 'https://linux.do/apps/'),
          _entry,
          requireSource: false,
        ),
        'request_url_mismatch',
      );
    });

    test('已知风险：同目录 iframe 与主框架不可区分（目录形式相同）', () {
      // 文档化局限：/apps/other 的 iframe 调用方 URL 也是 /apps/，会放行。
      expect(
        isMiniAppMessageSourceAllowed(
          _msg(url: 'https://linux.do/apps/'),
          Uri.parse('https://linux.do/apps/other'),
          requireSource: true,
        ),
        true,
      );
    });
  });

  group('miniAppSourceRejectReason', () {
    String? reason(MiniAppJsMessage m, {bool require = true}) =>
        miniAppSourceRejectReason(m, _entry, requireSource: require);

    test('放行时为 null，且与 isMiniAppMessageSourceAllowed 一致', () {
      expect(reason(_msg()), isNull);
      for (final require in [true, false]) {
        for (final m in [
          _msg(),
          _msg(main: false),
          _msg(main: null),
          _msg(origin: 'https://evil.example'),
          _msg(url: 'https://linux.do/apps/other'),
          const MiniAppJsMessage(args: []),
        ]) {
          expect(
            reason(m, require: require) == null,
            isMiniAppMessageSourceAllowed(m, _entry, requireSource: require),
          );
        }
      }
    });

    test('各拒绝原因', () {
      expect(reason(const MiniAppJsMessage(args: [])), 'source_missing');
      expect(reason(_msg(main: null)), 'source_missing');
      expect(reason(_msg(main: false)), 'not_main_frame');
      expect(reason(_msg(main: false), require: false), 'not_main_frame');
      expect(reason(_msg(origin: 'https://evil.example')), 'origin_mismatch');
      expect(
        reason(_msg(url: 'https://linux.do/apps/other')),
        'request_url_mismatch',
      );
    });
  });

  test('miniAppRequiresMessageSource 可被测试覆盖', () {
    debugMiniAppRequireSourceOverride = true;
    expect(miniAppRequiresMessageSource, true);
    debugMiniAppRequireSourceOverride = false;
    expect(miniAppRequiresMessageSource, false);
    debugMiniAppRequireSourceOverride = null;
    // 测试宿主不是鸿蒙
    expect(miniAppRequiresMessageSource, false);
  });
}
