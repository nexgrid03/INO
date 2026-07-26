import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/currency.dart';
import '../../models/investment_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../services/app_settings.dart';
import '../../services/investment_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import '../wallet/wallet_detail_screen.dart';
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
        .where((i) =>
            (_typeFilter == null || i.type == _typeFilter) && i.matches(_query))
        .toList();
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push<Investment>(
      MaterialPageRoute(builder: (_) => const InvestmentFormScreen()),
    );
    if (created == null || !mounted) return;
    await showSuccessBurst(context, '${created.name} added');
  }

  Future<void> _edit(Investment investment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvestmentFormScreen(existing: investment),
      ),
    );
  }

  void _openDocuments() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletDetailScreen(category: widget.category),
      ),
    );
  }

  Future<void> _actions(Investment i) async {
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
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
              leading:
                  const Icon(Icons.edit_rounded, color: AppColors.primaryGreen),
              title: Text('Edit holding',
                  style: TextStyle(color: palette.textPrimary)),
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
                i.isFavorite ? 'Remove from favourites' : 'Add to favourites',
                style: TextStyle(color: palette.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _store.toggleFavorite(i.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.critical),
              title: const Text('Delete holding',
                  style: TextStyle(color: AppColors.critical)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await confirmDestructive(
                  context,
                  title: 'Delete holding?',
                  message: '"${i.name}" will be removed from your portfolio.',
                );
                if (!ok) return;
                await _store.remove(i.id);
                if (!mounted) return;
                showModuleToast(context, '${i.name} deleted');
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
    final hasAny = _store.items.isNotEmpty;

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: ModuleHeader(
                  title: 'Investments',
                  subtitle: hasAny
                      ? '${_store.count} holding${_store.count == 1 ? '' : 's'} · ${moneyWords(_store.totalValue, _currency)}'
                      : 'Your portfolio',
                  actions: [
                    ModuleIconButton(
                      icon: Icons.folder_shared_rounded,
                      tooltip: 'Investment documents',
                      onTap: _openDocuments,
                    ),
                    ModuleIconButton(
                      icon: Icons.add_rounded,
                      tooltip: 'Add investment',
                      onTap: _add,
                    ),
                  ],
                ),
              ),
              if (hasAny)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _SegmentedTabs(controller: _tabs),
                ),
              Expanded(
                child: !_store.isLoaded
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: ModuleSkeleton(height: 120, count: 3),
                      )
                    : !hasAny
                        ? ModuleEmptyState(
                            icon: Icons.trending_up_rounded,
                            title: 'No investments yet',
                            message:
                                'Add stocks, mutual funds, FDs, gold or anything '
                                'else you hold to see your portfolio, returns and '
                                'allocation in one place.',
                            actionLabel: 'Add investment',
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
              label: 'Add investment',
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

  static const _labels = ['Overview', 'Holdings', 'Activity'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
          for (var i = 0; i < _labels.length; i++)
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
                    _labels[i],
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
    final allocation = store.allocation;
    final maturing = store.maturingWithin(60);
    final ret = store.totalReturn;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        // ---- Total investments hero ----
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              gradient: palette.cardGradient,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.border),
              boxShadow: palette.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total investments',
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(store.totalValue, currency),
                    style: AppText.bigNumber.copyWith(color: palette.textPrimary),
                  ),
                ),
                const SizedBox(height: 6),
                if (ret != null)
                  Row(
                    children: [
                      Icon(
                        store.totalProfit >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 15,
                        color: store.totalProfit >= 0
                            ? AppColors.success
                            : AppColors.critical,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(ret.abs() * 100).toStringAsFixed(1)}%  ·  ${money(store.totalProfit.abs(), currency)}',
                        style: AppText.subtitle.copyWith(
                          color: store.totalProfit >= 0
                              ? AppColors.success
                              : AppColors.critical,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        store.totalProfit >= 0 ? 'overall gain' : 'overall loss',
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: moneyWords(store.totalInvested, currency),
                        label: 'Invested',
                        icon: Icons.savings_rounded,
                        accent: const Color(0xFF4383EA),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: moneyWords(store.totalProfit.abs(), currency),
                        label: store.totalProfit >= 0 ? 'Gain' : 'Loss',
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
                        label: 'Holdings',
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
            title: 'Asset allocation',
            icon: Icons.pie_chart_rounded,
            subtitle: 'Where your money sits',
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
                              '+${allocation.length - 6} more',
                              style: AppText.caption
                                  .copyWith(color: palette.textFaint),
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
            title: 'Top holdings',
            icon: Icons.leaderboard_rounded,
            accent: const Color(0xFF9B6DE0),
            trailing: TextButton(
              onPressed: onSeeHoldings,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('See all'),
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
              title: 'Maturing soon',
              icon: Icons.event_available_rounded,
              accent: AppColors.warning,
              subtitle: 'Within the next 60 days',
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
                  style: AppText.title
                      .copyWith(color: palette.textPrimary, fontSize: 18),
                ),
                if (top != null)
                  SizedBox(
                    width: 74,
                    child: Text(
                      top.type.shortLabel,
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
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: slice.type.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                slice.type.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: palette.textPrimary),
              ),
            ),
            Text(
              '${(slice.share * 100).round()}%',
              style: AppText.label.copyWith(color: palette.textPrimary),
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
    final ret = investment.returnPercent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: investment.type.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(investment.type.icon,
                size: 16, color: investment.type.color),
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
                  investment.type.shortLabel,
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
                    color:
                        investment.isUp ? AppColors.success : AppColors.critical,
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: FloatingSearchBar(
            hint: 'Search holdings',
            height: 48,
            controller: searchController,
            onChanged: onSearch,
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              ModuleChip(
                label: 'All',
                selected: typeFilter == null,
                onTap: () => onTypeFilter(null),
              ),
              for (final t in availableTypes) ...[
                const SizedBox(width: 8),
                ModuleChip(
                  label: t.shortLabel,
                  icon: t.icon,
                  selected: typeFilter == t,
                  accent: t.color,
                  onTap: () => onTypeFilter(t),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: investments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No holdings match this filter.',
                      style:
                          AppText.body.copyWith(color: palette.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  itemCount: investments.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => FadeSlideIn(
                    delay: Duration(milliseconds: (i * 40).clamp(0, 280)),
                    offset: 12,
                    child: InvestmentCard(
                      investment: investments[i],
                      currency: currency,
                      onTap: () => onTap(investments[i]),
                      onMore: () => onMore(investments[i]),
                      onFavorite: () => onFavorite(investments[i]),
                    ),
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
    final accent = investment.type.color;
    final ret = investment.returnPercent;
    final up = investment.isUp;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onMore,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: palette.cardGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(investment.type.icon, size: 20, color: accent),
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
                              const Icon(Icons.star_rounded,
                                  size: 16, color: AppColors.warning),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            investment.type.shortLabel,
                            if ((investment.institution ?? '').isNotEmpty)
                              investment.institution!,
                            if (investment.maskedAccount != null)
                              investment.maskedAccount!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption
                              .copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (onMore != null)
                    ModuleIconButton(
                      icon: Icons.more_horiz_rounded,
                      size: 32,
                      tooltip: 'Actions',
                      onTap: onMore!,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(
                  children: [
                    _Metric(
                      label: 'Invested',
                      value: moneyWords(investment.invested, currency),
                    ),
                    _MetricDivider(color: palette.border),
                    _Metric(
                      label: 'Current',
                      value: moneyWords(investment.value, currency),
                    ),
                    _MetricDivider(color: palette.border),
                    _Metric(
                      label: up ? 'Profit' : 'Loss',
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
          Text(label,
              style: AppText.caption
                  .copyWith(color: palette.textSecondary, fontSize: 11)),
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
    final events = <_ActivityEvent>[
      for (final i in investments) ...[
        _ActivityEvent(i, i.createdAt, added: true),
        if (i.updatedAt.difference(i.createdAt).inMinutes > 1)
          _ActivityEvent(i, i.updatedAt, added: false),
      ],
    ]..sort((a, b) => b.at.compareTo(a.at));

    if (events.isEmpty) {
      return Center(
        child: Text('Nothing here yet.',
            style: AppText.body.copyWith(color: palette.textSecondary)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final e = events[i];
        return FadeSlideIn(
          delay: Duration(milliseconds: (i * 35).clamp(0, 260)),
          offset: 10,
          child: InkWell(
            onTap: () => onTap(e.investment),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                gradient: palette.cardGradient,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: palette.border),
              ),
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
                          '${e.added ? 'Added' : 'Updated'} ${e.investment.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary),
                        ),
                        Text(
                          formatModuleDate(e.at),
                          style: AppText.caption
                              .copyWith(color: palette.textSecondary),
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
