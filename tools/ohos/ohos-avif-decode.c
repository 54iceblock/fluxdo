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
  decoder->imageSizeLimit = 16384 * 16384;
  decoder->imageDimensionLimit = 16384;

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
  const size_t bytes = (size_t)w * (size_t)h * 4u;
  uint8_t* out = (uint8_t*)malloc(bytes);
  if (out == NULL) {
    avifRGBImageFreePixels(&rgb);
    avifDecoderDestroy(decoder);
    return fail(out_err, "out of memory");
  }
  memcpy(out, rgb.pixels, bytes);
  if (max_dim > 0) {
    // 记录原始尺寸；缩放交给 Flutter 侧（ImageDescriptor.raw 之后由引擎缩放）
    (void)max_dim;
  }
  avifRGBImageFreePixels(&rgb);
  avifDecoderDestroy(decoder);

  *out_rgba = out;
  *out_w = w;
  *out_h = h;
  return 0;
}

void ohos_avif_free(void* p) {
  if (p != NULL) free(p);
}
