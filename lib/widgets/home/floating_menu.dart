import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A premium bottom-sheet menu of quick-add actions.
///
/// Used both by the Home "More" quick action and anywhere an action overflow is
/// needed. Renders a grip, a title and a responsive grid of [QuickAction]s.
class FloatingMenu {
  FloatingMenu._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<QuickAction> actions,
    required void Function(QuickAction action) onSelect,
  }) {
    final palette = AppPalette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  style: AppText.title.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 420 ? 4 : 3;
                    const gap = AppSpacing.sm;
                    final itemW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: AppSpacing.md,
                      children: [
                        for (final a in actions)
                          SizedBox(
                            width: itemW,
                            child: _MenuItem(
                              action: a,
                              onTap: () {
                                Navigator.of(context).pop();
                                onSelect(a);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.action, required this.onTap});

  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.93,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: action.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: Icon(action.icon, color: action.color, size: 24),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
