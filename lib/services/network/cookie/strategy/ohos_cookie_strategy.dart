import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../constants.dart';
import 'default_cookie_strategy.dart';

/// HarmonyOS / OpenHarmony cookie 策略。
///
/// 与 Android 的差异（依据 flutter_inappwebview_ohos 1.1.3 源码：
/// `ohos/src/main/ets/components/plugin/MyCookieManager.ets`）：
///
/// 1. `getCookies(url:)` 的实现是 `WebCookieManager.fetchCookieSync(url)` 后
///    按 `;` 拆 `name=value`。**返回的 Cookie 对象 domain/path/secure/
///    httpOnly/expiresDate/sameSite 全部为 null** —— ArkWeb 该 API 只暴露
///    Cookie 头字符串，不暴露属性。属性补全交给
///    `BoundarySyncService` 既有的兜底逻辑（domain 继承/回退 `.{host}`、
///    path 回退 `/`）。
/// 2. OHOS 没有 `RawCookieWriter` 原生通道（`com.fluxdo/raw_cookie` 未实现），
///    也没有 `CookieManager.getAllCookies()`（platform interface 默认抛
///    UnimplementedError），所以**读只能走插件通道**，而且必须按 URL 读。
///
/// 读增强：`fetchCookieSync(url)` 按 URL 过滤 cookie。CF 验证页把
/// `currentUrl` 传成 `https://linux.do/challenge`，而 `cf_clearance` 是
/// Path=/ 的根路径 cookie。若 ArkWeb 某些版本对「带 path 的 URL」过滤过严，
/// 深层 URL 就读不到根路径 cookie，表现为「验证通过但 jar 里没有
/// cf_clearance」。这里额外用站点根 URL 再读一次并合并（仅同 host），
/// 把这条 URL 过滤差异兜住。
class OhosCookieStrategy extends DefaultCookieStrategy {
  OhosCookieStrategy({String? rootUrl})
    : rootUrl = rootUrl ?? AppConstants.baseUrl;

  /// 站点根 URL，用于补充读取 Path=/ 的根路径 cookie。
  final String rootUrl;

  @override
  Future<List<Cookie>> readCookiesFromWebView(
    CookieManager cookieManager,
    String url,
  ) async {
    final merged = <String, Cookie>{};

    void addAll(List<Cookie> cookies) {
      for (final cookie in cookies) {
        if (cookie.name.isEmpty) continue;
        // 同名同值只留一份；OHOS 没有 domain/path，key 里带上避免误合并。
        final key =
            '${cookie.name}|${cookie.domain ?? ''}|${cookie.path ?? ''}|'
            '${cookie.value ?? ''}';
        merged.putIfAbsent(key, () => cookie);
      }
    }

    var primaryCount = 0;
    try {
      final primary = await cookieManager.getCookies(url: WebUri(url));
      primaryCount = primary.length;
      addAll(primary);
    } catch (e) {
      debugPrint('[CookieStrategy][OHOS] getCookies($url) 失败: $e');
    }

    // 深层 URL 读不到时补读站点根 URL：cf_clearance 是 Path=/ 的根 cookie。
    final current = Uri.tryParse(url);
    final root = Uri.tryParse(rootUrl);
    final shouldReadRoot =
        root != null &&
        current != null &&
        current.host == root.host &&
        (current.path != root.path || current.query.isNotEmpty);
    if (shouldReadRoot) {
      try {
        final rootCookies = await cookieManager.getCookies(
          url: WebUri(rootUrl),
        );
        addAll(rootCookies);
      } catch (e) {
        debugPrint('[CookieStrategy][OHOS] getCookies($rootUrl) 失败: $e');
      }
    }

    final result = merged.values.toList(growable: false);
    if (kDebugMode) {
      // 排查 CF 403 的关键日志：ArkWeb 侧到底有没有 cf_clearance。
      // 缺 cf_clearance 时这行能区分「ArkWeb 没有该 cookie」与「读到了但没写进 jar」。
      // 每次 cookie 同步都会打，release 里没有必要，只在 debug 输出。
      final names = result.map((cookie) => cookie.name).toSet();
      debugPrint(
        '[CookieStrategy][OHOS] read url=$url primary=$primaryCount '
        'merged=${result.length} names=${names.length} '
        'hasCfClearance=${names.contains('cf_clearance')}',
      );
    }
    return result;
  }
}
