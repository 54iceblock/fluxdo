import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../settings/definitions/preferences_defs.dart';

/// 话题列表顶部的「本地内容过滤」提示。
///
/// 仅在有话题被隐藏时显示。整行可点击，按本次隐藏的实际来源打开对应
/// 管理入口：本次隐藏全部来自屏蔽名单时打开名单，全部来自屏蔽标签时打开
/// 标签名单，其余情况（纯关键词或混合来源）打开关键词编辑。
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
    // 单一来源才跳对应管理页；混合来源时管理关键词（三种过滤共用同一入口组）
    final onlyBlocked = hiddenByBlocked >= hiddenCount;
    final onlyTag = !onlyBlocked && hiddenByTag >= hiddenCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (onlyBlocked) {
              showBlockedUsernamesDialog(context, ref);
            } else if (onlyTag) {
              showBlockedTagsDialog(context, ref);
            } else {
              showTopicFilterKeywordsDialog(context, ref);
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
}
