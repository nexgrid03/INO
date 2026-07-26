import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/currency.dart';
import '../../models/property_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../services/app_settings.dart';
import '../../services/property_store.dart';
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
import 'property_detail_screen.dart';
import 'property_form_screen.dart';

/// The Property Wallet - a register of everything the user owns, not a document
/// folder.
///
/// A portfolio hero (total value + appreciation + four live stats) sits above a
/// searchable, filterable list of property cards. Every property opens a full
/// dashboard; the wallet's *documents* stay one tap away in the header, so
/// nothing the wallet could do before has been taken away.
class PropertyWalletScreen extends StatefulWidget {
  const PropertyWalletScreen({super.key, required this.category});

  /// The hub category this screen replaces - used for the Documents route.
  final WalletCategory category;

  @override
  State<PropertyWalletScreen> createState() => _PropertyWalletScreenState();
}

enum _PropertyFilter { all, owned, rented, construction, sold }

extension _PropertyFilterX on _PropertyFilter {
  String get label => switch (this) {
        _PropertyFilter.all => 'All',
        _PropertyFilter.owned => 'Owned',
        _PropertyFilter.rented => 'Rented',
        _PropertyFilter.construction => 'Building',
        _PropertyFilter.sold => 'Sold',
      };

  bool accepts(Property p) => switch (this) {
        _PropertyFilter.all => true,
        _PropertyFilter.owned => p.status == PropertyStatus.owned,
        _PropertyFilter.rented =>
          p.status == PropertyStatus.rented || p.status == PropertyStatus.leased,
        _PropertyFilter.construction =>
          p.status == PropertyStatus.underConstruction,
        _PropertyFilter.sold => p.status == PropertyStatus.sold,
      };
}

enum _PropertySort { recent, valueHigh, valueLow, name }

extension _PropertySortX on _PropertySort {
  String get label => switch (this) {
        _PropertySort.recent => 'Recently updated',
        _PropertySort.valueHigh => 'Value (high → low)',
        _PropertySort.valueLow => 'Value (low → high)',
        _PropertySort.name => 'Name (A–Z)',
      };
}

class _PropertyWalletScreenState extends State<PropertyWalletScreen> {
  final _store = PropertyStore.instance;
  final _searchController = TextEditingController();

  String _query = '';
  _PropertyFilter _filter = _PropertyFilter.all;
  _PropertySort _sort = _PropertySort.recent;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Currency get _currency =>
      Currencies.byCode(AppSettings.instance.currency.value);

  List<Property> get _visible {
    final list = _store.items
        .where((p) => _filter.accepts(p) && p.matches(_query))
        .toList();
    switch (_sort) {
      case _PropertySort.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _PropertySort.valueHigh:
        list.sort((a, b) => b.portfolioValue.compareTo(a.portfolioValue));
      case _PropertySort.valueLow:
        list.sort((a, b) => a.portfolioValue.compareTo(b.portfolioValue));
      case _PropertySort.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    // Favourites always lead, whatever the sort.
    list.sort((a, b) =>
        a.isFavorite == b.isFavorite ? 0 : (a.isFavorite ? -1 : 1));
    return list;
  }

  Future<void> _addProperty() async {
    final created = await Navigator.of(context).push<Property>(
      MaterialPageRoute(builder: (_) => const PropertyFormScreen()),
    );
    if (created == null || !mounted) return;
    await showSuccessBurst(context, '${created.name} added');
  }

  Future<void> _openProperty(Property property) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(propertyId: property.id),
      ),
    );
  }

  /// The wallet's documents - the original document manager, untouched.
  void _openDocuments() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletDetailScreen(category: widget.category),
      ),
    );
  }

  Future<void> _openSort() async {
    final picked = await showModulePicker(
      context,
      title: 'Sort properties',
      labels: [for (final s in _PropertySort.values) s.label],
      selectedIndex: _PropertySort.values.indexOf(_sort),
    );
    if (picked == null || !mounted) return;
    setState(() => _sort = _PropertySort.values[picked]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final visible = _visible;
    final hasAny = _store.items.isNotEmpty;

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: ModuleHeader(
                    title: 'Property Wallet',
                    subtitle: hasAny
                        ? '${_store.count} ${_store.count == 1 ? 'property' : 'properties'} · ${moneyWords(_store.totalValue, _currency)}'
                        : 'Your property register',
                    actions: [
                      ModuleIconButton(
                        icon: Icons.folder_shared_rounded,
                        tooltip: 'Property documents',
                        onTap: _openDocuments,
                      ),
                      ModuleIconButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Add property',
                        onTap: _addProperty,
                      ),
                    ],
                  ),
                ),
              ),
              if (!_store.isLoaded)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: ModuleSkeleton(height: 132, count: 3),
                  ),
                )
              else if (!hasAny)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ModuleEmptyState(
                    icon: Icons.home_work_rounded,
                    title: 'No properties yet',
                    message:
                        'Add a house, plot or commercial space to track its value, '
                        'ownership, legal details and documents in one place.',
                    actionLabel: 'Add property',
                    onAction: _addProperty,
                  ),
                )
              else ...[
                // Portfolio hero.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: FadeSlideIn(
                      child: _PortfolioCard(
                        total: _store.totalValue,
                        appreciation: _store.totalAppreciation,
                        currency: _currency,
                        count: _store.count,
                        rentedCount: _store.countOf(PropertyStatus.rented) +
                            _store.countOf(PropertyStatus.leased),
                        monthlyRent: _store.monthlyRent,
                        loan: _store.totalLoan,
                      ),
                    ),
                  ),
                ),
                // Search + sort.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: FloatingSearchBar(
                        hint: 'Search properties',
                        height: 48,
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        trailing: ModuleIconButton(
                          icon: Icons.swap_vert_rounded,
                          tooltip: 'Sort',
                          size: 34,
                          onTap: _openSort,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ModuleChipRow(
                    labels: [for (final f in _PropertyFilter.values) f.label],
                    counts: [
                      for (final f in _PropertyFilter.values)
                        _store.items.where(f.accepts).length,
                    ],
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    selectedIndex: _PropertyFilter.values.indexOf(_filter),
                    onSelect: (i) =>
                        setState(() => _filter = _PropertyFilter.values[i]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: _NoMatches(
                      onClear: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _filter = _PropertyFilter.all;
                        });
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => FadeSlideIn(
                        delay: Duration(milliseconds: (i * 45).clamp(0, 300)),
                        offset: 12,
                        child: PropertyCard(
                          property: visible[i],
                          currency: _currency,
                          onTap: () => _openProperty(visible[i]),
                          onFavorite: () =>
                              _store.toggleFavorite(visible[i].id),
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ],
          ),
        ),
      ),
      // The gradient pill IS the FAB - Material's own circle would be the one
      // control on the screen that isn't part of the design system.
      floatingActionButton: hasAny
          ? GradientButton(
              label: 'Add property',
              icon: Icons.add_rounded,
              expand: false,
              onTap: _addProperty,
            )
          : null,
    );
  }
}

/// The portfolio hero: total value, appreciation and the four numbers that
/// actually matter across a property portfolio.
class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.total,
    required this.appreciation,
    required this.currency,
    required this.count,
    required this.rentedCount,
    required this.monthlyRent,
    required this.loan,
  });

  final double total;
  final double? appreciation;
  final Currency currency;
  final int count;
  final int rentedCount;
  final double monthlyRent;
  final double loan;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = (appreciation ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: InoStyle.gradient(context, AppColors.brandGradient),
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total portfolio value',
                style: AppText.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const Spacer(),
              if (appreciation != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        up
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${(appreciation!.abs() * 100).toStringAsFixed(1)}%',
                        style: AppText.label.copyWith(color: Colors.white),
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
              money(total, currency),
              style: AppText.bigNumber.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppRadius.chip + 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Properties',
                    value: '$count',
                    icon: Icons.home_work_rounded,
                    color: AppColors.primaryGreen,
                  ),
                ),
                _Divider(palette: palette),
                Expanded(
                  child: _MiniStat(
                    label: 'Rented',
                    value: '$rentedCount',
                    icon: Icons.key_rounded,
                    color: const Color(0xFF4383EA),
                  ),
                ),
                _Divider(palette: palette),
                Expanded(
                  child: _MiniStat(
                    label: 'Rent / mo',
                    value: monthlyRent > 0
                        ? moneyWords(monthlyRent, currency)
                        : '—',
                    icon: Icons.payments_rounded,
                    color: AppColors.success,
                  ),
                ),
                _Divider(palette: palette),
                Expanded(
                  child: _MiniStat(
                    label: 'Loan',
                    value: loan > 0 ? moneyWords(loan, currency) : '—',
                    icon: Icons.account_balance_rounded,
                    color: loan > 0 ? AppColors.warning : palette.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: palette.border);
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: AppText.subtitle
                .copyWith(color: palette.textPrimary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption
              .copyWith(color: palette.textSecondary, fontSize: 10.5),
        ),
      ],
    );
  }
}

/// One property in the list: image (or a typed gradient placeholder), name,
/// location, status pill, value and appreciation.
class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.currency,
    required this.onTap,
    this.onFavorite,
  });

  final Property property;
  final Currency currency;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = property.status.color;
    final appreciation = property.appreciation;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: palette.cardGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thumbnail - the user's photo, else a typed gradient tile.
              SizedBox(
                width: 104,
                child: _Thumbnail(property: property, accent: accent),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              property.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.title.copyWith(
                                color: palette.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (onFavorite != null)
                            GestureDetector(
                              onTap: onFavorite,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  property.isFavorite
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 19,
                                  color: property.isFavorite
                                      ? AppColors.warning
                                      : palette.textFaint,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(property.type.icon,
                              size: 13, color: palette.textFaint),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              property.locationLine.isEmpty
                                  ? property.type.label
                                  : '${property.type.label} · ${property.locationLine}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption
                                  .copyWith(color: palette.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  property.portfolioValue > 0
                                      ? money(property.portfolioValue, currency)
                                      : 'Value not set',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.title.copyWith(
                                    color: property.portfolioValue > 0
                                        ? palette.textPrimary
                                        : palette.textFaint,
                                    fontSize: 15,
                                  ),
                                ),
                                if (appreciation != null)
                                  Text(
                                    '${appreciation >= 0 ? '▲' : '▼'} ${(appreciation.abs() * 100).toStringAsFixed(1)}% since purchase',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.caption.copyWith(
                                      color: appreciation >= 0
                                          ? AppColors.success
                                          : AppColors.critical,
                                      fontSize: 11.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _StatusPill(status: property.status),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.property, required this.accent});

  final Property property;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final path = property.imagePath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        // A deleted/moved photo must never break the card.
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.32),
            accent.withValues(alpha: 0.12),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(property.type.icon, size: 30, color: accent),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final PropertyStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: AppText.label.copyWith(color: color, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 34, color: palette.textFaint),
          const SizedBox(height: 10),
          Text('No matching properties',
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Try a different search term or filter.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}
