import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 去掉注释，避免「注释里说明为什么删掉某权限」被断言误判。
String stripComments(String src) {
  final withoutBlock = src.replaceAll(
    RegExp(r'/\*[\s\S]*?\*/', multiLine: true),
    '',
  );
  return withoutBlock
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}

/// vendored 插件的本地改动回归测试（源码级断言）。
///
/// 这些改动都是「原生代码行为」的修正，没法在宿主机跑 ArkTS，但可以用源码断言
/// 把结论钉住：一旦有人重新拷贝上游插件、把改动冲掉，测试会立刻失败。
void main() {
  group('record_ohos：麦克风权限必须按需申请', () {
    final plugin = File(
      'packages/record_ohos/ohos/src/main/ets/components/plugin/RecordOhosPlugin.ets',
    );
    final handler = File(
      'packages/record_ohos/ohos/src/main/ets/components/plugin/MethodCallHandlerImpl.ets',
    );

    test('onAttachedToEngine 不得申请权限', () {
      final src = stripComments(plugin.readAsStringSync());
      final attach = RegExp(
        r'onAttachedToEngine\(binding: FlutterPluginBinding\): void \{([\s\S]*?)\n  \}',
      ).firstMatch(src)?.group(1);
      expect(attach, isNotNull, reason: '未找到 onAttachedToEngine');
      // 上游在这里调 checkPermission()，导致冷启动弹麦克风授权
      expect(
        attach,
        isNot(contains('checkPermission')),
        reason: '引擎 attach 阶段不能申请麦克风权限（冷启动会弹框）',
      );
      expect(
        attach,
        isNot(contains('requestPermissionsFromUser')),
        reason: '引擎 attach 阶段不能申请麦克风权限（冷启动会弹框）',
      );
    });

    test('permission 由 hasPermission 触发，且不再硬编码 true', () {
      final src = stripComments(handler.readAsStringSync());
      final caseBody = RegExp(
        r'case "hasPermission":([\s\S]*?)break;',
      ).firstMatch(src)?.group(1);
      expect(caseBody, isNotNull);
      expect(
        caseBody!.trim(),
        isNot('result.success(true);'),
        reason: 'hasPermission 不能写死 true（Dart 会以为有权限、start 失败）',
      );
      expect(src, contains('permissionProvider'));
    });

    test('申请结果是真实返回值', () {
      final src = stripComments(plugin.readAsStringSync());
      expect(src, contains('ensurePermission'));
      expect(
        RegExp(r'async requestNecessaryPermissions\([^)]*\): Promise<boolean>')
            .hasMatch(src),
        isTrue,
        reason: '申请权限必须返回是否授予，否则 Dart 无法判断',
      );
    });
  });

  group('flutter_local_notifications：去掉 PUBLISH_AGENT_REMINDER', () {
    test('HAR 的 module.json5 不再声明该权限', () {
      final src = stripComments(
        File(
          'packages/flutter_local_notifications/ohos/src/main/module.json5',
        ).readAsStringSync(),
      );
      expect(
        src,
        isNot(contains('PUBLISH_AGENT_REMINDER')),
        reason: 'HAR 权限会被 hvigor 合并进最终 HAP，删应用侧声明无效',
      );
    });

    test('应用侧 module.json5 也不声明它', () {
      final src = stripComments(
        File('ohos/entry/src/main/module.json5').readAsStringSync(),
      );
      expect(src, isNot(contains('PUBLISH_AGENT_REMINDER')));
    });
  });

  group('module.json5：应用权限集合', () {
    // 权限收敛原则：只声明真的会用到的权限（上架审核逐项核对）。
    // 增删权限必须同步改这里，并解包 HAP 核对 hvigor 合并后的最终集合。
    test('requestPermissions 恰为约定的 5 项', () {
      final src = stripComments(
        File('ohos/entry/src/main/module.json5').readAsStringSync(),
      );
      final declared = RegExp(r'"name":\s*"(ohos\.permission\.[A-Z_]+)"')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toList();
      expect(declared.toSet().length, declared.length, reason: '存在重复声明');
      expect(declared.toSet(), {
        'ohos.permission.INTERNET',
        'ohos.permission.GET_NETWORK_INFO',
        // 触感反馈：缺失时真机报 HapticFeedback.vibrate error 201
        'ohos.permission.VIBRATE',
        'ohos.permission.CAMERA',
        'ohos.permission.MICROPHONE',
      });
    });

    test('user_grant 权限必须带 reason 与 usedScene', () {
      final src = stripComments(
        File('ohos/entry/src/main/module.json5').readAsStringSync(),
      );
      for (final p in ['CAMERA', 'MICROPHONE']) {
        final block = RegExp(
          '"name":\\s*"ohos\\.permission\\.$p"[\\s\\S]*?\\n      \\}',
        ).firstMatch(src)?.group(0);
        expect(block, isNotNull, reason: '未找到 $p');
        expect(block, contains('"reason"'), reason: '$p 缺 reason');
        expect(block, contains('"usedScene"'), reason: '$p 缺 usedScene');
      }
    });
  });

  group('build-profile.json5：签名材料不得入库', () {
    test('signingConfigs 为空数组且无口令字段', () {
      final src = stripComments(
        File('ohos/build-profile.json5').readAsStringSync(),
      );
      expect(src, contains('"signingConfigs": []'));
      expect(src, isNot(contains('keyPassword')));
      expect(src, isNot(contains('storePassword')));
      expect(src, isNot(contains('certpath')));
    });
  });
}
