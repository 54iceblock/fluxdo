import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/utils/blocked_tag_filter.dart';

Topic _topic(int id, List<String> tags) => Topic(
  id: id,
  title: 'topic-$id',
  slug: 'topic-$id',
  postsCount: 1,
  replyCount: 0,
  views: 0,
  likeCount: 0,
  categoryId: '1',
  tags: tags.map((name) => Tag(name: name)).toList(),
);

void main() {
  group('BlockedTagFilter', () {
    test('stripHashPrefix 兼容 # 前缀与空白', () {
      expect(BlockedTagFilter.stripHashPrefix(' #Foo '), 'Foo');
      expect(BlockedTagFilter.stripHashPrefix('#'), '');
      expect(BlockedTagFilter.stripHashPrefix(' foo '), 'foo');
    });

    test('normalizeTag 统一小写', () {
      expect(BlockedTagFilter.normalizeTag('#Foo '), 'foo');
      expect(BlockedTagFilter.normalizeTag('AI'), 'ai');
    });

    test('sanitizeTags 去空、按大小写无关去重且保留首次形式', () {
      expect(
        BlockedTagFilter.sanitizeTags([' AI ', '#ai', '', '#Rust', 'rust']),
        ['AI', 'Rust'],
      );
    });

    test('normalizedTags 忽略空项', () {
      expect(BlockedTagFilter.normalizedTags(['#AI', ' ', 'Rust']), {
        'ai',
        'rust',
      });
    });

    test('精确匹配：ai 不命中 ai-tools', () {
      final blocked = BlockedTagFilter.normalizedTags(['ai']);
      expect(
        BlockedTagFilter.isBlockedTopic(_topic(1, ['AI']), blocked),
        isTrue,
      );
      expect(
        BlockedTagFilter.isBlockedTopic(_topic(2, ['ai-tools']), blocked),
        isFalse,
      );
      expect(
        BlockedTagFilter.isBlockedTopic(_topic(3, ['ai', 'rust']), blocked),
        isTrue,
      );
    });

    test('无标签话题永远不屏蔽', () {
      final blocked = BlockedTagFilter.normalizedTags(['ai']);
      expect(BlockedTagFilter.isBlockedTopic(_topic(4, const []), blocked),
          isFalse);
    });

    test('空名单不屏蔽', () {
      expect(
        BlockedTagFilter.isBlockedTopic(_topic(5, ['ai']), const <String>{}),
        isFalse,
      );
    });

    test('豁免标签不参与匹配', () {
      final blocked = BlockedTagFilter.normalizedTags(['ai', 'rust']);
      // 只有被豁免的 ai → 不屏蔽
      expect(
        BlockedTagFilter.isBlockedTopic(
          _topic(6, ['ai']),
          blocked,
          exemptTags: const {'ai'},
        ),
        isFalse,
      );
      // 还带有未豁免的 rust → 仍然屏蔽
      expect(
        BlockedTagFilter.isBlockedTopic(
          _topic(7, ['ai', 'rust']),
          blocked,
          exemptTags: const {'ai'},
        ),
        isTrue,
      );
    });
  });
}
