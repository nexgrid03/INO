import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 5 — a single Quick Action.
///
/// A circular pill: the coloured glyph floats inside a round, softly-tinted
/// container that lifts off the background, with the caption below — the
/// premium "round action" treatment. Large touch target, press-squish via
/// [PressableScale].
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // The action colour washed over the card surface so the pill reads
    // correctly in both light and dark mode.
    final fill = Color.alphaBlend(
        color.withValues(alpha: palette.isDark ? 0.18 : 0.10), palette.surface);
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: Border.all(
                      color: color.withValues(alpha: 0.22), width: 1),
                  boxShadow: palette.cardShadow,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Scale the label down to fit rather than truncating, so full
              // names (e.g. "Reminder", "Document") always show.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppText.caption.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
