import 'package:flutter/foundation.dart';
import '../models/topic.dart';
import '../providers/message_bus/topic_list_events.dart';
import '../providers/topic_list/filter_provider.dart';
import 'blocked_tag_filter.dart';

class TopicListUpdateQuery {
  TopicListUpdateQuery({
    required this.filter,
    this.subset = NewSubset.all,
    this.categoryId,
    List<String> tags = const [],
    this.order,
    this.ascending = false,
    this.newNewView = false,
  }) : tags = List.unmodifiable([...tags]..sort());

  final TopicListFilter filter;
  final NewSubset subset;
  final int? categoryId;
  final List<String> tags;
  final String? order;
  final bool ascending;
  final bool newNewView;

  bool accepts(String type) => switch (filter) {
    TopicListFilter.latest => type == 'latest' || type == 'new_topic',
    TopicListFilter.newTopics =>
      (type == 'new_topic' && (!newNewView || subset != NewSubset.replies)) ||
          (type == 'unread' && newNewView && subset != NewSubset.topics),
    TopicListFilter.unread => type == 'unread',
    TopicListFilter.unseen => type == 'new_topic' || type == 'unread',
    TopicListFilter.top || TopicListFilter.hot => false,
  };

  bool sameRequest(TopicListUpdateQuery other) =>
      filter == other.filter &&
      subset == other.subset &&
      categoryId == other.categoryId &&
      listEquals(tags, other.tags) &&
      order == other.order &&
      ascending == other.ascending;

  @override
  bool operator ==(Object other) =>
      other is TopicListUpdateQuery &&
      sameRequest(other) &&
      newNewView == other.newNewView;

  @override
  int get hashCode => Object.hash(
    filter,
    subset,
    categoryId,
    Object.hashAll(tags),
    order,
    ascending,
    newNewView,
  );
}

class TopicListUpdates {
  TopicListUpdateQuery? query;
  int generation = 0;
  int _revision = 0;
  final _pending = <int, ({TopicListEvent event, int revision})>{};
  final _tagNames = <int, Set<String>>{};

  void configure(TopicListUpdateQuery next) {
    if (query == next) return;
    final sameRequest = query?.sameRequest(next) ?? false;
    query = next;
    if (sameRequest) {
      // 用户预加载信息晚于列表到达时，仅更新消息规则，不作废列表请求。
      _pending.removeWhere((_, entry) => !next.accepts(entry.event.type));
    } else {
      reset();
    }
  }

  void reset() {
    generation++;
    _pending.clear();
  }

  void rememberTags(Iterable<Tag> tags) {
    for (final tag in tags) {
      if (tag.id != null) {
        _tagNames[tag.id!] = {tag.name, if (tag.slug != null) tag.slug!};
      }
    }
  }

  /// 登记一条新话题 / 未读事件。
  ///
  /// [blockedTags] 为本地屏蔽标签（已归一化）：命中的事件直接丢弃，不进
  /// 队列，避免「有 N 条新话题」点开后全被列表过滤掉。名单之后再变化时由
  /// [snapshot] 的同名参数兜底。
  bool add(
    TopicListEvent event, {
    Set<String> blockedTags = const <String>{},
  }) {
    final current = query;
    if (!(current?.accepts(event.type) ?? false)) return false;
    if (_isLocallyBlocked(event, current!, blockedTags)) return false;
    _pending[event.topicId] = (event: event, revision: ++_revision);
    return true;
  }

  Map<int, int> snapshot(
    Map<int, int?> categoryParents, {
    Set<String> blockedTags = const <String>{},
  }) {
    final current = query;
    if (current == null) return {};
    return {
      for (final entry in _pending.entries)
        if (_matches(entry.value.event, current, categoryParents) &&
            !_isLocallyBlocked(entry.value.event, current, blockedTags))
          entry.key: entry.value.revision,
    };
  }

  /// 本地屏蔽标签判定；豁免当前列表显式筛选的标签（与列表过滤口径一致）。
  bool _isLocallyBlocked(
    TopicListEvent event,
    TopicListUpdateQuery query,
    Set<String> blockedTags,
  ) {
    if (blockedTags.isEmpty || event.tags.isEmpty) return false;
    return BlockedTagFilter.isBlockedTagNames(
      _eventTagNames(event),
      blockedTags,
      exemptTags: BlockedTagFilter.normalizedTags(query.tags),
    );
  }

  Set<String> _eventTagNames(TopicListEvent event) =>
      BlockedTagFilter.tagNamesFromPayload(
        event.tags,
        idToNames: _tagNames,
      ).toSet();

  bool _matches(
    TopicListEvent event,
    TopicListUpdateQuery query,
    Map<int, int?> categoryParents,
  ) {
    if (query.categoryId != null &&
        event.categoryId != query.categoryId &&
        categoryParents[event.categoryId] != query.categoryId) {
      return false;
    }
    if (query.tags.isEmpty) return true;
    final names = _eventTagNames(event);
    // 分类接口默认 OR；纯标签多选请求使用 match_all_tags=true。
    return query.categoryId == null
        ? query.tags.every(names.contains)
        : query.tags.any(names.contains);
  }

  // 只消费本次请求开始时的版本，保留请求期间同一话题的新消息。
  void acknowledge(Map<int, int> snapshot) {
    for (final entry in snapshot.entries) {
      if (_pending[entry.key]?.revision == entry.value) {
        _pending.remove(entry.key);
      }
    }
  }
}

List<Topic> prependTopicUpdates(List<Topic> current, List<Topic> updates) {
  final ids = updates.map((topic) => topic.id).toSet();
  return [...updates, ...current.where((topic) => !ids.contains(topic.id))];
}
