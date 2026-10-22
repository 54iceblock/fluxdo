import 'dart:io';

import 'platform_utils.dart';

/// 鸿蒙（HarmonyOS / OpenHarmony）能力开关。
///
/// 移植背景：OHOS 平台没有官方的 DOH 代理、rhttp（Rust）、QuickJS（flutter_js）、
/// AVIF（flutter_avif）、super_clipboard 等原生实现。这些能力在 lib/ 里被无条件
/// 使用，直接调用会在运行时抛 MissingPluginException / UnsupportedError。
///
/// 这里集中声明「OHOS 上是否真的可用」，调用点统一走这里的开关，
/// 既保证 OHOS 不崩溃，也不影响 Android/iOS/桌面端的既有行为。
class OhosCompat {
  OhosCompat._();

  static bool get isOhos => PlatformUtils.isOhos;

  /// 是否支持 Rust DOH 代理（core/doh_proxy）
  /// OHOS：已交叉编译 libdoh_proxy.so（x86_64 / arm64-v8a）并打进 HAP 的 libs/<abi>/，
  /// 运行时由 `DynamicLibrary.open('libdoh_proxy.so')` 加载（见 doh_proxy_ffi.dart）。
  static bool get supportsDohProxy => true;

  /// 是否支持 rhttp（Rust reqwest / TLS 指纹）
  /// OHOS：暂无 FRB 平台加载器，强制关闭，回退 dio 默认适配器。
  static bool get supportsRhttp => !isOhos;

  /// 是否支持 flutter_js（Discourse markdown-it cook 渲染）
  /// OHOS：暂无 QuickJS 原生库，回退纯 Dart 渲染预览。
  static bool get supportsCookJs => !isOhos;

  /// 是否支持 native_animated_image（Rust 动图解码）
  /// OHOS：暂无原生库，回退 Flutter 内置 ImageProvider。
  static bool get supportsNativeAnimatedImage => !isOhos;

  /// 是否支持 flutter_avif（libavif/dav1d）
  /// OHOS：暂无原生库，AVIF 走平台 ImageKit 或占位。
  static bool get supportsAvif => !isOhos;

  /// 是否支持 super_clipboard（富文本剪贴板）
  /// OHOS：暂无实现，回退纯文本剪贴板。
  static bool get supportsRichClipboard => !isOhos;

  /// 是否支持桌面窗口管理（window_manager / screen_retriever / acrylic）
  static bool get supportsDesktopWindow => PlatformUtils.isDesktop;

  /// 是否支持相机扫码（mobile_scanner）
  /// OHOS：使用 CPF fork 的 OHOS 实现；相机不可用时页面内提供相册 + zxing2 兜底。
  static bool get supportsCameraScanner =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS || isOhos;

  /// 是否支持系统相册保存（gal）
  /// OHOS：走系统 Picker/SaveButton，暂用文件导出兜底。
  static bool get supportsSaveToGallery => !isOhos;

  /// 是否支持本地通知插件（flutter_local_notifications）
  /// OHOS：官方 fork 提供实现，若未注册则初始化会被 try/catch 兜住。
  static bool get supportsLocalNotifications => true;

  /// 是否支持后台保活（flutter_foreground_task / workmanager）
  /// OHOS：首版仅前台轮询，不启用后台保活。
  static bool get supportsBackgroundTasks => !isOhos;

  /// 是否支持应用内更新安装（ota_update / APK 安装）
  /// OHOS：三方应用不能静默安装 HAP，改为引导跳转应用市场。
  static bool get supportsInAppUpdate => !isOhos;
}
