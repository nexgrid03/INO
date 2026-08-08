import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/responsive/responsive_metric_text.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../services/net_worth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/home/net_worth_chart.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// Net Worth Analytics — live totals from Property + Investment wallets,
/// history-backed chart, and allocation from real holdings only.
class NetWorthAnalyticsScreen extends StatefulWidget {
  const NetWorthAnalyticsScreen({super.key});

  @override
  State<NetWorthAnalyticsScreen> createState() =>
      _NetWorthAnalyticsScreenState();
}

class _NetWorthAnalyticsScreenState extends State<NetWorthAnalyticsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await NetWorthService.instance.ensureReady();
    if (!mounted) return;
    NetWorthService.instance.addListener(_onChanged);
    setState(() => _loading = false);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    NetWorthService.instance.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return SettingsScaffold(
      title: l10n.t('netWorth'),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body(palette, l10n),
    );
  }

  Widget _body(AppPalette palette, AppLocalizations l10n) {
    final service = NetWorthService.instance;
    final data = service.data;
    final monthSeries = service.seriesFor(NetWorthRange.month);
    final yearSeries = service.seriesFor(NetWorthRange.year);
    final monthChange = _percentChange(monthSeries);
    final yearChange = _percentChange(yearSeries);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.xl,
      ),
      children: [
        AdaptiveGlassCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          radius: AppRadius.large,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('netWorthTotalLabel').toUpperCase(),
                style: AppText.label.copyWith(
                  color: palette.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: ResponsiveMetricText(
                      formatInr(data.total),
                      style: AppText.display.copyWith(
                        color: palette.textPrimary,
                        fontSize: 34,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _GrowthPill(percent: data.growthPercent),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${data.isUp ? '+' : ''}${formatInr(data.growthAmount)} ${l10n.t('thisMonth')}',
                style: AppText.caption.copyWith(
                  color: data.isUp ? AppColors.positive : AppColors.negative,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsCard(
          child: NetWorthChart(
            height: 200,
            pointsFor: (range) => service.seriesFor(range),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _TrendCard(
                label: l10n.t('monthlyTrend'),
                percent: monthChange,
                icon: Icons.calendar_view_month_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _TrendCard(
                label: l10n.t('yearlyTrend'),
                percent: yearChange,
                icon: Icons.timeline_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.section),
        Text(
          l10n.t('assetDistribution'),
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (data.allocations.isEmpty)
          SettingsCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Add properties or investments to build your net worth. '
                'Totals come from your Property and Investment wallets.',
                style: AppText.caption.copyWith(
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          )
        else
          SettingsCard(
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      allocations: data.allocations,
                      track: palette.surfaceVariant,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${data.allocations.length}',
                            style: AppText.title
                                .copyWith(color: palette.textPrimary),
                          ),
                          Text(
                            'classes',
                            style: AppText.label
                                .copyWith(color: palette.textFaint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    children: [
                      for (final a in data.allocations)
                        _LegendRow(allocation: a, total: data.total),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Based on your Property and Investment wallets. '
          'The chart updates from daily snapshots as your holdings change.',
          style: AppText.caption.copyWith(
            color: palette.textFaint,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  double _percentChange(List<NetWorthPoint> series) {
    if (series.length < 2) return 0;
    final start = series.first.value;
    final end = series.last.value;
    if (start == 0) return 0;
    return double.parse((((end - start) / start) * 100).toStringAsFixed(1));
  }
}

class _GrowthPill extends StatelessWidget {
  const _GrowthPill({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = up ? AppColors.positive : AppColors.negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${percent.abs().toStringAsFixed(1)}%',
            style: AppText.label.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.label,
    required this.percent,
    required this.icon,
  });

  final String label;
  final double percent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = percent >= 0;
    final color = up ? AppColors.positive : AppColors.negative;
    return SettingsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            '${up ? '+' : ''}${percent.toStringAsFixed(1)}%',
            style: AppText.headline.copyWith(color: color, fontSize: 20),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.allocation, required this.total});

  final AssetAllocation allocation;
  final double total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pct = total == 0 ? 0 : (allocation.value / total) * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: allocation.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: allocation.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allocation.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  formatInr(allocation.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: palette.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: AppText.label.copyWith(color: AppColors.primaryGreen),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.allocations, required this.track});

  final List<AssetAllocation> allocations;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final total = allocations.fold<double>(0, (s, a) => s + a.value);
    if (total <= 0) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    const stroke = 18.0;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    canvas.drawCircle(
      center,
      radius - stroke / 2,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    var start = -math.pi / 2;
    const gap = 0.04;
    for (final a in allocations) {
      final sweep = (a.value / total) * (math.pi * 2) - gap;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = a.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.allocations != allocations;
}
