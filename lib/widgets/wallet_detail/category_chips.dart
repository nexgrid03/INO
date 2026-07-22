import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 5 — horizontal Category Chips.
///
/// A fast, single-tap way to narrow the list to one kind of document. The
/// labels are derived from the wallet's actual records (a leading "All", then
/// each distinct category / tag present) so the row is never decorative — every
/// chip resolves to real results. Selecting a chip filters the list below.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  /// Category labels, excluding the implicit leading "All".
  final List<String> categories;

  /// Currently selected category, or `null` for "All".
  final String? selected;

  /// Emits the tapped category, or `null` when "All" is chosen.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _CategoryChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final c in categories)
            _CategoryChip(
              label: c,
              selected: c == selected,
              onTap: () => onSelected(c),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
    return Padding(
      padding: const EdgeInsets.only(right: 12),
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
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected ? null : palette.surface,
                gradient: selected ? AppGradients.primary : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? Colors.transparent : palette.border,
                ),
                boxShadow: selected
                    ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.26)
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
      ),
    );
  }
}
