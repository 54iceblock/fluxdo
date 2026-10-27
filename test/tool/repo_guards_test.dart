@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 两个守卫脚本（tool/check_no_secrets.dart、tool/check_ohos_pubspec.dart）的
/// 端到端测试：在临时目录里搭最小「假仓库」，用 `--root` 指过去跑脚本，看退出码。
/// `flutter test` 下 Platform.resolvedExecutable 是 flutter_tester，不是 dart：
/// 按 FLUTTER_ROOT 定位 SDK 自带的 dart，找不到再退回 PATH 上的 `dart`。
String _dartExecutable() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final exe = Platform.isWindows ? 'dart.exe' : 'dart';
    final f = File('$root/bin/cache/dart-sdk/bin/$exe');
    if (f.existsSync()) return f.path;
  }
  return 'dart';
}

void main() {
  final String dart = _dartExecutable();
  final String repo = Directory.current.path;
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fluxdo_guard_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String rel, String content) {
    final f = File('${tmp.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  // 脚本输出 UTF-8；Windows 默认按系统代码页（GBK）解码会把中文和路径搅乱。
  Future<ProcessResult> run(String script, [List<String> extra = const []]) =>
      Process.run(
        dart,
        <String>['$repo/tool/$script', '--root', tmp.path, ...extra],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  group('check_no_secrets', () {
    const cleanProfile = '{ "app": { "signingConfigs": [], "products": [] } }';

    test('干净仓库通过', () async {
      write('ohos/build-profile.json5', cleanProfile);
      final r = await run('check_no_secrets.dart');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('signingConfigs 非空时失败，--fix 能复位', () async {
      write('ohos/build-profile.json5', '''
{ "app": { "signingConfigs": [ { "name": "default", "material": { "keyAlias": "debugKey" } } ], "products": [] } }
''');
      final bad = await run('check_no_secrets.dart');
      expect(bad.exitCode, 1);
      expect('${bad.stderr}', contains('signingConfigs'));

      final fixed = await run('check_no_secrets.dart', ['--fix']);
      expect(fixed.exitCode, 0, reason: '${fixed.stdout}${fixed.stderr}');
      expect(
        File('${tmp.path}/ohos/build-profile.json5').readAsStringSync(),
        contains('"signingConfigs": []'),
      );
    });

    test('提交了口令字段或证书文件时失败', () async {
      write('ohos/build-profile.json5', cleanProfile);
      write('ohos/other.json5', '{ "storePassword": "0000001B" }');
      final r1 = await run('check_no_secrets.dart');
      expect(r1.exitCode, 1);
      expect('${r1.stderr}', contains('ohos/other.json5'));

      File('${tmp.path}/ohos/other.json5').deleteSync();
      final cert = File('${tmp.path}/certs/debug.p12');
      cert.parent.createSync(recursive: true);
      cert.writeAsBytesSync(<int>[0x30, 0x82]);
      final r2 = await run('check_no_secrets.dart');
      expect(r2.exitCode, 1);
      expect('${r2.stderr}', contains('certs/debug.p12'));
    });

    test('构建产物目录（.hvigor/build）不参与扫描', () async {
      write('ohos/build-profile.json5', cleanProfile);
      write('ohos/.hvigor/outputs/sync/output.json', '{ "storePassword": "x" }');
      write('build/x.json', '{ "keyPassword": "x" }');
      final r = await run('check_no_secrets.dart');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });
  });

  group('check_ohos_pubspec', () {
    const sha = '8b5ba6a9ef3a28558177e9193319a0700f9cc640';

    String pubspec(String ref) => '''
name: demo
dependencies:
  flutter:
    sdk: flutter
  record_ohos:
    git:
      url: https://example.com/record_ohos.git
      ref: $sha
dependency_overrides:
  device_info_plus:
    git:
      url: https://example.com/plus.git
      ref: $ref
      path: packages/device_info_plus
  flutter_rust_bridge: 2.12.0
''';

    String lock(String ref) => '''
packages:
  device_info_plus:
    dependency: "direct overridden"
    description:
      path: "packages/device_info_plus"
      ref: $ref
      resolved-ref: $sha
      url: "https://example.com/plus.git"
    source: git
    version: "12.3.0"
''';

    test('全部锁 SHA 且与 lock 一致时通过', () async {
      write('pubspec.yaml', pubspec(sha));
      write('pubspec.lock', lock(sha));
      final r = await run('check_ohos_pubspec.dart');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('写分支名时失败', () async {
      write('pubspec.yaml', pubspec('br_device_info_plus-v12.3.0_ohos'));
      final r = await run('check_ohos_pubspec.dart');
      expect(r.exitCode, 1);
      expect('${r.stderr}', contains('device_info_plus'));
    });

    test('pubspec 与 lock 的 ref 不一致时失败', () async {
      write('pubspec.yaml', pubspec(sha));
      write('pubspec.lock', lock('br_old'));
      final r = await run('check_ohos_pubspec.dart');
      expect(r.exitCode, 1);
      expect('${r.stderr}', contains('pubspec.lock'));
    });

    test('--portable 把 OHOS fork override 还原成上游形态，保留其它', () async {
      write('pubspec.yaml', pubspec(sha));
      final r = await run('check_ohos_pubspec.dart', ['--portable', 'out.yaml']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final out = File('${tmp.path}/out.yaml').readAsStringSync();
      // device_info_plus 不能删：上游靠它压住 super_clipboard 的 <12.0.0 约束，
      // 删了非 OHOS 平台会 version solving failed（实测）。应还原成 hosted pin。
      expect(out, contains('  device_info_plus: 12.3.0'));
      expect(out, isNot(contains('packages/device_info_plus')));
      expect(out, isNot(contains('example.com/plus.git')));
      // 上游有、OHOS 版删掉的桌面 override 要补回
      expect(out, contains('flutter_inappwebview_windows'));
      expect(out, contains('flutter_inappwebview_linux'));
      expect(out, contains('flutter_rust_bridge: 2.12.0'));
      expect(out, contains('record_ohos:'));
    });
  });
}
