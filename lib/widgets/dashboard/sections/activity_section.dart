import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';

/// Section 12 — Recent Activity Timeline.
///
/// A chronological feed of the user's latest actions, drawn as a classic
/// timeline: a connecting rail with coloured nodes, the action title and a
/// relative timestamp. Gives a sense of momentum and an audit trail.
class ActivitySection extends StatelessWidget {
  const ActivitySection({super.key, required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.t('recentActivity'),
          subtitle: l10n.t('recentActivitySubtitle'),
          actionLabel: l10n.t('history'),
          icon: Icons.history_rounded,
        ),
        InoCard(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _TimelineRow(
                  item: items[i],
                  isLast: i == items.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.isLast});

  final ActivityItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail with node.
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(item.icon, size: 17, color: Colors.white),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: palette.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 7, bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.time,
                    style: TextStyle(fontSize: 12, color: palette.textFaint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
