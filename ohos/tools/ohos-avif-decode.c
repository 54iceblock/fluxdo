/**
 * HarmonyOS AVIF 解码包装（libavif + dav1d 静态链接进本 .so）
 *
 * 导出：
 *   int  ohos_avif_decode(const uint8_t* data, size_t size,
 *                         uint8_t** out_rgba, int* out_w, int* out_h,
 *                         char** out_err, int max_dim);
 *   void ohos_avif_free(void* p);
 *
 * 返回 0 成功；非 0 失败（out_err 为可读原因，需用 ohos_avif_free 释放）。
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <avif/avif.h>

static char* dup_cstr(const char* s) {
  if (s == NULL) return NULL;
  size_t n = strlen(s) + 1;
  char* p = (char*)malloc(n);
  if (p != NULL) memcpy(p, s, n);
  return p;
}

static int fail(char** out_err, const char* msg) {
  if (out_err != NULL) {
    *out_err = dup_cstr(msg);
  }
  return -1;
}

/* RGBA8888 盒式降采样（近似面积平均）。
 *
 * 为什么在 C 侧做：Dart 传入的 max_dim 之前被直接忽略，等于每张缩略图都
 * 按原图解出全尺寸 RGBA 再交给引擎缩放 —— 大图既慢又吃内存。
 * 用盒式而不是双线性：缩略图场景下质量足够，实现简单、无浮点。
 *
 * 调用方负责 free 返回值；失败返回 NULL。
 */
static uint8_t* downscale_rgba_box(const uint8_t* src, int sw, int sh, int dw,
                                   int dh) {
  if (src == NULL || sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return NULL;
  if (dw > sw || dh > sh) return NULL;

  const size_t out_bytes = (size_t)dw * (size_t)dh * 4u;
  uint8_t* out = (uint8_t*)malloc(out_bytes);
  if (out == NULL) return NULL;

  for (int y = 0; y < dh; y++) {
    /* 目标像素对应的源区间 [y0, y1) */
    const int y0 = (int)(((int64_t)y * sh) / dh);
    int y1 = (int)(((int64_t)(y + 1) * sh) / dh);
    if (y1 <= y0) y1 = y0 + 1;
    if (y1 > sh) y1 = sh;

    for (int x = 0; x < dw; x++) {
      const int x0 = (int)(((int64_t)x * sw) / dw);
      int x1 = (int)(((int64_t)(x + 1) * sw) / dw);
      if (x1 <= x0) x1 = x0 + 1;
      if (x1 > sw) x1 = sw;

      uint32_t r = 0, g = 0, b = 0, a = 0, n = 0;
      for (int sy = y0; sy < y1; sy++) {
        const uint8_t* row = src + ((size_t)sy * (size_t)sw + (size_t)x0) * 4u;
        for (int sx = x0; sx < x1; sx++, row += 4) {
          r += row[0];
          g += row[1];
          b += row[2];
          a += row[3];
          n++;
        }
      }
      uint8_t* dst = out + ((size_t)y * (size_t)dw + (size_t)x) * 4u;
      if (n == 0) {
        dst[0] = dst[1] = dst[2] = dst[3] = 0;
      } else {
        dst[0] = (uint8_t)(r / n);
        dst[1] = (uint8_t)(g / n);
        dst[2] = (uint8_t)(b / n);
        dst[3] = (uint8_t)(a / n);
      }
    }
  }
  return out;
}

int ohos_avif_decode(const uint8_t* data, size_t size, uint8_t** out_rgba,
                     int* out_w, int* out_h, char** out_err, int max_dim) {
  if (data == NULL || size == 0) return fail(out_err, "empty input");
  if (out_rgba == NULL || out_w == NULL || out_h == NULL)
    return fail(out_err, "bad out args");

  *out_rgba = NULL;
  *out_w = 0;
  *out_h = 0;
  if (out_err != NULL) *out_err = NULL;

  avifDecoder* decoder = avifDecoderCreate();
  if (decoder == NULL) return fail(out_err, "avifDecoderCreate failed");
  decoder->maxThreads = 2;
  /* 上限从 16384 收到 8192：8192*8192 已远超移动端合理图片尺寸，而
   * 16384*16384 的 RGBA 需要 ~1GB，一个畸形文件就够 OOM。 */
  decoder->imageSizeLimit = 8192 * 8192;
  decoder->imageDimensionLimit = 8192;

  avifResult res = avifDecoderSetIOMemory(decoder, data, size);
  if (res != AVIF_RESULT_OK) {
    char buf[256];
    snprintf(buf, sizeof(buf), "SetIOMemory: %s", avifResultToString(res));
    avifDecoderDestroy(decoder);
    return fail(out_err, buf);
  }
  res = avifDecoderParse(decoder);
  if (res != AVIF_RESULT_OK) {
    char buf[256];
    snprintf(buf, sizeof(buf), "Parse: %s", avifResultToString(res));
    avifDecoderDestroy(decoder);
    return fail(out_err, buf);
  }
  res = avifDecoderNextImage(decoder);
  if (res != AVIF_RESULT_OK) {
    char buf[256];
    snprintf(buf, sizeof(buf), "NextImage: %s", avifResultToString(res));
    avifDecoderDestroy(decoder);
    return fail(out_err, buf);
  }

  avifImage* image = decoder->image;
  // 统一转成 8bit RGBA
  avifRGBImage rgb;
  avifRGBImageSetDefaults(&rgb, image);
  rgb.format = AVIF_RGB_FORMAT_RGBA;
  rgb.depth = 8;
  rgb.ignoreAlpha = 0;
  rgb.alphaPremultiplied = 0;
  res = avifRGBImageAllocatePixels(&rgb);
  if (res != AVIF_RESULT_OK) {
    char buf[256];
    snprintf(buf, sizeof(buf), "AllocatePixels: %s", avifResultToString(res));
    avifDecoderDestroy(decoder);
    return fail(out_err, buf);
  }
  res = avifImageYUVToRGB(image, &rgb);
  if (res != AVIF_RESULT_OK) {
    char buf[256];
    snprintf(buf, sizeof(buf), "YUVToRGB: %s", avifResultToString(res));
    avifRGBImageFreePixels(&rgb);
    avifDecoderDestroy(decoder);
    return fail(out_err, buf);
  }

  const int w = (int)rgb.width;
  const int h = (int)rgb.height;

  /* max_dim > 0 且长边超限时，在 C 侧降采样后再交给 Dart，避免整幅大图
   * 穿过 FFI 边界、也避免引擎侧再做一次全尺寸缩放。 */
  int out_width = w;
  int out_height = h;
  if (max_dim > 0 && (w > max_dim || h > max_dim)) {
    if (w >= h) {
      out_width = max_dim;
      out_height = (int)(((int64_t)h * max_dim) / w);
    } else {
      out_height = max_dim;
      out_width = (int)(((int64_t)w * max_dim) / h);
    }
    if (out_width < 1) out_width = 1;
    if (out_height < 1) out_height = 1;
  }

  uint8_t* out = NULL;
  if (out_width == w && out_height == h) {
    const size_t bytes = (size_t)w * (size_t)h * 4u;
    out = (uint8_t*)malloc(bytes);
    if (out != NULL) memcpy(out, rgb.pixels, bytes);
  } else {
    out = downscale_rgba_box(rgb.pixels, w, h, out_width, out_height);
  }
  avifRGBImageFreePixels(&rgb);
  avifDecoderDestroy(decoder);
  if (out == NULL) return fail(out_err, "out of memory");

  *out_rgba = out;
  *out_w = out_width;
  *out_h = out_height;
  return 0;
}

void ohos_avif_free(void* p) {
  if (p != NULL) free(p);
}
