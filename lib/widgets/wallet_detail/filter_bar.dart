import 'package:flutter/material.dart';

import '../../models/wallet_detail_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 4 — Filters.
///
/// A horizontally scrolling row of filter chips (All / Active / Expiring … )
/// plus a sort control on the right. Selecting a chip animates its fill to the
/// brand green.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.selected,
    required this.sort,
    required this.onFilter,
    required this.onSortTap,
  });

  final WalletFilter selected;
  final WalletSort sort;
  final ValueChanged<WalletFilter> onFilter;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (final f in WalletFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(
                      label: f.label,
                      selected: f == selected,
                      onTap: () => onFilter(f),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sort control.
        PressableScale(
          pressedScale: 0.92,
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip),
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
                      sort.label,
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
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? null : palette.surface,
              gradient: selected ? AppGradients.primary : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? Colors.transparent : palette.border,
              ),
              boxShadow: selected
                  ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.28)
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
