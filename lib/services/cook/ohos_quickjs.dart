import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// HarmonyOS 上的 QuickJS 上下文（自编 `libohos_quickjs.so`）。
///
/// cook 流程要求**持久上下文**：先 eval 整个 bundle 定义全局对象
/// （`__fluxdoCook` 等），之后每次渲染再调用这些全局。
class OhosQuickJs {
  OhosQuickJs._(this._handle);

  /// 新建一个独立 JS 上下文；原生库不可用时返回 null。
  static OhosQuickJs? create() {
    final lib = _load();
    if (lib == null) return null;
    final handle = lib.newContext();
    if (handle == nullptr) {
      debugPrint('[OhosQuickJs] 创建上下文失败');
      return null;
    }
    return OhosQuickJs._(handle);
  }

  final Pointer<Void> _handle;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// 执行 JS；成功返回结果字符串，失败返回错误描述。
  OhosJsResult evaluate(String code) {
    if (_disposed) {
      return const OhosJsResult(error: 'JS 上下文已释放');
    }
    final lib = _load();
    if (lib == null) {
      return const OhosJsResult(error: 'libohos_quickjs.so 不可用');
    }
    final codePtr = code.toNativeUtf8();
    final errPtr = malloc<Pointer<Utf8>>();
    errPtr.value = nullptr;
    try {
      final resultPtr = lib.eval(_handle, codePtr, errPtr);
      if (resultPtr == nullptr) {
        final err = errPtr.value == nullptr ? 'JS 执行失败' : errPtr.value.toDartString();
        return OhosJsResult(error: err);
      }
      final value = resultPtr.toDartString();
      lib.free(resultPtr.cast());
      return OhosJsResult(result: value);
    } finally {
      if (errPtr.value != nullptr) {
        lib.free(errPtr.value.cast());
      }
      malloc.free(errPtr);
      malloc.free(codePtr);
    }
  }

  /// 释放上下文（服务销毁/进程退出时调用）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _load()?.disposeContext(_handle);
  }

  // ---------------- 原生库加载（进程内单例） ----------------

  static _QuickJsBindings? _bindings;
  static bool _loadFailed = false;

  static _QuickJsBindings? _load() {
    if (_bindings != null) return _bindings;
    if (_loadFailed) return null;
    try {
      final lib = DynamicLibrary.open('libohos_quickjs.so');
      _bindings = _QuickJsBindings(lib);
      return _bindings;
    } catch (e) {
      _loadFailed = true;
      debugPrint('[OhosQuickJs] 原生库加载失败: $e');
      return null;
    }
  }

  /// QuickJS 版本号（不可用时返回 null）。
  static String? get version {
    final lib = _load();
    if (lib == null) return null;
    final ptr = lib.version();
    if (ptr == nullptr) return null;
    return ptr.toDartString();
  }

  /// 一次性 eval（内部临时建/销毁上下文），供启动探测使用。
  static OhosJsResult evaluateOnce(String code) {
    final js = create();
    if (js == null) return const OhosJsResult(error: 'libohos_quickjs.so 不可用');
    try {
      return js.evaluate(code);
    } finally {
      js.dispose();
    }
  }
}

class _QuickJsBindings {
  _QuickJsBindings(DynamicLibrary lib)
    : newContext = lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'ohos_js_new',
      ),
      eval = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
      >('ohos_js_eval'),
      disposeContext = lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('ohos_js_dispose'),
      free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'ohos_js_free',
      ),
      version = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'ohos_js_version',
      );

  final Pointer<Void> Function() newContext;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>) eval;
  final void Function(Pointer<Void>) disposeContext;
  final void Function(Pointer<Void>) free;
  final Pointer<Utf8> Function() version;
}

class OhosJsResult {
  const OhosJsResult({this.result, this.error});

  final String? result;
  final String? error;

  bool get isError => error != null;
}
