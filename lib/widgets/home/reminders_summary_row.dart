import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// PhonePe-style Reminders summary (Today / Tomorrow / This Week / Completed).
/// Launcher theme only — classic Home keeps reminders in the overview strip.
class RemindersSummaryRow extends StatelessWidget {
  const RemindersSummaryRow({
    super.key,
    required this.today,
    required this.tomorrow,
    required this.thisWeek,
    required this.completed,
    this.onToday,
    this.onTomorrow,
    this.onThisWeek,
    this.onCompleted,
  });

  final int today;
  final int tomorrow;
  final int thisWeek;
  final int completed;
  final VoidCallback? onToday;
  final VoidCallback? onTomorrow;
  final VoidCallback? onThisWeek;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = [
      _Tile(
        label: l10n.t('today'),
        count: today,
        icon: Icons.calendar_today_rounded,
        accent: AppColors.accentIndigo,
        onTap: onToday,
      ),
      _Tile(
        label: l10n.t('tomorrow'),
        count: tomorrow,
        icon: Icons.event_rounded,
        accent: AppColors.warning,
        onTap: onTomorrow,
      ),
      _Tile(
        label: l10n.t('thisWeek'),
        count: thisWeek,
        icon: Icons.date_range_rounded,
        accent: AppColors.success,
        onTap: onThisWeek,
      ),
      _Tile(
        label: l10n.t('completed'),
        count: completed,
        icon: Icons.check_circle_rounded,
        accent: AppColors.accentEmerald,
        onTap: onCompleted,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.count,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(16),
          blur: 16,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
