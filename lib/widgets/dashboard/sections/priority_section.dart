import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_style.dart';
import '../../common/shiny_icon.dart';
import '../ino_card.dart';
import '../section_header.dart';

/// Section 4 - Priority Center.
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
    final themeStyle = InoStyle.of(context);
    final bold = themeStyle == ThemeStyle.bold;
    final color = InoStyle.accent(context, _color());

    // Bold: the severity colour that used to sit on the small icon badge
    // floods the whole card; the glyph stays in place in plain white and the
    // texts flip to white. Classic/soft keep the white card + badge.
    return InoCard(
      padding: EdgeInsets.zero,
      onTap: () {},
      gradient: bold
          ? LinearGradient(
              colors: [InoStyle.boldFill(color), InoStyle.deepen(color, 0.16)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      borderColor: bold ? InoStyle.boldBorder(color) : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Severity rail.
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: bold ? InoStyle.deepen(color, 0.26) : color,
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
                    bold
                        ? SizedBox(
                            width: 40,
                            height: 40,
                            // Bigger than the old badge glyph - with the badge
                            // body gone it can fill the slot.
                            child: Icon(
                              item.icon,
                              color: Colors.white,
                              size: 30,
                            ),
                          )
                        : ShinyIcon(
                            icon: item.icon,
                            color: color,
                            size: 40,
                            iconSize: 21,
                            radius: 12,
                            style: ShinyIconStyle.filled,
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
                              color:
                                  bold ? Colors.white : palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: bold
                                  ? InoStyle.boldTextSecondary
                                  : palette.textSecondary,
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
                        color: bold
                            ? Colors.white.withValues(alpha: 0.20)
                            : color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.due,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: bold ? Colors.white : color,
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
