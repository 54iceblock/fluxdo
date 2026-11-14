/*
 * FluxDO 新增：JavaScriptProxy 调用方 frame URL 与主文档 URL 的比较规则（纯函数，无任何 ArkWeb 依赖）。
 *
 * 真机实测（HarmonyOS 7 / API 26，HBN-AL00）：
 *   主文档 http://127.0.0.1:8080/apps/<uuid>?embed_mode=true 的主框架调用，
 *   getLastJavascriptProxyCallingFrameUrl() 返回 http://127.0.0.1:8080/apps/
 *   —— 即截断到「最后一个 / 为止」的目录形式（query / fragment / 文件名都被丢弃）。
 *   官方文档只写「获取调用 JavaScriptProxy 最后一帧的 url」，未保证完整 URL，行为随 ROM 可能变化，
 *   因此这里同时接受「完整 URL」与「目录形式」两种表示，且都是 fail-closed：
 *
 *   1. frame 去掉 fragment 后与主文档去掉 fragment 完全相等 → 主框架；
 *   2. frame（去掉 query / fragment 后）以 '/' 结尾（目录形式），且等于主文档的目录形式 → 主框架；
 *   3. 其余一律非主框架。
 *
 * 已知风险（必须保留）：规则 2 下，与主文档同 origin、同目录的 iframe（例如主文档 /apps/a，
 * iframe /apps/b）的调用方 URL 同样是 /apps/，无法与主框架区分，会被误判为主框架。
 * 不同目录（/mock/x）或跨 origin 的 iframe 仍能区分。后续 Dart 侧还会再校验 origin，
 * 并由宿主 token / viewEpoch 兜底。
 */

export default class FrameUrlMatcher {
  /** 去掉 fragment。 */
  static stripFragment(url: string): string {
    const idx: number = url.indexOf('#');
    return idx >= 0 ? url.substring(0, idx) : url;
  }

  /** 去掉 query 与 fragment。 */
  static stripQueryAndFragment(url: string): string {
    let s: string = FrameUrlMatcher.stripFragment(url);
    const q: number = s.indexOf('?');
    if (q >= 0) {
      s = s.substring(0, q);
    }
    return s;
  }

  /**
   * 目录形式：scheme://authority + path 截到最后一个 '/'（含）。
   * 无 path（如 http://host:8080）返回 scheme://authority/。无法识别 scheme://authority 返回 null。
   */
  static directoryForm(url: string): string | null {
    const s: string = FrameUrlMatcher.stripQueryAndFragment(url);
    const schemeEnd: number = s.indexOf('://');
    if (schemeEnd <= 0) {
      return null;
    }
    const pathStart: number = s.indexOf('/', schemeEnd + 3);
    if (pathStart < 0) {
      return s + '/';
    }
    const last: number = s.lastIndexOf('/');
    return s.substring(0, last + 1);
  }

  /**
   * frame URL 是否对应主文档 URL。任一为空返回 false（fail-closed）。
   */
  static isSameDocumentOrDirectoryForm(frameUrl: string | null, mainUrl: string | null): boolean {
    if (frameUrl == null || mainUrl == null || frameUrl.length === 0 || mainUrl.length === 0) {
      return false;
    }
    if (FrameUrlMatcher.stripFragment(frameUrl) === FrameUrlMatcher.stripFragment(mainUrl)) {
      return true;
    }
    const frameNoQuery: string = FrameUrlMatcher.stripQueryAndFragment(frameUrl);
    if (!frameNoQuery.endsWith('/')) {
      return false;
    }
    const mainDir: string | null = FrameUrlMatcher.directoryForm(mainUrl);
    return mainDir != null && mainDir === frameNoQuery;
  }
}
