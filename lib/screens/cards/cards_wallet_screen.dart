import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/card_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../navigation/wallet_module_router.dart';
import '../../services/card_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/shiny_icon.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import '../shell/shell_controller.dart';
import 'card_form_screen.dart';

/// The Banking Wallet - the user's cards, rendered as cards.
///
/// Tapping a card expands an action row beneath it (View / Copy / Share /
/// Delete) instead of pushing a new screen, so the stack stays the interface.
///
/// SECURITY: nothing here can transact. Only the last four digits are stored,
/// there is no CVV field anywhere in the app, and "Copy" copies those four
/// digits - never a full number, because one was never captured.
class CardsWalletScreen extends StatefulWidget {
  const CardsWalletScreen({super.key, required this.category});

  final WalletCategory category;

  @override
  State<CardsWalletScreen> createState() => _CardsWalletScreenState();
}

class _CardsWalletScreenState extends State<CardsWalletScreen> {
  final _store = CardStore.instance;
  final _searchController = TextEditingController();

  String _query = '';
  CardSort _sort = CardSort.recent;
  CardKind? _kindFilter;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<SavedCard> get _visible {
    final filtered = _store.items
        .where((c) =>
            (_kindFilter == null || c.kind == _kindFilter) && c.matches(_query))
        .toList();
    return _sort.apply(filtered);
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push<SavedCard>(
      MaterialPageRoute(builder: (_) => const CardFormScreen()),
    );
    if (created == null || !mounted) return;
    setState(() => _expandedId = created.id);
    await showSuccessBurst(context, 'Card added');
  }

  Future<void> _edit(SavedCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CardFormScreen(existing: card)),
    );
  }

  Future<void> _delete(SavedCard card) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete card?',
      message:
          '"${card.name}" (•••• ${card.last4}) will be removed from this device.',
    );
    if (!ok || !mounted) return;
    await _store.remove(card.id);
    if (!mounted) return;
    setState(() => _expandedId = null);
    showModuleToast(context, 'Card deleted');
  }

  void _copyLast4(SavedCard card) {
    Clipboard.setData(ClipboardData(text: card.last4));
    HapticFeedback.selectionClick();
    // Deliberately explicit: the user should know only 4 digits exist here.
    showModuleToast(context, 'Last 4 digits copied');
  }

  void _openDocuments() => openWalletDocuments(context, widget.category);

  Future<void> _openSort() async {
    final picked = await showModulePicker(
      context,
      title: 'Sort cards',
      labels: [for (final s in CardSort.values) s.label],
      selectedIndex: CardSort.values.indexOf(_sort),
    );
    if (picked == null || !mounted) return;
    setState(() => _sort = CardSort.values[picked]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasAny = _store.items.isNotEmpty;
    final visible = _visible;
    final attention = _store.needingAttention.length;
    // Match Documents: solid page chrome — no sky wash / glass backdrop.
    final pageBg = palette.isDark ? palette.bg : Colors.white;

    return Scaffold(
      backgroundColor: pageBg,
      extendBody: true,
      body: ColoredBox(
        color: pageBg,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _CardsDocHeader(
                  subtitle: hasAny
                      ? '${_store.count} card${_store.count == 1 ? '' : 's'} · ${_store.countOf(CardKind.credit)} credit · ${_store.countOf(CardKind.debit)} debit'
                      : 'Debit & credit cards',
                  onDocuments: _openDocuments,
                  onAdd: _add,
                ),
              ),
              if (!_store.isLoaded)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: ModuleSkeleton(height: 88, count: 3),
                  ),
                )
              else if (!hasAny)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ModuleEmptyState(
                    icon: Icons.credit_card_rounded,
                    title: 'No cards saved',
                    message:
                        'Keep track of the cards you carry. Only the last four '
                        'digits are stored - never the full number, and never a CVV.',
                    actionLabel: 'Add card',
                    onAction: _add,
                  ),
                )
              else ...[
                if (attention > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 10),
                      child: FadeSlideIn(
                        child: _AttentionBanner(count: attention),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 10),
                    child: _CardsSearchBar(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      onSort: _openSort,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      children: [
                        _DocFilterChip(
                          label: 'All',
                          count: _store.count,
                          selected: _kindFilter == null,
                          onTap: () => setState(() => _kindFilter = null),
                        ),
                        for (final k in CardKind.values)
                          if (_store.countOf(k) > 0) ...[
                            const SizedBox(width: 8),
                            _DocFilterChip(
                              label: k.label,
                              count: _store.countOf(k),
                              selected: _kindFilter == k,
                              onTap: () => setState(() => _kindFilter = k),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cards · ${visible.length} of ${_store.count}',
                            style: AppText.caption.copyWith(
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openSort,
                          icon: Icon(Icons.swap_vert_rounded,
                              size: 18, color: AppColors.primaryGreen),
                          label: Text(
                            'Sort',
                            style: AppText.label.copyWith(
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No cards match this search.',
                          style: AppText.body
                              .copyWith(color: palette.textSecondary),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final card = visible[i];
                        final expanded = _expandedId == card.id;
                        return FadeSlideIn(
                          delay:
                              Duration(milliseconds: (i * 50).clamp(0, 300)),
                          offset: 12,
                          child: Column(
                            children: [
                              _CardDocTile(
                                card: card,
                                selected: expanded,
                                onTap: () => setState(() {
                                  HapticFeedback.selectionClick();
                                  _expandedId =
                                      expanded ? null : card.id;
                                }),
                                onFavorite: () =>
                                    _store.toggleFavorite(card.id),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: expanded
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: _CardActions(
                                          onView: () => _edit(card),
                                          onCopy: () => _copyLast4(card),
                                          onEdit: () => _edit(card),
                                          onDelete: () => _delete(card),
                                        ),
                                      )
                                    : const SizedBox(width: double.infinity),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 18)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: palette.isDark
                            ? palette.surfaceVariant
                            : AppColors.tealFoam,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: palette.isDark
                              ? palette.border
                              : AppColors.tealPale.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_user_outlined,
                              size: 16, color: AppColors.primaryGreen),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Only the last 4 digits are stored on this device. '
                              'No CVV, ever.',
                              textAlign: TextAlign.center,
                              style: AppText.caption.copyWith(
                                  color: palette.textSecondary,
                                  fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: hasAny
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: GradientButton(
                label: 'Add card',
                icon: Icons.add_rounded,
                expand: false,
                onTap: _add,
              ),
            )
          : null,
      bottomNavigationBar: InoBottomNav(
        index: 1,
        onSelect: (i) {
          if (i == 1) return;
          ShellController.tab.value = i;
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
      ),
    );
  }
}

/// Documents-style solid header (no frosted glass app bar).
class _CardsDocHeader extends StatelessWidget {
  const _CardsDocHeader({
    required this.subtitle,
    required this.onDocuments,
    required this.onAdd,
  });

  final String subtitle;
  final VoidCallback onDocuments;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          InoBackButton(size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Cards',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          ModuleIconButton(
            icon: Icons.folder_shared_rounded,
            tooltip: 'Banking documents',
            color: AppColors.primaryGreen,
            size: 46,
            iconSize: 26,
            onTap: onDocuments,
          ),
          const SizedBox(width: 8),
          ModuleIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Add card',
            color: AppColors.primaryGreen,
            size: 46,
            iconSize: 28,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

/// Solid white search field matching Documents [DetailSearchBar] classic mode.
class _CardsSearchBar extends StatelessWidget {
  const _CardsSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onSort,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: palette.isDark ? palette.surface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.search),
        border: Border.all(color: palette.border),
        boxShadow: palette.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, size: 21, color: palette.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppText.body.copyWith(color: palette.textPrimary),
              cursorColor: AppColors.primaryGreen,
              decoration: InputDecoration(
                hintText: 'Search cards',
                hintStyle: AppText.body.copyWith(color: palette.textFaint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ModuleIconButton(
            icon: Icons.swap_vert_rounded,
            tooltip: 'Sort',
            size: 34,
            onTap: onSort,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// Documents [DocumentFilterBar]-style chip with vault gradient when selected.
class _DocFilterChip extends StatelessWidget {
  const _DocFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.94,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? null
                  : (palette.isDark ? palette.surface : Colors.white),
              gradient: selected ? AppColors.vaultFillGradient(accent) : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? Colors.transparent : palette.border,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$label $count',
              style: AppText.label.copyWith(
                color: selected ? Colors.white : palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Documents-style list row for a saved card (solid white, not glass).
class _CardDocTile extends StatelessWidget {
  const _CardDocTile({
    required this.card,
    required this.onTap,
    required this.onFavorite,
    this.selected = false,
  });

  final SavedCard card;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = card.theme.top;
    final title = card.bank.isEmpty ? card.name : card.bank;
    final statusLabel = card.isExpired
        ? 'Expired'
        : (card.isExpiringSoon ? 'Expiring soon' : card.kind.label);
    final statusColor = card.isExpired
        ? AppColors.critical
        : (card.isExpiringSoon ? AppColors.warning : AppColors.primaryGreen);

    return PressableScale(
      child: Material(
        color: palette.isDark ? palette.surface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected ? AppColors.primaryGreen : palette.border,
                width: selected ? 1.4 : 1,
              ),
              boxShadow: palette.isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ShinyIcon(
                        icon: Icons.credit_card_rounded,
                        color: accent,
                        size: 46,
                        iconSize: 23,
                        radius: 13,
                      ),
                      if (card.isFavorite)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              size: 13,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '•••• ${card.last4} · ${card.network.label}'
                          '${card.holderName.isEmpty ? '' : ' · ${card.holderName}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            statusLabel,
                            style: AppText.label.copyWith(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onFavorite,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      card.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 20,
                      color: card.isFavorite
                          ? AppColors.warning
                          : palette.textFaint,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: palette.textFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A saved card drawn as a real card: bank, network badge, masked number,
/// holder and expiry over the theme gradient.
class BankCardFace extends StatelessWidget {
  const BankCardFace({
    super.key,
    required this.card,
    required this.onTap,
    this.onFavorite,
    this.showFavorite = true,
  });

  final SavedCard card;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = card.theme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AspectRatio(
        aspectRatio: 1.62, // the real card ratio
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: theme.gradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: theme.bottom.withValues(alpha: 0.34),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Soft light sweep across the face.
              Positioned(
                top: -60,
                right: -30,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.18),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.bank.isEmpty ? card.name : card.bank,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title.copyWith(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${card.kind.label.toUpperCase()} · ${card.network.label.toUpperCase()}',
                                maxLines: 1,
                                softWrap: false,
                                style: AppText.label.copyWith(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // The masked number: four groups, only the last real.
                    Row(
                      children: [
                        for (var g = 0; g < 3; g++) ...[
                          Row(
                            children: List.generate(
                              4,
                              (_) => Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.88),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          card.last4,
                          style: AppText.title.copyWith(
                            color: Colors.white,
                            fontSize: 19,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CARD HOLDER',
                                style: AppText.label.copyWith(
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: 8.5,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                card.holderName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.subtitle.copyWith(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EXPIRES',
                              style: AppText.label.copyWith(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 8.5,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              card.expiryLabel,
                              style: AppText.subtitle.copyWith(
                                color: card.isExpired
                                    ? const Color(0xFFFFD5D5)
                                    : Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        _NetworkMark(network: card.network),
                      ],
                    ),
                  ],
                ),
              ),
              // Expiry warning + favourite live in the top-left/right gutters.
              if (card.isExpired || card.isExpiringSoon)
                Positioned(
                  left: 18,
                  top: 44,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      card.isExpired ? 'EXPIRED' : 'EXPIRING SOON',
                      style: AppText.label.copyWith(
                        color: const Color(0xFFFFE2A8),
                        fontSize: 8.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              if (showFavorite && onFavorite != null)
                Positioned(
                  right: 10,
                  bottom: 8,
                  child: IconButton(
                    onPressed: onFavorite,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      card.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: Colors.white.withValues(
                          alpha: card.isFavorite ? 1 : 0.55),
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

/// The network mark. Drawn from primitives rather than shipping brand logos -
/// the app has no licence to redistribute those.
class _NetworkMark extends StatelessWidget {
  const _NetworkMark({required this.network});

  final CardNetwork network;

  @override
  Widget build(BuildContext context) {
    switch (network) {
      case CardNetwork.mastercard:
        return SizedBox(
          width: 40,
          height: 24,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                child: _dot(const Color(0xFFEB5C4A)),
              ),
              Positioned(
                left: 14,
                child: _dot(const Color(0xFFF7A600)),
              ),
            ],
          ),
        );
      case CardNetwork.visa:
      case CardNetwork.rupay:
      case CardNetwork.amex:
      case CardNetwork.discover:
      case CardNetwork.diners:
      case CardNetwork.other:
        return Text(
          network == CardNetwork.other ? 'CARD' : network.label.toUpperCase(),
          style: AppText.title.copyWith(
            color: Colors.white,
            fontSize: 14,
            fontStyle: FontStyle.italic,
            letterSpacing: 1.1,
          ),
        );
    }
  }

  Widget _dot(Color color) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
      );
}

/// The row that slides out under an expanded card.
class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.onView,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onView;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Action(icon: Icons.visibility_rounded, label: 'View', onTap: onView),
        const SizedBox(width: 8),
        _Action(icon: Icons.copy_rounded, label: 'Copy No.', onTap: onCopy),
        const SizedBox(width: 8),
        _Action(icon: Icons.edit_rounded, label: 'Edit', onTap: onEdit),
        const SizedBox(width: 8),
        _Action(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: onDelete,
          danger: true,
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = danger ? AppColors.critical : palette.textPrimary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: color, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count card${count == 1 ? '' : 's'} expired or expiring within 60 days',
              style: AppText.caption.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
