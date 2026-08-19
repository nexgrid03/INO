import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// Notes · Offline — same chip layout / breakpoints as Expenses · Net Worth.
/// Sits under Quick Actions without changing the 4-disc row.
class LauncherNotesOfflineShortcuts extends StatelessWidget {
  const LauncherNotesOfflineShortcuts({
    super.key,
    required this.onNotes,
    required this.onOffline,
  });

  final VoidCallback onNotes;
  final VoidCallback onOffline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _LauncherHubChipRow(
      first: (
        svg: InoHomeIcons.notes,
        label: l10n.t('notes'),
        accent: AppColors.primaryGreen,
        onTap: onNotes,
      ),
      second: (
        svg: InoHomeIcons.offline,
        label: l10n.t('offline'),
        accent: AppColors.accentCyan,
        onTap: onOffline,
      ),
    );
  }
}

/// Secondary hub shortcuts (Expenses · Net Worth) — below the fold.
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
    return _LauncherHubChipRow(
      first: (
        svg: InoHomeIcons.expenses,
        label: l10n.t('expenses'),
        accent: AppColors.accentCoral,
        onTap: onExpenses,
      ),
      second: (
        svg: InoHomeIcons.netWorth,
        label: l10n.t('netWorth'),
        accent: AppColors.primaryGreen,
        onTap: onNetWorth,
      ),
    );
  }
}

typedef _HubChipSpec = ({
  String svg,
  String label,
  Color accent,
  VoidCallback onTap,
});

/// Shared glass chip pair — always one row (labels scale down, never wrap).
class _LauncherHubChipRow extends StatelessWidget {
  const _LauncherHubChipRow({required this.first, required this.second});

  final _HubChipSpec first;
  final _HubChipSpec second;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final flat = InoStyle.usesFlatBackdrop(context);

    Widget chip(_HubChipSpec spec) {
      return Expanded(
        child: PressableScale(
          pressedScale: 0.97,
          child: GestureDetector(
            onTap: spec.onTap,
            behavior: HitTestBehavior.opaque,
            child: LiquidGlass(
              borderRadius: BorderRadius.circular(16),
              // Chips sit in a dense row — frost matches glass without N blurs.
              enableBlur: false,
              blur: flat ? 16 : 20,
              frost: flat ? 1.35 : (palette.isDark ? 1.0 : 0.72),
              shadow: flat,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: spec.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: InoSvgIcon(spec.svg, size: 20, color: spec.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        spec.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
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
        chip(first),
        const SizedBox(width: 10),
        chip(second),
      ],
    );
  }
}
