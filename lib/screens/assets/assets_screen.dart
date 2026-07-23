import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../services/net_worth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../documents/add_document_screen.dart';
import '../networth/net_worth_analytics_screen.dart';

/// Assets — the total asset value, a searchable breakdown by class (from the
/// [NetWorthService] allocation model) and a real "Add asset" entry point that
/// opens the add-document flow.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final _query = TextEditingController();
  String _term = '';

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      final t = _query.text.trim().toLowerCase();
      if (t != _term) setState(() => _term = t);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _addAsset() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddDocumentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final service = NetWorthService.instance;
    final total = service.total;
    final all = service.allocations;
    final growthPercent = service.data.growthPercent;
    final trend =
        service.seriesFor(NetWorthRange.month).map((p) => p.value).toList();
    final filtered = _term.isEmpty
        ? all
        : all.where((a) => a.label.toLowerCase().contains(_term)).toList();

    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('assets'),
      actions: [
        IconButton(
          tooltip: l10n.t('addAsset'),
          icon: Icon(Icons.add_rounded, color: palette.textPrimary),
          onPressed: _addAsset,
        ),
      ],
      child: Column(
        children: [
          // Hero — gradient performance card (total, trend pill, sparkline).
          FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, 0),
              child: PressableScale(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const NetWorthAnalyticsScreen())),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow:
                          AppShadows.glow(AppColors.primaryGreen, opacity: 0.28),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      child: Stack(
                        children: [
                          const Positioned(
                              right: -44, top: -44, child: _WashCircle(130)),
                          const Positioned(
                              left: -36, bottom: -56, child: _WashCircle(150)),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(l10n.t('totalAssets'),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.1)),
                                    ),
                                    // Real month-over-month trend from the
                                    // same NetWorthService read model.
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.pill),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              growthPercent >= 0
                                                  ? Icons.trending_up_rounded
                                                  : Icons.trending_down_rounded,
                                              size: 14,
                                              color: Colors.white),
                                          const SizedBox(width: 4),
                                          Text(
                                              '${growthPercent >= 0 ? '+' : ''}${growthPercent.toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(formatInr(total),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.0)),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 40,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter:
                                        _HeroSparklinePainter(values: trend),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                        l10n
                                            .t('assetClasses')
                                            .replaceAll('{n}', '${all.length}'),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    const Spacer(),
                                    Text(l10n.t('viewAnalytics'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    const Icon(Icons.chevron_right_rounded,
                                        color: Colors.white, size: 18),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Search.
          FadeSlideIn(
            delay: const Duration(milliseconds: 70),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: FloatingSearchBar(
                hint: l10n.t('searchAssets'),
                controller: _query,
              ),
            ),
          ),
          if (filtered.isNotEmpty)
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen + 4,
                    AppSpacing.md, AppSpacing.screen, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Decorative section label (Stitch "Portfolio Assets" rhythm).
                  child: Text('PORTFOLIO ASSETS',
                      style: AppText.label.copyWith(
                          color: palette.textFaint,
                          fontSize: 11,
                          letterSpacing: 1.2)),
                ),
              ),
            )
          else
            const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: l10n.t('noMatchingAssets'),
                    message: l10n.t('noMatchingAssetsSubtitle'),
                    actionLabel: l10n.t('addAsset'),
                    onAction: _addAsset,
                    compact: true,
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                        AppSpacing.xs, AppSpacing.screen, AppSpacing.xl),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => FadeSlideIn(
                      delay: Duration(milliseconds: 150 + 45 * math.min(i, 6)),
                      child: _AssetTile(allocation: filtered[i], total: total),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Soft translucent disc used as a decorative wash inside the gradient hero.
class _WashCircle extends StatelessWidget {
  const _WashCircle(this.size);
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.10),
      ),
    );
  }
}

/// A compact white sparkline of the real 30-day net-worth series, drawn inside
/// the gradient hero (mirrors the Stitch wealth-graph treatment).
class _HeroSparklinePainter extends CustomPainter {
  _HeroSparklinePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs() < 1 ? 1.0 : (maxV - minV);

    Offset at(int i) {
      final x = size.width * (i / (values.length - 1));
      final norm = (values[i] - minV) / range;
      final y = size.height * 0.06 + (size.height * 0.88) * (1 - norm);
      return Offset(x, y);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(values.length - 1), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _HeroSparklinePainter old) =>
      old.values != values;
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.allocation, required this.total});

  final AssetAllocation allocation;
  final double total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pct = total == 0 ? 0.0 : allocation.value / total;
    return InoCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: allocation.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(_iconFor(allocation.label),
                    color: allocation.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(allocation.label,
                    style:
                        AppText.subtitle.copyWith(color: palette.textPrimary)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatInr(allocation.value),
                      style: AppText.subtitle
                          .copyWith(color: palette.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: allocation.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('${(pct * 100).toStringAsFixed(0)}%',
                        style: AppText.label.copyWith(
                            color: allocation.color, fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: palette.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(allocation.color),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String label) {
    switch (label) {
      case 'Investments':
        return Icons.trending_up_rounded;
      case 'Property':
        return Icons.home_work_rounded;
      case 'Bank & Cash':
        return Icons.account_balance_rounded;
      case 'Gold':
        return Icons.workspace_premium_rounded;
      case 'Digital Assets':
        return Icons.currency_bitcoin_rounded;
      default:
        return Icons.savings_rounded;
    }
  }
}
