import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';

/// Section 4 — Priority Center.
///
/// Surfaces the urgent + important items the user must act on, each tagged with
/// a traffic-light severity (🔴 critical / 🟠 important / 🟢 info). The card
/// uses a coloured leading rail so severity is scannable in under a second.
class PrioritySection extends StatelessWidget {
  const PrioritySection({super.key, required this.items});

  final List<PriorityItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final critical =
        items.where((e) => e.level == PriorityLevel.critical).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.t('priorityCenter'),
          subtitle: critical > 0
              ? l10n.t('priorityUrgentItems').replaceFirst('{n}', '$critical')
              : l10n.t('priorityCenterSubtitle'),
          actionLabel: l10n.t('seeAll'),
          icon: Icons.priority_high_rounded,
        ),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 10),
            child: _PriorityCard(item: items[i]),
          ),
      ],
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.item});

  final PriorityItem item;

  Color _color() {
    switch (item.level) {
      case PriorityLevel.critical:
        return AppColors.critical;
      case PriorityLevel.important:
        return AppColors.warning;
      case PriorityLevel.info:
        return AppColors.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = _color();
    return InoCard(
      padding: EdgeInsets.zero,
      onTap: () {},
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Severity rail.
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.30),
                            blurRadius: 9,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(item.icon, size: 21, color: Colors.white),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.due,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
