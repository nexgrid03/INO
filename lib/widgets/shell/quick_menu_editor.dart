import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_settings.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/shiny_icon.dart';
import 'quick_actions.dart';

/// The "+" menu customiser: a bottom sheet listing every [QuickMenuAction]; the
/// user picks up to [kQuickMenuMax]. Selection order = menu order (each picked
/// tile wears its 1-based slot badge). Changes persist immediately through
/// [AppSettings.setQuickMenu], so the nav menu and wheel update live.
const int kQuickMenuMax = 5;

Future<void> showQuickMenuEditor(BuildContext context) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (_) => const _QuickMenuEditor(),
  );
}

class _QuickMenuEditor extends StatefulWidget {
  const _QuickMenuEditor();

  @override
  State<_QuickMenuEditor> createState() => _QuickMenuEditorState();
}

class _QuickMenuEditorState extends State<_QuickMenuEditor> {
  late final List<QuickMenuAction> _picked = List.of(selectedQuickMenuActions());

  void _toggle(QuickMenuAction action) {
    final isPicked = _picked.contains(action);
    if (isPicked) {
      // Keep at least one action - a "+" that opens an empty menu feels broken.
      if (_picked.length == 1) {
        HapticFeedback.heavyImpact();
        return;
      }
      setState(() => _picked.remove(action));
    } else {
      if (_picked.length >= kQuickMenuMax) {
        HapticFeedback.heavyImpact();
        return;
      }
      setState(() => _picked.add(action));
    }
    HapticFeedback.selectionClick();
    AppSettings.instance.setQuickMenu([for (final a in _picked) a.name]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final atCap = _picked.length >= kQuickMenuMax;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customize Quick Menu',
                        style: AppText.title
                            .copyWith(color: palette.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pick up to $kQuickMenuMax features for the + button',
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                // Live counter pill.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${_picked.length}/$kQuickMenuMax',
                    style: AppText.subtitle.copyWith(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final action in QuickMenuAction.values)
                    _ActionTile(
                      action: action,
                      slot: _picked.indexOf(action),
                      // Grey out unpicked tiles once the cap is reached, so
                      // "full" is visible before you tap.
                      dimmed: atCap && !_picked.contains(action),
                      onTap: () => _toggle(action),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.slot,
    required this.dimmed,
    required this.onTap,
  });

  final QuickMenuAction action;

  /// 0-based position in the picked list, or -1 when unpicked.
  final int slot;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final picked = slot >= 0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: dimmed ? 0.45 : 1,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: ShinyIcon(
          icon: action.icon,
          color: picked ? AppColors.primaryGreen : palette.textFaint,
          size: 40,
          iconSize: 20,
          radius: 12,
        ),
        title: Text(
          action.title,
          style: AppText.subtitle.copyWith(
            color: palette.textPrimary,
            fontWeight: picked ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: picked
            ? Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${slot + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : Icon(Icons.add_circle_outline_rounded,
                color: palette.textFaint, size: 24),
      ),
    );
  }
}
