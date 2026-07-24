import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';

/// Section 3 — Life Overview Summary.
///
/// A responsive grid of compact stat cards (Documents, Properties, Net Worth …)
/// each showing a count, a status chip, and the last-updated line. The grid
/// reflows from 2 → 3 → 4 columns as width grows, so it reads well on phones,
/// foldables and tablets alike.
class LifeOverviewSection extends StatelessWidget {
  const LifeOverviewSection({super.key, required this.items});

  final List<LifeOverviewItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.t('lifeOverview'),
          subtitle: l10n.t('lifeOverviewSubtitle'),
          icon: Icons.dashboard_rounded,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 720 ? 4 : (w >= 480 ? 3 : 2);
            const gap = 12.0;
            final cardW = (w - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: cardW,
                    child: _OverviewTile(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Premium gradient icon container. Uses the item's bespoke [gradient] when
/// present (e.g. Net Worth's brand gradient, white glyph), otherwise a soft
/// two-stop tint of the accent colour.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.item});

  final LifeOverviewItem item;

  @override
  Widget build(BuildContext context) {
    final hasGradient = item.gradient != null;
    // Solid accent fill (or brand gradient for Net Worth) + white glyph.
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: hasGradient ? null : item.color,
        gradient: hasGradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: item.gradient!,
              )
            : null,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: (hasGradient ? item.gradient!.first : item.color)
                .withValues(alpha: 0.30),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(item.icon, size: 18, color: Colors.white),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({required this.item});

  final LifeOverviewItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      padding: const EdgeInsets.all(14),
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(item: item),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: palette.textFaint),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.count,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 12.5,
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  item.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.textFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
