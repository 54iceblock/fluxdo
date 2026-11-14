import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 鸿蒙网络栈守卫：rhttp / DOH 代理已在同步上游 v0.2.30 时删除，改用 net_core。
void main() {
  group('鸿蒙网络核心守卫', () {
    for (final abi in const ['arm64-v8a', 'x86_64']) {
      for (final lib in const ['librhttp.so', 'libdoh_proxy.so']) {
        test('ohos/entry/libs/$abi 下不得再有 $lib', () {
          expect(
            File('ohos/entry/libs/$abi/$lib').existsSync(),
            isFalse,
            reason: '$lib 已随 rhttp / DOH 代理删除，不应再入库',
          );
        });
      }
    }

    test('net_core_bindings 包含鸿蒙加载分支', () {
      final src = File(
        'lib/services/network/core/net_core_bindings.dart',
      ).readAsStringSync();
      expect(src, contains('libfluxdo_net.so'));
      expect(src, contains('isOhos'));
      // isOhos 分支内必须加载 libfluxdo_net.so
      expect(
        RegExp(
          r"isOhos\)\s*\{[^}]*DynamicLibrary\.open\('libfluxdo_net\.so'\)",
        ).hasMatch(src),
        isTrue,
        reason: 'PlatformUtils.isOhos 分支应 open libfluxdo_net.so',
      );
    });

    for (final abi in const ['arm64-v8a', 'x86_64']) {
      test('ohos/entry/libs/$abi 下必须有 libfluxdo_net.so', () {
        final so = File('ohos/entry/libs/$abi/libfluxdo_net.so');
        expect(
          so.existsSync(),
          isTrue,
          reason: '鸿蒙网络核心库缺失：运行 ohos/tools/build-netcore-ohos.sh 重新生成',
        );
        // 防止误入库空文件或构建中断留下的半截文件（实测 14–17 MB）
        expect(so.lengthSync(), greaterThan(1024 * 1024));
      });
    }
  });
}
