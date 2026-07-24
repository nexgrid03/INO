import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../donut_chart.dart';
import '../ino_card.dart';
import '../section_header.dart';
import '../sparkline.dart';

/// Section 7 — Investment Overview.
///
/// Hero card pairing a headline (invested / current value / P&L) with an
/// animated allocation donut and a legend, plus a portfolio-growth sparkline.
/// The donut sweeps in once via a short entrance controller.
class InvestmentSection extends StatefulWidget {
  const InvestmentSection({super.key, required this.summary});

  final InvestmentSummary summary;

  @override
  State<InvestmentSection> createState() => _InvestmentSectionState();
}

class _InvestmentSectionState extends State<InvestmentSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _sweep =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final s = widget.summary;
    final gainColor = s.isGain ? AppColors.positive : AppColors.negative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.t('investments'),
          subtitle: l10n.t('portfolioPerformance'),
          actionLabel: l10n.t('details'),
          icon: Icons.trending_up_rounded,
        ),
        InoCard(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: figures.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.t('currentValue'),
                            style: TextStyle(
                                fontSize: 12, color: palette.textSecondary)),
                        const SizedBox(height: 2),
                        Text(
                          _fmt(s.currentValue),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              s.isGain
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 15,
                              color: gainColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${_fmt(s.profit.abs())} (${s.returnPercent.abs().toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: gainColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.t('invested').replaceFirst(
                              '{v}', _fmt(s.invested)),
                          style:
                              TextStyle(fontSize: 12, color: palette.textFaint),
                        ),
                      ],
                    ),
                  ),
                  // Right: animated donut.
                  AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => DonutChart(
                      allocations: s.allocations,
                      progress: _sweep.value,
                      size: 116,
                      centerColor: gainColor,
                      centerTop: l10n.t('returnLabel'),
                      centerBottom: '+${s.returnPercent.toStringAsFixed(1)}%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Growth sparkline strip.
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Text(l10n.t('growth'),
                        style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: Sparkline(
                          values: s.growth,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Allocation legend.
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  for (final a in s.allocations)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: a.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          a.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
