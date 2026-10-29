import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse_cook_service.dart';
import 'package:fluxdo/services/memory_reclaimer.dart';
import 'package:fluxdo/widgets/topic/painted_topic_card.dart';
import 'package:fluxdo/widgets/topic/topic_card_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('进后台：桌面端不清 ImageCache，移动端清空', () {
    final cache = PaintingBinding.instance.imageCache;
    final key = Object();
    cache.putIfAbsent(key, () => _NeverCompleter());
    expect(cache.containsKey(key), isTrue);

    MemoryReclaimer.onEnterBackground(clearImageCache: false);
    expect(cache.containsKey(key), isTrue);

    MemoryReclaimer.onEnterBackground(clearImageCache: true);
    expect(cache.containsKey(key), isFalse);
  });

  test('内存压力：自建缓存清空且可重复调用', () {
    MemoryReclaimer.onMemoryPressure();
    MemoryReclaimer.onMemoryPressure();
    expect(TopicCardImages.length, 0);
    expect(TopicCardLayout.cacheLength, 0);
    expect(DiscourseCookService().hasEngine, isFalse);
  });
}

class _NeverCompleter extends ImageStreamCompleter {}
