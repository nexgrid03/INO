import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// Secondary hub shortcuts (Expenses · Net Worth) — kept below the first fold
/// so Quick Actions stay the primary launcher row.
class LauncherHubShortcuts extends StatelessWidget {
  const LauncherHubShortcuts({
    super.key,
    required this.onExpenses,
    required this.onNetWorth,
  });

  final VoidCallback onExpenses;
  final VoidCallback onNetWorth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);

    Widget chip({
      required String svg,
      required String label,
      required Color accent,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: PressableScale(
          pressedScale: 0.97,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: LiquidGlass(
              borderRadius: BorderRadius.circular(16),
              enableBlur: false,
              frost: palette.isDark ? 1.0 : 0.72,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: InoSvgIcon(svg, size: 20, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.textFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          svg: InoHomeIcons.expenses,
          label: l10n.t('expenses'),
          accent: AppColors.accentCoral,
          onTap: onExpenses,
        ),
        const SizedBox(width: 10),
        chip(
          svg: InoHomeIcons.netWorth,
          label: l10n.t('netWorth'),
          accent: AppColors.primaryGreen,
          onTap: onNetWorth,
        ),
      ],
    );
  }
}
