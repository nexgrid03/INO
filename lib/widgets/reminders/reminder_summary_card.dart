import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/shiny_icon.dart';
import '../dashboard/ino_card.dart';

/// One of the four compact headline cards at the top of the dashboard
/// (Today · This Week · Expiring · Completed). Bright glossy icon chip, a big count,
/// and a short label. Sized to sit two-up in a grid, always visible.
class ReminderSummaryCard extends StatelessWidget {
  const ReminderSummaryCard({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShinyIcon(
                icon: icon,
                color: color,
                size: 32,
                iconSize: 18,
                radius: AppRadius.chip,
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
