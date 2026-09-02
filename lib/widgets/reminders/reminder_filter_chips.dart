import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Horizontally scrolling filter chips - the curated six: All · Documents ·
/// Insurance · Health · Property · Family. The selected chip is a Divine Glass
/// tinted pill: mist fill with a brand hairline and brand-coloured glyph.
class ReminderFilterChips extends StatelessWidget {
  const ReminderFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ReminderFilterKind selected;
  final ValueChanged<ReminderFilterKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: context.horizontalCardHeight(44),
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screen,
          vertical: 4,
        ),
        children: [
          for (final kind in ReminderFilterKind.values)
            _Chip(
              label: kind.localizedLabel(l10n),
              icon: kind.icon,
              selected: kind == selected,
              onTap: () => onSelected(kind),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: PressableScale(
        pressedScale: 0.94,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.tealMist : palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? AppColors.primaryGreen : palette.border,
                  width: selected ? 1.3 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected
                        ? AppColors.primaryGreen
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.primaryGreen
                          : palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
