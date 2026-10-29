// 惰性帧序列在「无人观看」时释放已转换帧，滚回后能从首帧重新播放。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_animated_image/src/ffi/native_animated_image_ffi.dart';
import 'package:native_animated_image/src/native_animated_image_provider.dart';

DecodedAnimatedImage _gif({int frames = 4, int w = 2, int h = 2}) {
  return DecodedAnimatedImage(
    width: w,
    height: h,
    loopCount: 0,
    frames: [
      for (var i = 0; i < frames; i++)
        AnimatedFrame(
          rgba: Uint8List(w * h * 4)..fillRange(0, w * h * 4, i * 40),
          delay: const Duration(milliseconds: 50),
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trim 释放首帧以外的已转换帧，并保留源数据供重新转换', (tester) async {
    await tester.runAsync(() async {
      final seq = DebugLazyFrameSequence(_gif());

      final first = await seq.nextFrame();
      for (var i = 1; i < 4; i++) {
        await seq.nextFrame();
      }
      expect(seq.convertedCount, 4);
      // 首帧转换后丢源数据（永不 trim），其余帧保留以便重新转换
      expect(seq.retainedSourceCount, 3);

      seq.trim();
      expect(seq.convertedCount, 1, reason: '只保留首帧');
      expect(first.debugDisposed, isFalse, reason: '首帧不能被释放');

      // 恢复播放从首帧开始，且后续帧能重新转换出来
      final again = await seq.nextFrame();
      expect(identical(again, first), isTrue);
      final second = await seq.nextFrame();
      expect(second.debugDisposed, isFalse);
      expect(seq.convertedCount, 2);
    });
  });

  testWidgets('trim 不影响已交给 listener 的 clone', (tester) async {
    await tester.runAsync(() async {
      final seq = DebugLazyFrameSequence(_gif(frames: 3));
      await seq.nextFrame();
      final frame2 = await seq.nextFrame();
      final shown = frame2.clone(); // completer 的 setImage 交出去的是 clone

      seq.trim();
      expect(frame2.debugDisposed, isTrue, reason: '缓存自己的引用已释放');
      expect(shown.debugDisposed, isFalse, reason: '在屏的 clone 仍有效');
      expect(shown.width, 2);
      shown.dispose();
    });
  });

  testWidgets('单帧与重复 trim 安全', (tester) async {
    await tester.runAsync(() async {
      final seq = DebugLazyFrameSequence(_gif(frames: 1));
      final only = await seq.nextFrame();
      seq.trim();
      seq.trim();
      expect(seq.convertedCount, 1);
      expect(only.debugDisposed, isFalse);
    });
  });
}
