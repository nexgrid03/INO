import 'package:flutter/material.dart';

import '../../services/password_utils.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A four-segment strength meter plus a text label, driven by [PasswordUtils].
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final strength = PasswordUtils.strength(password);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = i < strength.score;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 6,
                  decoration: BoxDecoration(
                    color: filled ? strength.color : palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            );
          }),
        ),
        if (strength != PasswordStrength.empty) ...[
          const SizedBox(height: 6),
          Text(
            strength.label,
            style: AppText.caption.copyWith(
              color: strength.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
