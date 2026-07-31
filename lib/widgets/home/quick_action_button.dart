import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 5 - a single Quick Action.
///
/// A circular pill: a white glyph on a saturated accent [ShinyIcon] that lifts
/// off the background, with the caption below - the premium "round action"
/// treatment. Large touch target, press-squish via [PressableScale].
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
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A white glass circle with the action's coloured glyph - the
              // Divine Glass "round action" treatment.
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
