import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../settings/definitions/preferences_defs.dart';
import '../../utils/dialog_utils.dart';

/// 话题列表顶部的「本地内容过滤」提示。
///
/// 仅在有话题被隐藏时显示。整行可点击，按本次隐藏的实际来源打开对应
/// 管理入口：单一来源直达对应名单 / 关键词编辑；多个来源同时命中时弹出
/// 分来源菜单（各来源隐藏数），见 [resolveFilterHintSource]。
/// 形态与 `_buildNewTopicIndicator` 保持一致（同样的胶囊容器、margin、圆角），
/// 但使用 surfaceVariant 系颜色而非 primaryContainer，刻意做成次要状态层级，
/// 与新话题 CTA 堆叠时形成「主操作 + 次要状态」的视觉层次。
class KeywordFilterHintBar extends ConsumerWidget {
  final int hiddenCount;

  /// [hiddenCount] 中因本地屏蔽名单隐藏的数量
  final int hiddenByBlocked;

  /// [hiddenCount] 中因本地屏蔽标签隐藏的数量
  final int hiddenByTag;

  const KeywordFilterHintBar({
    super.key,
    required this.hiddenCount,
    this.hiddenByBlocked = 0,
    this.hiddenByTag = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hiddenCount <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    final source = resolveFilterHintSource(
      hiddenCount: hiddenCount,
      hiddenByBlocked: hiddenByBlocked,
      hiddenByTag: hiddenByTag,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            switch (source) {
              case FilterHintSource.blockedUsers:
                showBlockedUsernamesDialog(context, ref);
              case FilterHintSource.blockedTags:
                showBlockedTagsDialog(context, ref);
              case FilterHintSource.keywords:
                showTopicFilterKeywordsDialog(context, ref);
              case FilterHintSource.mixed:
                _showSourceMenu(context, ref);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.visibility_off_rounded,
                  size: 14,
                  color: mutedColor,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.topic_keywordFilter_hiddenCount(hiddenCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedColor,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '  ·  ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedColor.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                Text(
                  l10n.topic_keywordFilter_manage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 混合来源：列出每个有命中的来源及其隐藏数，点哪项开哪个管理入口。
  Future<void> _showSourceMenu(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final hiddenByKeyword = hiddenCount - hiddenByBlocked - hiddenByTag;
    final entries = <(IconData, String, int, FilterHintSource)>[
      if (hiddenByKeyword > 0)
        (
          Symbols.filter_alt_off_rounded,
          l10n.preferences_topicFilterKeywords,
          hiddenByKeyword,
          FilterHintSource.keywords,
        ),
      if (hiddenByBlocked > 0)
        (
          Symbols.person_off_rounded,
          l10n.preferences_blockedUsernames,
          hiddenByBlocked,
          FilterHintSource.blockedUsers,
        ),
      if (hiddenByTag > 0)
        (
          Symbols.label_off_rounded,
          l10n.preferences_blockedTags,
          hiddenByTag,
          FilterHintSource.blockedTags,
        ),
    ];
    final picked = await showAppBottomSheet<FilterHintSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                l10n.topic_keywordFilter_hiddenCount(hiddenCount),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final (icon, title, count, value) in entries)
              ListTile(
                leading: Icon(icon),
                title: Text(title),
                trailing: Text('$count'),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    switch (picked) {
      case FilterHintSource.blockedUsers:
        await showBlockedUsernamesDialog(context, ref);
      case FilterHintSource.blockedTags:
        await showBlockedTagsDialog(context, ref);
      case FilterHintSource.keywords:
      case FilterHintSource.mixed:
        await showTopicFilterKeywordsDialog(context, ref);
    }
  }
}

/// 提示条点击后应打开的管理入口
enum FilterHintSource { keywords, blockedUsers, blockedTags, mixed }

/// 按本次隐藏的来源决定入口：单一来源直达对应管理页，多来源弹分来源菜单。
FilterHintSource resolveFilterHintSource({
  required int hiddenCount,
  required int hiddenByBlocked,
  required int hiddenByTag,
}) {
  final hiddenByKeyword = hiddenCount - hiddenByBlocked - hiddenByTag;
  final sources = (hiddenByKeyword > 0 ? 1 : 0) +
      (hiddenByBlocked > 0 ? 1 : 0) +
      (hiddenByTag > 0 ? 1 : 0);
  if (sources > 1) return FilterHintSource.mixed;
  if (hiddenByBlocked > 0) return FilterHintSource.blockedUsers;
  if (hiddenByTag > 0) return FilterHintSource.blockedTags;
  return FilterHintSource.keywords;
}
