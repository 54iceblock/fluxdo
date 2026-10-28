import '../models/topic.dart';

/// 本地标签屏蔽名单的归一化与匹配。
///
/// 名单只由 [AppPreferences] 持久化在当前设备；这里绝不向 Discourse
/// 发出标签静音请求。标签名按 trim + lowercase 后精确匹配，不做子串或
/// 前缀匹配（名单里的 `ai` 不会命中 `ai-tools`）。
class BlockedTagFilter {
  BlockedTagFilter._();

  /// 标签输入框无需填写浏览时常见的 `#` 前缀。
  ///
  /// 兼容用户误输入 `#foo` 的情况，持久化和匹配均使用不带前缀的标签名。
  static String stripHashPrefix(String tag) {
    final trimmed = tag.trim();
    return trimmed.startsWith('#') ? trimmed.substring(1).trim() : trimmed;
  }

  static String normalizeTag(String tag) => stripHashPrefix(tag).toLowerCase();

  /// 去空、按大小写无关的标签名去重，同时保留第一条输入的显示形式。
  static List<String> sanitizeTags(Iterable<String> tags) {
    final seen = <String>{};
    final result = <String>[];
    for (final tag in tags) {
      final cleaned = stripHashPrefix(tag);
      final normalized = cleaned.toLowerCase();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(cleaned);
    }
    return result;
  }

  static Set<String> normalizedTags(Iterable<String> tags) {
    return Set.unmodifiable(
      tags.map(normalizeTag).where((tag) => tag.isNotEmpty),
    );
  }

  /// 话题任意一个标签命中名单即视为屏蔽。
  ///
  /// - [exemptTags] 为已归一化的豁免标签集合：浏览标签自身页面、或用户
  ///   显式选中该标签做筛选时，不应把结果全部隐藏。
  /// - 话题没有标签时永远不屏蔽：数据缺失时宁可保留。
  static bool isBlockedTopic(
    Topic topic,
    Set<String> blockedTags, {
    Set<String> exemptTags = const <String>{},
  }) {
    if (blockedTags.isEmpty || topic.tags.isEmpty) return false;
    for (final tag in topic.tags) {
      final name = normalizeTag(tag.name);
      if (name.isEmpty || exemptTags.contains(name)) continue;
      if (blockedTags.contains(name)) return true;
    }
    return false;
  }
}
