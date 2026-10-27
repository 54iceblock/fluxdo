/// 按长边上限计算解码目标尺寸。
///
/// 与 `ohos/tools/ohos-avif-decode.c` 里 C 侧降采样的尺寸换算是同一规则（长边恰为
/// [maxDim]，短边按比例向下取整且至少为 1），两边改动必须同步。
///
/// 返回 `null` 表示不需要缩放。
(int, int)? fitLongEdge(int width, int height, int? maxDim) {
  if (maxDim == null || maxDim <= 0 || width <= 0 || height <= 0) return null;
  if (width <= maxDim && height <= maxDim) return null;
  if (width >= height) {
    final h = (height * maxDim) ~/ width;
    return (maxDim, h < 1 ? 1 : h);
  }
  final w = (width * maxDim) ~/ height;
  return (w < 1 ? 1 : w, maxDim);
}
