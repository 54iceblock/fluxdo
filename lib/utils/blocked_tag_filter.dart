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
    return isBlockedTagNames(
      topic.tags.map((tag) => tag.name),
      blockedTags,
      exemptTags: exemptTags,
    );
  }

  /// 与 [isBlockedTopic] 同一口径，但直接接收标签名。
  ///
  /// 供不经过 [Topic] 模型的来源使用：搜索结果（`SearchTopic.tags`）、
  /// message_bus 追踪消息里的标签等。空集合永远不屏蔽。
  static bool isBlockedTagNames(
    Iterable<String> tagNames,
    Set<String> blockedTags, {
    Set<String> exemptTags = const <String>{},
  }) {
    if (blockedTags.isEmpty) return false;
    for (final raw in tagNames) {
      final name = normalizeTag(raw);
      if (name.isEmpty || exemptTags.contains(name)) continue;
      if (blockedTags.contains(name)) return true;
    }
    return false;
  }

  /// 从 message_bus 追踪消息 payload 的 `tags` 字段抽出标签名。
  ///
  /// 该字段在不同版本下可能是 `["foo"]`、`[{id, name, slug}]` 或纯 ID
  /// 数组；纯 ID 时借助 [idToNames]（列表页已知的 id → 名称映射）还原，
  /// 还原不了就忽略——宁可漏放也不误杀。
  static List<String> tagNamesFromPayload(
    Iterable<dynamic> rawTags, {
    Map<int, Set<String>> idToNames = const {},
  }) {
    final names = <String>[];
    for (final tag in rawTags) {
      if (tag is String) {
        names.add(tag);
        continue;
      }
      final id = tag is int ? tag : (tag is Map ? tag['id'] : null);
      if (tag is Map) {
        if (tag['name'] is String) names.add(tag['name'] as String);
        if (tag['slug'] is String) names.add(tag['slug'] as String);
      }
      if (id is int) names.addAll(idToNames[id] ?? const <String>{});
    }
    return names;
  }

  /// 搜索词里显式写出的标签筛选（`tags:a,b` / `tag:a+b` / `#a`）。
  ///
  /// 搜索页的豁免集合：用户在搜索语法里点名某个标签，说明此刻就想看它，
  /// 与列表页「显式按标签筛选时豁免」口径一致。`#xxx` 在 Discourse 搜索里
  /// 既可能是分类也可能是标签，这里一并当作豁免候选——豁免只会多放行，
  /// 不会误杀。
  static Set<String> explicitTagsInSearchQuery(String query) {
    final result = <String>{};
    for (final token in query.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final lower = token.toLowerCase();
      String? value;
      if (lower.startsWith('tags:')) {
        value = token.substring(5);
      } else if (lower.startsWith('tag:')) {
        value = token.substring(4);
      } else if (token.startsWith('#') && token.length > 1) {
        value = token.substring(1);
      }
      if (value == null) continue;
      for (final part in value.split(RegExp(r'[,+]'))) {
        final normalized = normalizeTag(part);
        if (normalized.isNotEmpty) result.add(normalized);
      }
    }
    return result;
  }
}
