import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/wallet_detail_models.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 6 — the document Filter row.
///
/// A focused second row of status chips (All / Favorites / Expiring / Archived)
/// with the Sort control pinned on the right. "Recent" intentionally lives
/// inside Sort, not here. Renders only the [filters] passed in, so the screen
/// decides which subset of [WalletFilter] is relevant.
class DocumentFilterBar extends StatelessWidget {
  const DocumentFilterBar({
    super.key,
    required this.filters,
    required this.selected,
    required this.sort,
    required this.onFilter,
    required this.onSortTap,
  });

  final List<WalletFilter> filters;
  final WalletFilter selected;
  final WalletSort sort;
  final ValueChanged<WalletFilter> onFilter;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(
                      label: f.localizedLabel(l10n),
                      selected: f == selected,
                      onTap: () => onFilter(f),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        PressableScale(
          pressedScale: 0.92,
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSortTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_vert_rounded,
                        size: 18, color: AppColors.primaryGreen),
                    const SizedBox(width: 5),
                    Text(
                      sort.localizedLabel(l10n),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.94,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryGreen : palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.primaryGreen : palette.border,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
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
