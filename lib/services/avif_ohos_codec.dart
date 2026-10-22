import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// HarmonyOS 上的 AVIF 解码（自编 `libavif` + `dav1d`，随 HAP 打进 libs/`<abi>`/）。
///
/// 背景：flutter_avif 没有 OHOS 平台实现；系统 ImageKit 只能解析 AVIF 容器头、
/// 不能解码像素（已实测）。因此用 WSL 交叉编译 `tools/ohos-avif-decode.c` +
/// libavif + dav1d，导出 [decode] 需要的两个 C 函数。
class OhosAvifCodec {
  OhosAvifCodec._();

  static final OhosAvifCodec instance = OhosAvifCodec._();

  DynamicLibrary? _lib;
  bool _failed = false;

  /// 解码结果：宽、高、RGBA8888 像素。
  static const int _rgbaBytesPerPixel = 4;

  bool _ensureLoaded() {
    if (_lib != null) return true;
    if (_failed) return false;
    try {
      _lib = DynamicLibrary.open('libohos_avif.so');
      _decode = _lib!
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              IntPtr,
              Pointer<Pointer<Uint8>>,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Pointer<Utf8>>,
              Int32,
            ),
            int Function(
              Pointer<Uint8>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Pointer<Utf8>>,
              int,
            )
          >('ohos_avif_decode');
      _free = _lib!.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'ohos_avif_free',
      );
      return true;
    } catch (e) {
      _failed = true;
      debugPrint('[OhosAvif] 原生库加载失败: $e');
      return false;
    }
  }

  late final int Function(
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Pointer<Utf8>>,
    int,
  )
  _decode;
  late final void Function(Pointer<Void>) _free;

  /// 解码 AVIF 字节流。失败返回 null（错误原因会 debugPrint）。
  OhosAvifResult? decode(Uint8List bytes, {int? maxDim}) {
    if (!_ensureLoaded()) return null;
    if (bytes.isEmpty) return null;

    final dataPtr = malloc<Uint8>(bytes.length);
    final outPixels = malloc<Pointer<Uint8>>();
    final outW = malloc<Int32>();
    final outH = malloc<Int32>();
    final outErr = malloc<Pointer<Utf8>>();
    outPixels.value = nullptr;
    outErr.value = nullptr;
    outW.value = 0;
    outH.value = 0;
    try {
      dataPtr.asTypedList(bytes.length).setAll(0, bytes);
      final rc = _decode(
        dataPtr,
        bytes.length,
        outPixels,
        outW,
        outH,
        outErr,
        maxDim ?? 0,
      );
      if (rc != 0) {
        final err = outErr.value == nullptr ? 'unknown' : outErr.value.toDartString();
        if (outErr.value != nullptr) _free(outErr.value.cast());
        debugPrint('[OhosAvif] 解码失败(rc=$rc): $err');
        return null;
      }
      final w = outW.value;
      final h = outH.value;
      final pixels = outPixels.value;
      if (w <= 0 || h <= 0 || pixels == nullptr) {
        debugPrint('[OhosAvif] 解码结果异常: w=$w h=$h ptr=$pixels');
        return null;
      }
      final count = w * h * _rgbaBytesPerPixel;
      final rgba = Uint8List.fromList(pixels.asTypedList(count));
      _free(pixels.cast());
      return OhosAvifResult(width: w, height: h, rgba: rgba);
    } finally {
      malloc.free(dataPtr);
      malloc.free(outPixels);
      malloc.free(outW);
      malloc.free(outH);
      malloc.free(outErr);
    }
  }

  /// 仅用于日志：原生库是否可用。
  bool get isAvailable => _ensureLoaded();
}

class OhosAvifResult {
  const OhosAvifResult({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;

  /// RGBA8888，长度 = width * height * 4。
  final Uint8List rgba;
}
