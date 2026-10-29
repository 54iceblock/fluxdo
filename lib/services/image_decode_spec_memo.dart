import 'package:flutter/widgets.dart';

import 'discourse_cache_manager.dart';

/// 按帖内登记的解码参数重建 provider，同步命中帖内那份已解码位图。
///
/// 长按预览、查看器缩略图占位等「再画一次帖内同一张图」的场景用它：
/// 裸 `discourseImageProvider(url)` 是另一个缓存 key，会按原尺寸再解码
/// 一份（optimized 图常见 4–16 MB）。未登记时退回裸 provider。
ImageProvider resizedLikeInPost(String url) {
  final spec = ImageDecodeSpecMemo.peek(url);
  final provider = discourseImageProvider(url);
  if (spec == null) return provider;
  return ResizeImage(
    provider,
    width: spec.$1,
    height: spec.$2,
    policy: ResizeImagePolicy.fit,
  );
}

/// url → 帖内解码参数(decode-time ResizeImage 的宽高 cap)的会话级备忘。
///
/// 查看器打开时的缩略图占位必须与帖内用**完全相同的 provider 参数**:
/// ImageCache 的 key 是 ResizeImageKey(内层 provider key + 宽高 + 策略),
/// 参数差一点就是 cache miss —— Hero 转场帧白付一次全量解码(帖内那份
/// 明明还在屏、活在缓存里)。帖内路径(LazyImage / 网格瓦片 / 轮播)
/// 构建 provider 时登记,查看器按登记参数原样重建即可同步命中。
///
/// 纯内存、会话级:查看器只可能从"帖内那张图还在屏"的状态进入,
/// 不需要跨会话持久化。
class ImageDecodeSpecMemo {
  ImageDecodeSpecMemo._();

  static final Map<String, (int, int)> _mem = {};
  static const int _cap = 512;

  static void remember(String url, int width, int height) {
    if (url.isEmpty || width <= 0 || height <= 0) return;
    _mem.remove(url);
    _mem[url] = (width, height);
    while (_mem.length > _cap) {
      _mem.remove(_mem.keys.first);
    }
  }

  /// (width, height);未登记返回 null。
  static (int, int)? peek(String url) {
    final v = _mem.remove(url);
    if (v != null) _mem[url] = v; // LRU 触摸
    return v;
  }
}
