import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_more_topics.dart';
import 'package:fluxdo/widgets/topic/keyword_filter_hint_bar.dart';

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
  group('filterMoreTopicsByBlockedTags', () {
    test('空名单原样返回同一实例', () {
      final topics = [_topic(1, ['ai'])];
      expect(
        identical(filterMoreTopicsByBlockedTags(topics, const {}), topics),
        isTrue,
      );
    });

    test('命中即隐藏，无标签保留', () {
      final result = filterMoreTopicsByBlockedTags(
        [_topic(1, ['ai']), _topic(2, ['rust']), _topic(3, const [])],
        const {'ai'},
      );
      expect(result.map((t) => t.id), [2, 3]);
    });

    test('豁免当前话题自身的标签', () {
      final result = filterMoreTopicsByBlockedTags(
        [_topic(1, ['ai']), _topic(2, ['ai', 'rust'])],
        const {'ai', 'rust'},
        currentTopicTags: const [Tag(name: 'AI')],
      );
      // 1 只有被豁免的 ai → 保留；2 还带 rust → 隐藏
      expect(result.map((t) => t.id), [1]);
    });
  });

  group('resolveFilterHintSource', () {
    FilterHintSource resolve(int total, int blocked, int tag) =>
        resolveFilterHintSource(
          hiddenCount: total,
          hiddenByBlocked: blocked,
          hiddenByTag: tag,
        );

    test('单一来源直达对应入口', () {
      expect(resolve(3, 3, 0), FilterHintSource.blockedUsers);
      expect(resolve(3, 0, 3), FilterHintSource.blockedTags);
      expect(resolve(3, 0, 0), FilterHintSource.keywords);
    });

    test('任意两种及以上来源 → 分来源菜单', () {
      expect(resolve(3, 1, 2), FilterHintSource.mixed);
      expect(resolve(3, 1, 0), FilterHintSource.mixed);
      expect(resolve(3, 0, 1), FilterHintSource.mixed);
      expect(resolve(3, 1, 1), FilterHintSource.mixed);
    });
  });
}
