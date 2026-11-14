import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 鸿蒙插件 / 原生库守卫：
/// `desktop_multi_window`、`jni`、`jni_flutter` 只给桌面 / Android 用，
/// `rhttp`、`doh_proxy` 已随同步上游 v0.2.30 删除，都不能进入鸿蒙构建。
///
/// 生成物（`.flutter-plugins-dependencies`、`GeneratedPluginRegistrant.ets`）
/// 由 `flutter pub get` / 构建产生且被 gitignore，不存在时跳过对应断言。
const _forbidden = <String>[
  'desktop_multi_window',
  'jni',
  'jni_flutter',
  'rhttp',
  'doh_proxy',
];

void main() {
  group('鸿蒙插件注册守卫', () {
    test('.flutter-plugins-dependencies 的 ohos 段不含禁入插件', () {
      final file = File('.flutter-plugins-dependencies');
      if (!file.existsSync()) {
        markTestSkipped('未生成 .flutter-plugins-dependencies，先运行 flutter pub get');
        return;
      }
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final ohos = ((json['plugins'] as Map<String, dynamic>)['ohos'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final names = ohos.map((p) => p['name'] as String).toSet();
      expect(names, isNotEmpty, reason: 'ohos 段为空，生成物异常');
      for (final name in _forbidden) {
        expect(names, isNot(contains(name)), reason: '$name 不应注册到鸿蒙插件');
      }
    });

    test('GeneratedPluginRegistrant.ets 不含禁入插件', () {
      final file = File(
        'ohos/entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets',
      );
      if (!file.existsSync()) {
        markTestSkipped('未生成 GeneratedPluginRegistrant.ets');
        return;
      }
      final src = file.readAsStringSync().toLowerCase();
      for (final name in _forbidden) {
        // 以 import 来源的包名判断，避免类名子串误判
        expect(
          RegExp("from '$name[^']*'").hasMatch(src),
          isFalse,
          reason: '$name 不应出现在鸿蒙插件注册文件中',
        );
      }
    });

    test('ohos/entry/libs 下只有预期的原生库，不含 jni / rhttp / doh_proxy', () {
      for (final abi in const ['arm64-v8a', 'x86_64']) {
        final dir = Directory('ohos/entry/libs/$abi');
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync().whereType<File>()) {
          final name = f.uri.pathSegments.last.toLowerCase();
          for (final bad in const ['jni', 'rhttp', 'doh_proxy', 'multi_window']) {
            expect(name, isNot(contains(bad)), reason: '$abi/$name 不应入库');
          }
        }
      }
    });
  });

  group('JNI / 多窗口的 Dart 运行时守卫', () {
    test('net_core_service 的 JNI 读取只在 Platform.isAndroid 下进入', () {
      final src = File(
        'lib/services/network/core/net_core_service.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'if \(!Platform\.isAndroid[^)]*\) return this;').hasMatch(src),
        isTrue,
        reason: 'withDetectedSystemProxy 必须先用 Platform.isAndroid 挡掉非安卓平台',
      );
      expect(
        RegExp('_androidSystemProxy\\(').allMatches(src).length,
        2,
        reason: '_androidSystemProxy 应只有定义 + withDetectedSystemProxy 一处调用',
      );
    });

    test('MiniAppWindowBridge.desktop 只覆盖 Windows / macOS / Linux', () {
      final src = File(
        'lib/modules/mini_apps/mini_app_window_bridge.dart',
      ).readAsStringSync();
      expect(
        src,
        contains(
          'Platform.isWindows || Platform.isMacOS || Platform.isLinux',
        ),
      );
      // 鸿蒙的 Platform.operatingSystem 是 'ohos'，isLinux 为 false；
      // 一旦有人把 isOhos 并入 desktop 就会进入 desktop_multi_window 路径。
      expect(src, isNot(contains('isOhos')));
    });
  });
}
