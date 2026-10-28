import '../models/topic.dart';
import 'blocked_tag_filter.dart';
import 'blocked_user_filter.dart';

/// 话题列表本地过滤结果。
///
/// 用结果类而不是位置元组：过滤维度还会继续增加，每加一项都改签名会把
/// 所有调用点（3 个页面 × 2 处 + 测试）一起刷一遍。
class TopicFilterResult {
  /// 过滤后可见的话题（未过滤时与传入列表同一个实例）
  final List<Topic> visible;

  /// 隐藏总数 = [hiddenByBlocked] + [hiddenByTag] + 关键词命中数
  final int hiddenCount;

  /// 因本地屏蔽名单（发帖人）隐藏的数量
  final int hiddenByBlocked;

  /// 因本地屏蔽标签隐藏的数量
  final int hiddenByTag;

  const TopicFilterResult(
    this.visible, {
    this.hiddenCount = 0,
    this.hiddenByBlocked = 0,
    this.hiddenByTag = 0,
  });

  /// 因标题关键词隐藏的数量
  int get hiddenByKeyword => hiddenCount - hiddenByBlocked - hiddenByTag;

  bool get hasHidden => hiddenCount > 0;
}

/// 标题关键词过滤工具。
///
/// 关键词在 [PreferencesNotifier] 保存时已 trim + 去重；调用方需传入
/// `normalizedFilterKeywords`（已 lowercase）以避免重复归一化开销。
/// 标签与屏蔽名单的归一化同理。
class TopicKeywordFilter {
  TopicKeywordFilter._();

  static const int autoLoadVisibleThreshold = 5;
  static const int autoLoadMaxAttempts = 3;

  /// 是否存在任何会隐藏话题的本地过滤条件。
  ///
  /// 供各页判断用完 loadMore 后要不要自动续加载：没有过滤时多看一页是
  /// 浪费请求。
  static bool hasAnyFilter({
    required List<String> normalizedKeywords,
    Set<String> blockedUsernames = const <String>{},
    Set<String> blockedTags = const <String>{},
  }) =>
      normalizedKeywords.isNotEmpty ||
      blockedUsernames.isNotEmpty ||
      blockedTags.isNotEmpty;

  /// 应用关键词、本地屏蔽名单与本地屏蔽标签过滤。
  ///
  /// - [normalizedKeywords] 必须是已 trim + lowercase + 去空的列表。
  /// - [wholeWord] 为 true 时：对纯 ASCII word-char 关键词（如 `ai`、`db_2`）
  ///   使用单词边界（`\\b`）匹配；对含非 word-char（如中文）的关键词依然走子串
  ///   匹配——Dart 的 `\\b` 不在两个非 word-char 之间产生边界，强制套 `\\b`
  ///   会让 `\\b中文\\b` 几乎不可能命中。
  /// - [blockedTags] 与 [exemptTags] 都是已归一化（lowercase）的标签集合，
  ///   见 [BlockedTagFilter.normalizedTags]。
  ///
  /// 每条被隐藏的话题只归入一个原因，判定顺序为
  /// 屏蔽名单 → 屏蔽标签 → 关键词，因此三个计数相加等于 [TopicFilterResult.hiddenCount]。
  static TopicFilterResult apply(
    List<Topic> topics, {
    required List<String> normalizedKeywords,
    required bool wholeWord,
    Set<String> blockedUsernames = const <String>{},
    Set<String> blockedTags = const <String>{},
    Set<String> exemptTags = const <String>{},
  }) {
    if (!hasAnyFilter(
          normalizedKeywords: normalizedKeywords,
          blockedUsernames: blockedUsernames,
          blockedTags: blockedTags,
        ) ||
        topics.isEmpty) {
      return TopicFilterResult(topics);
    }

    final substrings = <String>[];
    final regexes = <RegExp>[];
    for (final keyword in normalizedKeywords) {
      if (wholeWord && _isAsciiWordOnly(keyword)) {
        regexes.add(
          RegExp(r'\b' + RegExp.escape(keyword) + r'\b', caseSensitive: false),
        );
      } else {
        substrings.add(keyword);
      }
    }

    final visible = <Topic>[];
    var hidden = 0;
    var hiddenByBlocked = 0;
    var hiddenByTag = 0;
    for (final topic in topics) {
      if (BlockedUserFilter.isBlockedTopic(topic, blockedUsernames)) {
        hidden++;
        hiddenByBlocked++;
      } else if (BlockedTagFilter.isBlockedTopic(
        topic,
        blockedTags,
        exemptTags: exemptTags,
      )) {
        hidden++;
        hiddenByTag++;
      } else if (_matches(topic.title, substrings, regexes)) {
        hidden++;
      } else {
        visible.add(topic);
      }
    }
    return TopicFilterResult(
      visible,
      hiddenCount: hidden,
      hiddenByBlocked: hiddenByBlocked,
      hiddenByTag: hiddenByTag,
    );
  }

  static bool _matches(
    String title,
    List<String> substrings,
    List<RegExp> regexes,
  ) {
    if (substrings.isNotEmpty) {
      final lower = title.toLowerCase();
      for (final keyword in substrings) {
        if (lower.contains(keyword)) return true;
      }
    }
    for (final re in regexes) {
      if (re.hasMatch(title)) return true;
    }
    return false;
  }

  /// 关键词是否全部由 ASCII 字母 / 数字 / 下划线组成（`\\w` 等价集）。
  static bool _isAsciiWordOnly(String s) {
    if (s.isEmpty) return false;
    for (final code in s.codeUnits) {
      final isWord =
          (code >= 0x30 && code <= 0x39) || // 0-9
          (code >= 0x41 && code <= 0x5A) || // A-Z
          (code >= 0x61 && code <= 0x7A) || // a-z
          code == 0x5F; // _
      if (!isWord) return false;
    }
    return true;
  }

  /// loadMore 完成后判断是否需要自动再加载一次。
  ///
  /// 当关键词命中率高时，单次 loadMore 实际新增可见条目很少，会让用户感到
  /// "划到底什么也没出来"。本判定在以下都满足时返回 true：
  /// - 仍有更多页（[hasMore]）
  /// - 本次 loadMore 的可见增量小于 [threshold]
  /// - 自动续加载次数未超 [maxAttempts]
  static bool shouldAutoLoadMore({
    required int visibleBefore,
    required int visibleAfter,
    required bool hasMore,
    required int attempts,
    int threshold = autoLoadVisibleThreshold,
    int maxAttempts = autoLoadMaxAttempts,
  }) {
    if (!hasMore) return false;
    if (attempts >= maxAttempts) return false;
    return (visibleAfter - visibleBefore) < threshold;
  }
}
