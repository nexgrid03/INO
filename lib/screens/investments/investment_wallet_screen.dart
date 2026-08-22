import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../models/investment_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../navigation/wallet_module_router.dart';
import '../../services/app_settings.dart';
import '../../services/investment_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/dashboard/sparkline.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import 'investment_form_screen.dart';

/// The Investment Wallet - a portfolio dashboard.
///
/// Three tabs, in the order an investor actually thinks: **Overview** (total
/// value, return, allocation ring, growth), **Holdings** (every position, with
/// search and type filters) and **Activity** (a dated ledger of what was added
/// or updated). The wallet's documents stay reachable from the header.
class InvestmentWalletScreen extends StatefulWidget {
  const InvestmentWalletScreen({super.key, required this.category});

  final WalletCategory category;

  @override
  State<InvestmentWalletScreen> createState() => _InvestmentWalletScreenState();
}

class _InvestmentWalletScreenState extends State<InvestmentWalletScreen>
    with SingleTickerProviderStateMixin {
  final _store = InvestmentStore.instance;
  final _searchController = TextEditingController();

  // Created eagerly in initState, never lazily: with an empty portfolio the tab
  // strip is not built, and a `late` initialiser would then construct the
  // controller inside dispose() - which needs an ancestor lookup that is
  // illegal at that point.
  late final TabController _tabs;

  String _query = '';
  InvestmentType? _typeFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _store.ensureLoaded();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Currency get _currency =>
      Currencies.byCode(AppSettings.instance.currency.value);

  List<Investment> get _visible {
    return _store.sorted
        .where(
          (i) =>
              (_typeFilter == null || i.type == _typeFilter) &&
              i.matches(_query),
        )
        .toList();
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push<Investment>(
      MaterialPageRoute(builder: (_) => const InvestmentFormScreen()),
    );
    if (created == null || !mounted) return;
    await showSuccessBurst(
      context,
      AppLocalizations.of(context)
          .t('nameAdded')
          .replaceAll('{name}', created.name),
    );
  }

  Future<void> _edit(Investment investment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvestmentFormScreen(existing: investment),
      ),
    );
  }

  void _openDocuments() => openWalletDocuments(context, widget.category);

  Future<void> _actions(Investment i) async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: AppColors.primaryGreen),
              title: Text(
                l10n.t('editHolding'),
                style: TextStyle(color: palette.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _edit(i);
              },
            ),
            ListTile(
              leading: Icon(
                i.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: AppColors.warning,
              ),
              title: Text(
                l10n.t(
                  i.isFavorite ? 'removeFromFavourites' : 'addToFavourites',
                ),
                style: TextStyle(color: palette.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _store.toggleFavorite(i.id);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.critical,
              ),
              title: Text(
                l10n.t('deleteHolding'),
                style: const TextStyle(color: AppColors.critical),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await confirmDestructive(
                  context,
                  title: l10n.t('deleteHoldingTitle'),
                  message: l10n
                      .t('deleteHoldingMessage')
                      .replaceAll('{name}', i.name),
                );
                if (!ok) return;
                await _store.remove(i.id);
                if (!mounted) return;
                showModuleToast(
                  context,
                  l10n.t('nameDeleted').replaceAll('{name}', i.name),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final hasAny = _store.items.isNotEmpty;
    final holdingCount = _store.count == 1
        ? l10n.t('oneHolding')
        : l10n.t('nHoldings').replaceAll('{count}', '${_store.count}');

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: divineGlassEnabled(context),
        child: SafeArea(
          top: !divineGlassEnabled(context),
          bottom: false,
          child: Column(
            children: [
              ModuleHeader(
                title: l10n.t('investments'),
                subtitle: hasAny
                    ? '$holdingCount · ${moneyWords(_store.totalValue, _currency)}'
                    : l10n.t('yourPortfolio'),
                icon: Icons.trending_up_rounded,
                accent: AppColors.primaryGreen,
                actions: [
                  ModuleIconButton(
                    icon: Icons.folder_shared_rounded,
                    tooltip: l10n.t('investmentDocuments'),
                    color: AppColors.primaryGreen,
                    onTap: _openDocuments,
                  ),
                  ModuleIconButton(
                    icon: Icons.add_rounded,
                    tooltip: l10n.t('addInvestment'),
                    color: AppColors.primaryGreen,
                    onTap: _add,
                  ),
                ],
              ),
              if (hasAny)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 0),
                  child: _SegmentedTabs(controller: _tabs),
                ),
              Expanded(
                child: !_store.isLoaded
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 0),
                        child: ModuleSkeleton(height: 120, count: 3),
                      )
                    : !hasAny
                    ? ModuleEmptyState(
                        icon: Icons.trending_up_rounded,
                        title: l10n.t('noInvestmentsYet'),
                        message: l10n.t('noInvestmentsMessage'),
                        actionLabel: l10n.t('addInvestment'),
                        onAction: _add,
                      )
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _OverviewTab(
                            store: _store,
                            currency: _currency,
                            onSeeHoldings: () => _tabs.animateTo(1),
                            onTapType: (t) {
                              setState(() => _typeFilter = t);
                              _tabs.animateTo(1);
                            },
                          ),
                          _HoldingsTab(
                            investments: _visible,
                            currency: _currency,
                            searchController: _searchController,
                            onSearch: (v) => setState(() => _query = v),
                            typeFilter: _typeFilter,
                            availableTypes: _store.allocation
                                .map((s) => s.type)
                                .toList(),
                            onTypeFilter: (t) =>
                                setState(() => _typeFilter = t),
                            onTap: _edit,
                            onMore: _actions,
                            onFavorite: (i) => _store.toggleFavorite(i.id),
                          ),
                          _ActivityTab(
                            investments: _store.items,
                            currency: _currency,
                            onTap: _edit,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: hasAny
          ? GradientButton(
              label: l10n.t('addInvestment'),
              icon: Icons.add_rounded,
              expand: false,
              onTap: _add,
            )
          : null,
    );
  }
}

/// The pill segmented control from the mock, built on the app's chip styling.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.controller});

  final TabController controller;

  static const _labelKeys = ['overview', 'holdings', 'activity'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final labels = [for (final k in _labelKeys) l10n.t(k)];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.animateTo(i);
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: controller.index == i
                        ? InoStyle.gradient(context, AppColors.brandGradient)
                        : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: controller.index == i
                        ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.22)
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: AppText.caption.copyWith(
                      color: controller.index == i
                          ? Colors.white
                          : palette.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.store,
    required this.currency,
    required this.onSeeHoldings,
    required this.onTapType,
  });

  final InvestmentStore store;
  final Currency currency;
  final VoidCallback onSeeHoldings;
  final ValueChanged<InvestmentType> onTapType;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final allocation = store.allocation;
    final maturing = store.maturingWithin(60);
    final ret = store.totalReturn;
    final up = store.totalProfit >= 0;

    // A decorative growth line for the hero: the portfolio's cumulative value
    // in the order holdings were added.
    final byDate = [...store.items]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var running = 0.0;
    final growth = <double>[for (final i in byDate) running += i.value];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 120),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        // ---- Total investments hero ----
        FadeSlideIn(
          child: AdaptiveGlassCard(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            radius: AppRadius.large,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.t('totalPortfolioValue'),
                        style: AppText.caption.copyWith(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (ret != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (up ? AppColors.success : AppColors.critical)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              up
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 14,
                              color: up
                                  ? AppColors.success
                                  : AppColors.critical,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${up ? '+' : '-'}${(ret.abs() * 100).toStringAsFixed(1)}%',
                              style: AppText.label.copyWith(
                                color: up
                                    ? AppColors.success
                                    : AppColors.critical,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(store.totalValue, currency),
                    style: AppText.bigNumber.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (ret != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${money(store.totalProfit.abs(), currency)} '
                    '${l10n.t(up ? 'overallGain' : 'overallLoss')}',
                    style: AppText.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
                if (growth.length >= 2) ...[
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: Sparkline(
                      values: growth,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: moneyWords(store.totalInvested, currency),
                        label: l10n.t('investedLabel'),
                        icon: Icons.savings_rounded,
                        accent: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: moneyWords(store.totalProfit.abs(), currency),
                        label: l10n.t(store.totalProfit >= 0 ? 'gain' : 'loss'),
                        icon: store.totalProfit >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        accent: store.totalProfit >= 0
                            ? AppColors.success
                            : AppColors.critical,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: '${store.count}',
                        label: l10n.t('holdings'),
                        icon: Icons.inventory_2_rounded,
                        accent: AppColors.primaryGreen,
                        onTap: onSeeHoldings,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ---- Allocation ----
        FadeSlideIn(
          delay: const Duration(milliseconds: 60),
          child: ModuleSection(
            title: l10n.t('assetAllocation'),
            icon: Icons.pie_chart_rounded,
            subtitle: l10n.t('whereYourMoneySits'),
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  _AllocationRing(allocation: allocation),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      children: [
                        for (final slice in allocation.take(6))
                          _LegendRow(
                            slice: slice,
                            currency: currency,
                            onTap: () => onTapType(slice.type),
                          ),
                        if (allocation.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l10n.t('plusNMore').replaceAll(
                                    '{count}',
                                    '${allocation.length - 6}',
                                  ),
                              style: AppText.caption.copyWith(
                                color: palette.textFaint,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ---- Top holdings ----
        FadeSlideIn(
          delay: const Duration(milliseconds: 100),
          child: ModuleSection(
            title: l10n.t('topHoldings'),
            icon: Icons.leaderboard_rounded,
            accent: AppColors.primaryGreen,
            trailing: TextButton(
              onPressed: onSeeHoldings,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l10n.t('seeAll')),
            ),
            children: [
              for (final i in store.sorted.take(4))
                _TopHoldingRow(investment: i, currency: currency),
            ],
          ),
        ),

        // ---- Maturing soon ----
        if (maturing.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            delay: const Duration(milliseconds: 140),
            child: ModuleSection(
              title: l10n.t('maturingSoon'),
              icon: Icons.event_available_rounded,
              accent: AppColors.warning,
              subtitle: l10n.t('withinNext60Days'),
              children: [
                for (final i in maturing)
                  DetailRow(
                    label: i.name,
                    value: formatModuleDate(i.maturityDate!),
                    icon: i.type.icon,
                    valueColor: AppColors.warning,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The allocation donut. Drawn here (rather than reusing the dashboard's
/// [DonutChart]) because it animates its own sweep and sizes to this card.
class _AllocationRing extends StatelessWidget {
  const _AllocationRing({required this.allocation});

  final List<InvestmentSlice> allocation;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final top = allocation.isEmpty ? null : allocation.first;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        width: 122,
        height: 122,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(122),
              painter: _RingPainter(
                allocation: allocation,
                progress: t,
                track: palette.surfaceVariant,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  top == null ? '—' : '${(top.share * 100).round()}%',
                  style: AppText.title.copyWith(
                    color: palette.textPrimary,
                    fontSize: 18,
                  ),
                ),
                if (top != null)
                  SizedBox(
                    width: 74,
                    child: Text(
                      investmentTypeShortLabel(l10n, top.type),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.allocation,
    required this.progress,
    required this.track,
  });

  final List<InvestmentSlice> allocation;
  final double progress;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );

    // The empty track keeps the ring visible even at a single 100% slice.
    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    const start = -1.5708; // 12 o'clock
    const gap = 0.06;
    var angle = start;
    final sweepLimit = start + 6.28318 * progress;
    for (final slice in allocation) {
      final full = slice.share * 6.28318;
      final remaining = sweepLimit - angle;
      if (remaining <= 0) break;
      final sweep = (full - gap).clamp(0.0, remaining);
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          angle,
          sweep,
          false,
          Paint()
            ..color = slice.type.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round,
        );
      }
      angle += full;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.allocation != allocation;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.currency,
    required this.onTap,
  });

  final InvestmentSlice slice;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            AdaptiveListIcon(
              icon: slice.type.icon,
              accent: slice.type.color,
              size: 30,
              iconSize: 15,
              radius: 10,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    investmentTypeShortLabel(l10n, slice.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    moneyWords(slice.value, currency),
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
              '${(slice.share * 100).round()}%',
              style: AppText.label.copyWith(color: AppColors.primaryGreen),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopHoldingRow extends StatelessWidget {
  const _TopHoldingRow({required this.investment, required this.currency});

  final Investment investment;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ret = investment.returnPercent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AdaptiveListIcon(
            icon: investment.type.icon,
            accent: investment.type.color,
            size: 32,
            iconSize: 16,
            radius: 10,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  investment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(color: palette.textPrimary),
                ),
                Text(
                  investmentTypeShortLabel(l10n, investment.type),
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(investment.value, currency),
                style: AppText.subtitle.copyWith(color: palette.textPrimary),
              ),
              if (ret != null)
                Text(
                  '${investment.isUp ? '+' : '-'}${(ret.abs() * 100).toStringAsFixed(1)}%',
                  style: AppText.caption.copyWith(
                    color: investment.isUp
                        ? AppColors.success
                        : AppColors.critical,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Holdings
// ---------------------------------------------------------------------------

class _HoldingsTab extends StatelessWidget {
  const _HoldingsTab({
    required this.investments,
    required this.currency,
    required this.searchController,
    required this.onSearch,
    required this.typeFilter,
    required this.availableTypes,
    required this.onTypeFilter,
    required this.onTap,
    required this.onMore,
    required this.onFavorite,
  });

  final List<Investment> investments;
  final Currency currency;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final InvestmentType? typeFilter;
  final List<InvestmentType> availableTypes;
  final ValueChanged<InvestmentType?> onTypeFilter;
  final ValueChanged<Investment> onTap;
  final ValueChanged<Investment> onMore;
  final ValueChanged<Investment> onFavorite;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            AppSpacing.md,
            16,
            AppSpacing.sm,
          ),
          child: FloatingSearchBar(
            hint: l10n.t('searchHoldings'),
            height: 48,
            controller: searchController,
            onChanged: onSearch,
          ),
        ),
        SizedBox(
          height: ModuleChipRow.rowHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            children: [
              ModuleChip(
                label: l10n.t('all'),
                selected: typeFilter == null,
                onTap: () => onTypeFilter(null),
              ),
              for (final t in availableTypes) ...[
                const SizedBox(width: 8),
                ModuleChip(
                  label: investmentTypeShortLabel(l10n, t),
                  icon: t.icon,
                  selected: typeFilter == t,
                  accent: t.color,
                  onTap: () => onTypeFilter(t),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: investments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.t('noHoldingsMatchFilter'),
                      style: AppText.body.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    AppSpacing.md,
                    16,
                    120,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  itemCount: investments.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  // No FadeSlideIn here: recycled rows replay the entrance
                  // animation every time they scroll back into view (see the
                  // note in profile_screen.dart). Keyed so sort / favourite
                  // changes re-associate each element with its own card.
                  itemBuilder: (context, i) => InvestmentCard(
                    key: ValueKey(investments[i].id),
                    investment: investments[i],
                    currency: currency,
                    onTap: () => onTap(investments[i]),
                    onMore: () => onMore(investments[i]),
                    onFavorite: () => onFavorite(investments[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One holding: type chip, name, institution, value and return.
class InvestmentCard extends StatelessWidget {
  const InvestmentCard({
    super.key,
    required this.investment,
    required this.currency,
    required this.onTap,
    this.onMore,
    this.onFavorite,
  });

  final Investment investment;
  final Currency currency;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = investment.type.color;
    final ret = investment.returnPercent;
    final up = investment.isUp;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onMore,
        behavior: HitTestBehavior.opaque,
        child: AdaptiveGlassCard(
          padding: const EdgeInsets.all(14),
          radius: AppRadius.card,
          child: Column(
            children: [
              Row(
                children: [
                  AdaptiveListIcon(
                    icon: investment.type.icon,
                    accent: accent,
                    size: 40,
                    iconSize: 20,
                    radius: 12,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                investment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.title.copyWith(
                                  color: palette.textPrimary,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (investment.isFavorite)
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppColors.warning,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            investmentTypeShortLabel(l10n, investment.type),
                            if ((investment.institution ?? '').isNotEmpty)
                              investment.institution!,
                            if (investment.maskedAccount != null)
                              investment.maskedAccount!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onMore != null)
                    ModuleIconButton(
                      icon: Icons.more_horiz_rounded,
                      size: 32,
                      tooltip: l10n.t('actions'),
                      onTap: onMore!,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(
                  children: [
                    _Metric(
                      label: l10n.t('investedLabel'),
                      value: moneyWords(investment.invested, currency),
                    ),
                    _MetricDivider(color: palette.border),
                    _Metric(
                      label: l10n.t('current'),
                      value: moneyWords(investment.value, currency),
                    ),
                    _MetricDivider(color: palette.border),
                    _Metric(
                      label: l10n.t(up ? 'profit' : 'loss'),
                      value: ret == null
                          ? moneyWords(investment.profit.abs(), currency)
                          : '${up ? '+' : '-'}${(ret.abs() * 100).toStringAsFixed(1)}%',
                      color: up ? AppColors.success : AppColors.critical,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.subtitle.copyWith(
                color: color ?? palette.textPrimary,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 26,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: color,
  );
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

/// A dated ledger of portfolio activity, newest first. Derived from the
/// holdings themselves - an entry appears when a holding was added, and again
/// when it was later updated, so the tab never invents transactions the app
/// hasn't actually recorded.
class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.investments,
    required this.currency,
    required this.onTap,
  });

  final List<Investment> investments;
  final Currency currency;
  final ValueChanged<Investment> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final events = <_ActivityEvent>[
      for (final i in investments) ...[
        _ActivityEvent(i, i.createdAt, added: true),
        if (i.updatedAt.difference(i.createdAt).inMinutes > 1)
          _ActivityEvent(i, i.updatedAt, added: false),
      ],
    ]..sort((a, b) => b.at.compareTo(a.at));

    if (events.isEmpty) {
      return Center(
        child: Text(
          l10n.t('nothingHereYet'),
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 120),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final e = events[i];
        // No FadeSlideIn: recycled rows would replay the entrance on scroll.
        return InkWell(
          onTap: () => onTap(e.investment),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AdaptiveGlassCard(
            padding: const EdgeInsets.all(13),
            radius: AppRadius.card,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (e.added ? AppColors.success : AppColors.lightBlue)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    e.added
                        ? Icons.add_circle_outline_rounded
                        : Icons.edit_rounded,
                    size: 17,
                    color: e.added ? AppColors.success : AppColors.lightBlue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n
                            .t(e.added ? 'addedName' : 'updatedName')
                            .replaceAll('{name}', e.investment.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        formatModuleDate(e.at),
                        style: AppText.caption.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  moneyWords(e.investment.value, currency),
                  style: AppText.subtitle.copyWith(color: palette.textPrimary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityEvent {
  const _ActivityEvent(this.investment, this.at, {required this.added});

  final Investment investment;
  final DateTime at;
  final bool added;
}
