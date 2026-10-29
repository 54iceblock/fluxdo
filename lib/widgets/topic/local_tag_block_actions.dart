import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../../services/toast_service.dart';
import '../../utils/blocked_tag_filter.dart';
import '../../utils/dialog_utils.dart';

/// 在「本机屏蔽此标签」与「取消屏蔽」之间切换，并用 Toast 告知结果。
///
/// 标签页按钮与标签 Badge 长按菜单共用。纯本地偏好，不要求登录。
/// [wasBlocked] 由调用方传入切换前状态，Toast 文案据此区分。
Future<void> toggleLocalTagBlock(
  WidgetRef ref,
  BuildContext context,
  String tagName, {
  required bool wasBlocked,
}) async {
  final l10n = context.l10n;
  await ref.read(preferencesProvider.notifier).toggleBlockedTag(tagName);
  ToastService.showInfo(
    wasBlocked ? l10n.tag_localUnblocked(tagName) : l10n.tag_localBlocked(tagName),
  );
}

/// 标签 Badge 长按弹出的快捷菜单：只有一个「本机屏蔽 / 取消屏蔽」动作。
///
/// 用底部菜单而不是长按直接切换：长按是易误触手势，屏蔽又会让其它列表
/// 里的话题消失，多一步确认更稳。
Future<void> showLocalTagBlockSheet(
  BuildContext context,
  WidgetRef ref,
  String tagName,
) async {
  final key = BlockedTagFilter.normalizeTag(tagName);
  if (key.isEmpty) return;
  final blocked = ref
      .read(preferencesProvider)
      .normalizedBlockedTags
      .contains(key);
  final l10n = context.l10n;
  final confirmed = await showAppBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(
              '#$tagName',
              style: Theme.of(sheetContext).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: Icon(
              blocked ? Symbols.label_rounded : Symbols.label_off_rounded,
            ),
            title: Text(blocked ? l10n.tag_localUnblock : l10n.tag_localBlock),
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await toggleLocalTagBlock(ref, context, tagName, wasBlocked: blocked);
}
