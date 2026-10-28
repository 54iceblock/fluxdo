import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/utils/topic_keyword_filter.dart';

Topic _topic(int id, String title, {List<String> tags = const []}) => Topic(
  id: id,
  title: title,
  slug: 'topic-$id',
  postsCount: 1,
  replyCount: 0,
  views: 0,
  likeCount: 0,
  categoryId: '1',
  tags: tags.map((name) => Tag(name: name)).toList(),
);

void main() {
  group('TopicKeywordFilter.apply', () {
    final topics = [
      _topic(1, 'Main thread for the AI release'),
      _topic(2, '今天的水帖合集'),
      _topic(3, 'Available tools'),
      _topic(4, 'Hello world'),
      _topic(5, 'AI 助手测试'),
    ];

    test('空关键词返回原列表，hidden 为 0', () {
      final result = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const [],
        wholeWord: false,
      );
      expect(result.visible, topics);
      expect(result.hiddenCount, 0);
      expect(result.hiddenByKeyword, 0);
    });

    test('空话题列表直接返回，hidden 为 0', () {
      final result = TopicKeywordFilter.apply(
        const [],
        normalizedKeywords: const ['ai'],
        wholeWord: false,
      );
      expect(result.visible, isEmpty);
      expect(result.hiddenCount, 0);
    });

    test('子串匹配不区分大小写', () {
      final result = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['ai'],
        wholeWord: false,
      );
      // 子串模式下 "ai" 命中 Main、Available、AI、AI 助手 → 4 条被过滤
      // 仅 id=2 "今天的水帖合集" 与 id=4 "Hello world" 留下
      // 等等：Hello world 不含 ai，Main 含 ai (m-a-i-n)，Available 含 ai (av-ai-lable)
      // AI release 含 ai，AI 助手 含 ai
      expect(result.visible.map((t) => t.id), [2, 4]);
      expect(result.hiddenCount, 3);
      expect(result.hiddenByKeyword, 3);
      expect(result.hiddenByTag, 0);
      expect(result.hiddenByBlocked, 0);
    });

    test('中文关键词命中', () {
      final result = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['水帖'],
        wholeWord: false,
      );
      expect(result.visible.map((t) => t.id), [1, 3, 4, 5]);
      expect(result.hiddenCount, 1);
    });

    test('多关键词任一命中即过滤', () {
      final result = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['ai', '水帖'],
        wholeWord: false,
      );
      // 命中：1(ai)、2(水帖)、3(ai)、5(ai) → 剩 4
      expect(result.visible.map((t) => t.id), [4]);
      expect(result.hiddenCount, 4);
    });

    test('完整词模式下英文不再误匹配子串', () {
      final result = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['ai'],
        wholeWord: true,
      );
      // 完整词下 "ai" 应命中 "AI release"（独立的 AI 词）和 "AI 助手"
      // 而不命中 "Main"（mai 是 main 的子串）和 "Available"（ai 是 av-ai-lable 的子串）
      expect(result.visible.map((t) => t.id), containsAll([2, 3, 4]));
      expect(result.visible.map((t) => t.id), isNot(contains(1)));
      expect(result.visible.map((t) => t.id), isNot(contains(5)));
      expect(result.hiddenCount, 2);
    });

    test('完整词模式对中文关键词等价于子串', () {
      final result = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: const ['水帖'],
        wholeWord: true,
      );
      expect(result.visible.map((t) => t.id), [1, 3, 4, 5]);
      expect(result.hiddenCount, 1);
    });

    test('包含特殊正则字符的关键词被转义', () {
      final special = [
        _topic(10, 'Use a.b.c notation'),
        _topic(11, 'No dots here'),
      ];
      final result = TopicKeywordFilter.apply(
        special,
        normalizedKeywords: const ['a.b.c'],
        wholeWord: false,
      );
      expect(result.visible.map((t) => t.id), [11]);
      expect(result.hiddenCount, 1);
    });

    group('标签屏蔽', () {
      final tagTopics = [
        _topic(21, 'AI 周报', tags: ['ai']),
        _topic(22, 'Rust 入门', tags: ['rust']),
        _topic(23, '多标签', tags: ['rust', 'ai']),
        _topic(24, '无标签话题'),
        _topic(25, 'AI 工具集', tags: ['ai-tools']),
      ];

      test('仅标签名单命中时隐藏，计数归入 hiddenByTag', () {
        final result = TopicKeywordFilter.apply(
          tagTopics,
          normalizedKeywords: const [],
          wholeWord: false,
          blockedTags: const {'ai'},
        );
        // 精确匹配：21、23 命中；25 的 "ai-tools" 不算命中
        expect(result.visible.map((t) => t.id), [22, 24, 25]);
        expect(result.hiddenCount, 2);
        expect(result.hiddenByTag, 2);
        expect(result.hiddenByKeyword, 0);
        expect(result.hiddenByBlocked, 0);
      });

      test('豁免标签不参与匹配', () {
        final result = TopicKeywordFilter.apply(
          tagTopics,
          normalizedKeywords: const [],
          wholeWord: false,
          blockedTags: const {'ai', 'rust'},
          exemptTags: const {'ai'},
        );
        // 豁免 ai 后：21 恢复可见；22 因 rust 被隐藏，23 因 rust 仍被隐藏
        expect(result.visible.map((t) => t.id), [21, 24, 25]);
        expect(result.hiddenByTag, 2);
      });

      test('无标签话题永远不屏蔽', () {
        final result = TopicKeywordFilter.apply(
          [_topic(30, '无标签')],
          normalizedKeywords: const [],
          wholeWord: false,
          blockedTags: const {'ai'},
        );
        expect(result.visible, hasLength(1));
        expect(result.hiddenCount, 0);
      });

      test('三种来源同时命中时计数互斥且加起来等于 hiddenCount', () {
        final mixed = [
          _topic(41, '普通话题', tags: ['ai']),
          _topic(42, '关键词话题', tags: ['rust']),
          _topic(43, '被拉黑者的话题', tags: ['ai']),
          _topic(44, '留下的话题', tags: ['go']),
        ];
        // 42 同时命中关键词与标签，按优先级归入标签
        final result = TopicKeywordFilter.apply(
          mixed,
          normalizedKeywords: const ['关键词'],
          wholeWord: false,
          blockedTags: const {'ai', 'rust'},
          blockedUsernames: const {},
        );
        expect(result.visible.map((t) => t.id), [44]);
        expect(result.hiddenCount, 3);
        expect(result.hiddenByTag, 3);
        expect(result.hiddenByKeyword, 0);
      });
    });
  });

  group('TopicKeywordFilter.hasAnyFilter', () {
    test('无任何条件时为 false', () {
      expect(
        TopicKeywordFilter.hasAnyFilter(normalizedKeywords: const []),
        isFalse,
      );
    });

    test('只有标签名单时也为 true', () {
      expect(
        TopicKeywordFilter.hasAnyFilter(
          normalizedKeywords: const [],
          blockedTags: const {'ai'},
        ),
        isTrue,
      );
    });

    test('只有关键词时为 true', () {
      expect(
        TopicKeywordFilter.hasAnyFilter(normalizedKeywords: const ['ai']),
        isTrue,
      );
    });
  });

  group('TopicKeywordFilter.shouldAutoLoadMore', () {
    test('hasMore 为 false 时不续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 5,
          visibleAfter: 5,
          hasMore: false,
          attempts: 0,
        ),
        isFalse,
      );
    });

    test('达到 maxAttempts 时不续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 0,
          visibleAfter: 0,
          hasMore: true,
          attempts: 3,
        ),
        isFalse,
      );
    });

    test('可见增量足够时不续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 10,
          visibleAfter: 25,
          hasMore: true,
          attempts: 0,
        ),
        isFalse,
      );
    });

    test('可见增量不足且未达上限且仍有更多时续加载', () {
      expect(
        TopicKeywordFilter.shouldAutoLoadMore(
          visibleBefore: 10,
          visibleAfter: 12,
          hasMore: true,
          attempts: 1,
        ),
        isTrue,
      );
    });
  });
}
