import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// HarmonyOS 上的 AVIF 解码（自编 `libavif` + `dav1d`，随 HAP 打进 libs/`<abi>`/）。
///
/// 背景：flutter_avif 没有 OHOS 平台实现；系统 ImageKit 只能解析 AVIF 容器头、
/// 不能解码像素（已实测）。因此用 WSL 交叉编译 `tools/ohos-avif-decode.c` +
/// libavif + dav1d，导出本类需要的两个 C 函数。
///
/// 线程模型（审核修复点）：AVIF 解码是纯 CPU 的百毫秒级工作——大图整幅 RGBA
/// 转换 + 拷贝。早期实现在主 isolate 里同步调 FFI，后果是：
///   1) 首次滚动到 AVIF 图片时掉帧、卡住手势（解码期间 UI 线程被占用）；
///   2) 连续解多张图（首屏/缓存回填）时主线程长时间不可用。
/// 现在统一走**常驻后台 isolate**：解码与像素拷贝都在 worker 里完成，像素用
/// [TransferableTypedData] 零拷贝搬回主 isolate。worker 只启动一次，不像
/// `Isolate.run` 每次新建，避免重复 dlopen 与 isolate 启动开销。
///
/// 降采样（审核修复点）：`maxDim` 之前只在 Dart 侧传参、C 侧直接忽略，等于每个
/// 缩略图都按原图解出全尺寸 RGBA 再缩放。现在 C 侧在转 RGBA 后做盒式降采样，
/// 内存与耗时随目标尺寸下降（**需重新编译 libohos_avif.so**，脚本见
/// tools/build-avif-ohos.sh；未重编时行为与旧库一致，仍能正常解码）。
class OhosAvifCodec {
  OhosAvifCodec._();

  static final OhosAvifCodec instance = OhosAvifCodec._();

  /// RGBA8888，每像素 4 字节。
  static const int bytesPerPixel = 4;

  /// 原生库是否可用（只判断能否 dlopen，不解码）。
  bool get isAvailable => _NativeAvif.isAvailable;

  /// 解码 AVIF 字节流。失败返回 null（原因见 debugPrint）。
  ///
  /// [maxDim] 为目标长边上限（逻辑像素）；传 0/null 表示保持原尺寸。
  Future<OhosAvifResult?> decode(Uint8List bytes, {int? maxDim}) async {
    if (bytes.isEmpty) return null;
    final SendPort? worker = await _AvifWorker.instance.port();
    if (worker == null) {
      // 后台 isolate 起不来时退化为同步解码：宁可掉一次帧，也别让解码链断掉。
      debugPrint('[OhosAvif] 后台 isolate 不可用，退化为同步解码');
      return decodeSync(bytes, maxDim: maxDim);
    }
    return _AvifWorker.instance.decode(worker, bytes, maxDim: maxDim);
  }

  /// 同步解码（仅 debug 探针/极小图使用，主线程调用会阻塞）。
  OhosAvifResult? decodeSync(Uint8List bytes, {int? maxDim}) {
    if (bytes.isEmpty) return null;
    return _NativeAvif.instance?.decodeBytes(bytes, maxDim: maxDim)?.toResult();
  }

  /// 一次性探测（debug 探针用），返回便于写日志的一行结果。
  String probe(Uint8List bytes, {int? maxDim}) {
    final OhosAvifResult? result = decodeSync(bytes, maxDim: maxDim);
    if (result == null) {
      return 'native-null available=$isAvailable';
    }
    return 'native-ok w=${result.width} h=${result.height} '
        'rgba=${result.rgba.length}';
  }
}

/// 常驻解码 worker（懒启动，进程内单例）。
class _AvifWorker {
  _AvifWorker._();

  static final _AvifWorker instance = _AvifWorker._();

  Future<SendPort?>? _portFuture;
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  ReceivePort? _errorPort;
  StreamSubscription<dynamic>? _errorSubscription;

  final Map<int, Completer<OhosAvifResult?>> _pending =
      <int, Completer<OhosAvifResult?>>{};
  int _nextId = 1;

  /// 拿到 worker 的 SendPort；不可用时返回 null（只尝试一次）。
  Future<SendPort?> port() => _portFuture ??= _start();

  Future<SendPort?> _start() async {
    final ReceivePort receivePort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final Completer<SendPort> ready = Completer<SendPort>();
    _receivePort = receivePort;
    _errorPort = errorPort;
    _subscription = receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      _handleMessage(message);
    });
    // Isolate.spawn 的错误回调只能是 SendPort：worker 未捕获异常会以
    // [error, stackTrace] 的形式送到这个端口。
    _errorSubscription = errorPort.listen((dynamic message) {
      final Object detail = message is List && message.isNotEmpty
          ? message.first as Object
          : message as Object;
      debugPrint('[OhosAvif] worker 异常: $detail');
      _teardown();
    });
    try {
      _isolate = await Isolate.spawn(
        _avifWorkerEntry,
        receivePort.sendPort,
        debugName: 'ohos-avif-decode',
        onError: errorPort.sendPort,
      );
      _sendPort = await ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('AVIF worker 启动超时'),
      );
      return _sendPort;
    } catch (e) {
      debugPrint('[OhosAvif] 后台 isolate 启动失败: $e');
      _teardown();
      return null;
    }
  }

  Future<OhosAvifResult?> decode(
    SendPort worker,
    Uint8List bytes, {
    int? maxDim,
  }) {
    final int id = _nextId++;
    final Completer<OhosAvifResult?> completer = Completer<OhosAvifResult?>();
    _pending[id] = completer;
    worker.send(<Object?>[id, bytes, maxDim ?? 0]);
    // 单张解码超时保护：原生库卡死时不能让上层 Future 永久挂起。
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        debugPrint('[OhosAvif] 解码超时(30s)，放弃本次解码');
        return null;
      },
    );
  }

  void _handleMessage(dynamic message) {
    if (message is! List<dynamic> || message.length < 5) return;
    final int id = message[0] as int;
    final int width = message[1] as int;
    final int height = message[2] as int;
    final TransferableTypedData? data = message[3] as TransferableTypedData?;
    final String? error = message[4] as String?;

    final Completer<OhosAvifResult?>? completer = _pending.remove(id);
    if (completer == null) return;
    if (error != null) {
      debugPrint('[OhosAvif] 解码失败: $error');
      completer.complete(null);
      return;
    }
    if (data == null || width <= 0 || height <= 0) {
      completer.complete(null);
      return;
    }
    completer.complete(
      OhosAvifResult(
        width: width,
        height: height,
        rgba: data.materialize().asUint8List(),
      ),
    );
  }

  void _teardown() {
    // 结束残留 worker（错误路径进入时才调用，正常解码不受影响）。
    _isolate?.kill(priority: Isolate.immediate);
    _sendPort = null;
    _isolate = null;
    _portFuture = null; // 允许下次解码重新拉起
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
    _errorPort?.close();
    _errorPort = null;
    for (final Completer<OhosAvifResult?> completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }
}

/// worker 入口（顶层函数，供 Isolate.spawn 使用）。
void _avifWorkerEntry(SendPort toMain) {
  final ReceivePort port = ReceivePort();
  toMain.send(port.sendPort);

  port.listen((dynamic message) {
    if (message is! List<dynamic> || message.length < 3) return;
    final int id = message[0] as int;
    final Uint8List bytes = message[1] as Uint8List;
    final int maxDim = message[2] as int;

    final _NativeAvif? native = _NativeAvif.instance;
    if (native == null) {
      toMain.send(<Object?>[id, 0, 0, null, 'libohos_avif.so 不可用']);
      return;
    }
    try {
      final _RawDecodeResult? result = native.decodeBytes(
        bytes,
        maxDim: maxDim > 0 ? maxDim : null,
      );
      if (result == null) {
        toMain.send(<Object?>[id, 0, 0, null, native.lastError]);
        return;
      }
      toMain.send(<Object?>[
        id,
        result.width,
        result.height,
        TransferableTypedData.fromList(<Uint8List>[result.rgba]),
        null,
      ]);
    } catch (e) {
      toMain.send(<Object?>[id, 0, 0, null, '$e']);
    }
  });
}

/// 原生库绑定（每个 isolate 各有一份：Dart 的 static 是 isolate 私有的）。
class _NativeAvif {
  _NativeAvif._(DynamicLibrary lib)
    : _decode = lib.lookupFunction<
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
      >('ohos_avif_decode'),
      _free = lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('ohos_avif_free');

  final int Function(
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Pointer<Utf8>>,
    int,
  )
  _decode;
  final void Function(Pointer<Void>) _free;

  static _NativeAvif? _cached;
  static bool _loadFailed = false;

  /// 最近一次失败原因（供日志/回传）。
  String lastError = '未知错误';

  static bool get isAvailable => instance != null;

  static _NativeAvif? get instance {
    if (_cached != null) return _cached;
    if (_loadFailed) return null;
    try {
      _cached = _NativeAvif._(DynamicLibrary.open('libohos_avif.so'));
      return _cached;
    } catch (e) {
      _loadFailed = true;
      debugPrint('[OhosAvif] 原生库加载失败: $e');
      return null;
    }
  }

  /// 解码并返回**紧凑排列**的 RGBA（行跨距 = width * 4）。
  _RawDecodeResult? decodeBytes(Uint8List bytes, {int? maxDim}) {
    final Pointer<Uint8> dataPtr = malloc<Uint8>(bytes.length);
    final Pointer<Pointer<Uint8>> outPixels = malloc<Pointer<Uint8>>();
    final Pointer<Int32> outW = malloc<Int32>();
    final Pointer<Int32> outH = malloc<Int32>();
    final Pointer<Pointer<Utf8>> outErr = malloc<Pointer<Utf8>>();
    outPixels.value = nullptr;
    outErr.value = nullptr;
    outW.value = 0;
    outH.value = 0;
    try {
      dataPtr.asTypedList(bytes.length).setAll(0, bytes);
      final int rc = _decode(
        dataPtr,
        bytes.length,
        outPixels,
        outW,
        outH,
        outErr,
        maxDim ?? 0,
      );
      if (rc != 0) {
        final String message = outErr.value == nullptr
            ? 'unknown'
            : outErr.value.toDartString();
        if (outErr.value != nullptr) _free(outErr.value.cast());
        lastError = '$message (rc=$rc)';
        return null;
      }
      final int w = outW.value;
      final int h = outH.value;
      final Pointer<Uint8> pixels = outPixels.value;
      if (w <= 0 || h <= 0 || pixels == nullptr) {
        lastError = '解码结果异常: w=$w h=$h ptr=$pixels';
        return null;
      }
      final int count = w * h * OhosAvifCodec.bytesPerPixel;
      final Uint8List rgba = Uint8List.fromList(pixels.asTypedList(count));
      _free(pixels.cast());
      lastError = '';
      return _RawDecodeResult(width: w, height: h, rgba: rgba);
    } finally {
      malloc.free(dataPtr);
      malloc.free(outPixels);
      malloc.free(outW);
      malloc.free(outH);
      malloc.free(outErr);
    }
  }
}

class _RawDecodeResult {
  const _RawDecodeResult({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  OhosAvifResult toResult() =>
      OhosAvifResult(width: width, height: height, rgba: rgba);
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
