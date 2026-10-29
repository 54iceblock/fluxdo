import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:fluxdo_render/fluxdo_render.dart'
    show FlattenCache, ParagraphLayoutCache;

import 'discourse_cook_service.dart';
import '../widgets/content/animated_svg_view.dart';
import '../widgets/post/post_item/render_parse_cache.dart';
import '../widgets/topic/painted_topic_card.dart';
import '../widgets/topic/topic_card_layout.dart';

/// 应用自建缓存的统一释放入口。
///
/// 之前只有 `RenderParseCache` / `FlattenCache` 接了内存压力，话题卡的
/// 头像位图（≤400 张）、排版段落（≤500 条 × 约 10 个 Paragraph）、
/// 段落排版缓存、动画 SVG 首帧这些原生 / GPU 资源都不受管控，
/// 进后台后一直驻留。
///
/// 只释放可再生的缓存：在屏内容要么持有独立引用（clone / retain），要么
/// 在下一帧 miss 后重建，所以任何时机调用都不会画到已释放的资源。
class MemoryReclaimer {
  MemoryReclaimer._();

  /// 系统内存压力（iOS 内存警告 / Android onTrimMemory / 鸿蒙 onMemoryLevel，
  /// 以及鸿蒙 MODERATE / LOW 内存等级时由 EntryAbility 转发、进后台时由
  /// 引擎 GpuReclaim 发出）。
  ///
  /// ImageCache 由框架 `PaintingBinding.handleMemoryPressure` 自清，这里
  /// 只补应用自建缓存。
  static void onMemoryPressure() {
    final stats = _reclaimAppCaches();
    // cook 引擎只在内存压力时释放（进后台不释放：用户可能正在写回复，
    // 切出去查资料回来不想等重建）。在途调用期间 release 会自行跳过。
    DiscourseCookService().release(reason: '内存压力');
    debugPrint('[MemoryReclaimer] 内存压力: $stats');
  }

  /// 进后台。[clearImageCache] 为 false 时跳过 ImageCache（桌面端最小化
  /// 一次性销毁大量 GPU 贴图有崩溃风险，见 main.dart `_enterBackground`）。
  static void onEnterBackground({required bool clearImageCache}) {
    if (clearImageCache) {
      PaintingBinding.instance.imageCache.clear();
    }
    final stats = _reclaimAppCaches();
    debugPrint('[MemoryReclaimer] 进后台: $stats');
  }

  static String _reclaimAppCaches() {
    final cardImages = TopicCardImages.length;
    final cardLayouts = TopicCardLayout.cacheLength;
    RenderParseCache.clear();
    FlattenCache.evictAll();
    final paragraphs = ParagraphLayoutCache.evictIdle();
    TopicCardImages.evictAll();
    TopicCardLayout.trim();
    AnimatedSvgView.evictMemoryCache();
    return '话题卡位图 $cardImages、话题卡排版 $cardLayouts、'
        '离屏段落 $paragraphs';
  }
}
