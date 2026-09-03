import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/wallet_detail_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 6 - the document Filter row.
///
/// A single horizontally-scrolling row of status chips (All / Favorites /
/// Expiring / Archived). Sorting now lives as a "View recents" affordance on
/// the document-count row, so this row is purely the filters. Renders only the
/// [filters] passed in, so the screen decides which subset is relevant.
class DocumentFilterBar extends StatelessWidget {
  const DocumentFilterBar({
    super.key,
    required this.filters,
    required this.selected,
    required this.onFilter,
    this.accent,
  });

  final List<WalletFilter> filters;
  final WalletFilter selected;
  final ValueChanged<WalletFilter> onFilter;

  /// Home vault accent — selected chip fill.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tint = accent ?? AppColors.primaryGreen;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final f in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: f.localizedLabel(l10n),
                selected: f == selected,
                onTap: () => onFilter(f),
                accent: tint,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.94,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              // Gradient in both states — color↔gradient tweens dip through
              // transparency and made the deselected chip blink.
              gradient: selected
                  ? AppColors.vaultFillGradient(accent)
                  : AppColors.solidFillGradient(palette.surface),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? Colors.transparent : palette.border,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
