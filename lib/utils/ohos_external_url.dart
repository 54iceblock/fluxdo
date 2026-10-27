/// HarmonyOS 外部打开（ArkTS 桥 `openExternalUrl` → `startAbility`）的纯逻辑部分。
///
/// 单独成文件是为了能在宿主机单测：桥侧（FluxdoBridgePlugin.ets）做同样的白名单
/// 校验，Dart 侧先过一遍，可以在不进 MethodChannel 的情况下就拒绝危险 scheme，
/// 也让两端的规则有一份可测试的「真源」。两边改动必须同步。
abstract final class OhosExternalUrl {
  /// 允许交给系统打开的 scheme（与 ArkTS 桥一致）。
  static const Set<String> allowedSchemes = <String>{
    'http',
    'https',
    'mailto',
    'tel',
  };

  /// 是否允许经桥交给系统打开。
  ///
  /// 帖子正文、用户输入里的链接可能带任意 scheme（`file://`、`javascript:`、
  /// 其它应用的自定义 scheme）；直接 startAbility 等于让远端内容触发本机能力。
  static bool isAllowed(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    if (!allowedSchemes.contains(scheme)) return false;
    // http(s) 必须带 host，避免 `https:` 这类空壳。
    if ((scheme == 'http' || scheme == 'https') && uri.host.isEmpty) {
      return false;
    }
    return true;
  }
}
