import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_detail_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart' show QuickAction;
import '../../models/wallet_detail_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../services/document_protection_store.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/documents/create_category_sheet.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/wallet_detail/document_card.dart';
import '../../widgets/wallet_detail/document_filter_bar.dart';
import '../../widgets/wallet_detail/document_skeleton.dart';
import '../../widgets/wallet_detail/empty_state.dart';
import '../../widgets/wallet_detail/search_section.dart';
import '../../widgets/wallet_detail/smart_banner.dart';
import '../../widgets/wallet_detail/wallet_header.dart';
import '../../widgets/wallet_detail/wallet_summary_card.dart';
import '../documents/add_document_screen.dart';
import '../property/area_converter_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../share/manage_shares_screen.dart';
import '../share/share_config_screen.dart';
import '../shell/shell_controller.dart';
import 'document_viewer_screen.dart';

/// The reusable Wallet Detail screen — a premium *document manager*, not a
/// dashboard.
///
/// Opened from the Wallet Hub for ANY wallet ([category]); the structure never
/// changes, only the data from [WalletDetailRepository]. Everything above the
/// document list is one-tap-tall and exists only to help the user find, open,
/// upload, scan or share a document: a compact header, a sticky search field, a
/// 4-fact summary card, an attention-only smart banner, category chips and a
/// status filter. The list itself owns the screen. Keeps the shared bottom nav
/// (Wallet active) and the gradient FAB for ecosystem consistency.
class WalletDetailScreen extends StatefulWidget {
  const WalletDetailScreen({super.key, required this.category});

  final WalletCategory category;

  @override
  State<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends State<WalletDetailScreen> {
  late Future<WalletDetailData> _future;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  // Working state.
  List<DocumentRecord> _records = const [];
  String _query = '';
  String? _category; // null = "All" category chip
  WalletFilter _filter = WalletFilter.all;
  WalletSort _sort = WalletSort.recent;
  bool _bannerDismissed = false;

  // Multi-select state for "Share via QR".
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  // The brief's focused status filter set (Recent lives inside Sort).
  static const _filters = <WalletFilter>[
    WalletFilter.all,
    WalletFilter.favorites,
    WalletFilter.expiringSoon,
    WalletFilter.archived,
  ];

  @override
  void initState() {
    super.initState();
    _future = WalletDetailRepository.instance.load(widget.category).then((data) {
      _records = data.records;
      return data;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  void _onFabAction(QuickAction action) {
    // Scan opens the dedicated Scan & OCR flow, pre-selecting this wallet.
    if (action.label == 'Scan Document') {
      launchScanFlow(context, initialWallet: widget.category.name);
      return;
    }
    if (action.label == 'Create Category') {
      _createCategory();
      return;
    }
    // Upload actions go straight to Add Document, pre-selecting this wallet.
    const uploadActions = {'Upload PDF', 'Import Image'};
    if (uploadActions.contains(action.label)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              AddDocumentScreen(initialWallet: widget.category.name),
        ),
      );
      return;
    }
    // Every other action opens Add Document as a safe default.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddDocumentScreen(initialWallet: widget.category.name),
      ),
    );
  }

  /// Opens the Create Category sheet; the new category becomes selectable when
  /// adding documents.
  Future<void> _createCategory() async {
    final created = await showCreateCategorySheet(context);
    if (created == null || !mounted) return;
    _toast('Category “${created.name}” created');
  }

  // ---- Derived data --------------------------------------------------------

  bool _matchesCategory(DocumentRecord r) {
    if (_category == null) return true;
    final c = _category!.toLowerCase();
    return r.category.toLowerCase() == c ||
        r.tags.any((t) => t.toLowerCase() == c);
  }

  List<DocumentRecord> get _visible {
    bool passFilter(DocumentRecord r) {
      switch (_filter) {
        case WalletFilter.all:
          return true;
        case WalletFilter.active:
          return r.status == DocumentStatus.active;
        case WalletFilter.expiringSoon:
          return r.status == DocumentStatus.expiringSoon ||
              r.status == DocumentStatus.expired;
        case WalletFilter.favorites:
          return r.isFavorite;
        case WalletFilter.shared:
          return r.status == DocumentStatus.shared;
        case WalletFilter.archived:
          return r.status == DocumentStatus.archived;
      }
    }

    final list = _records
        .where((r) => r.matches(_query) && _matchesCategory(r) && passFilter(r))
        .toList();
    switch (_sort) {
      case WalletSort.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case WalletSort.az:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case WalletSort.uploadDate:
        list.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
        break;
      case WalletSort.expiryDate:
        list.sort((a, b) {
          final ae = a.expiresAt;
          final be = b.expiresAt;
          if (ae == null && be == null) return 0;
          if (ae == null) return 1;
          if (be == null) return -1;
          return ae.compareTo(be);
        });
        break;
    }
    return list;
  }

  /// The single record (if any) that should drive the smart banner: the
  /// soonest-expiring document in the wallet.
  DocumentRecord? get _attentionRecord {
    final expiring = _records
        .where((r) =>
            r.status == DocumentStatus.expiringSoon ||
            r.status == DocumentStatus.expired)
        .toList()
      ..sort((a, b) {
        final ae = a.expiresAt;
        final be = b.expiresAt;
        if (ae == null && be == null) return 0;
        if (ae == null) return 1;
        if (be == null) return -1;
        return ae.compareTo(be);
      });
    return expiring.isEmpty ? null : expiring.first;
  }

  String _bannerMessage(DocumentRecord r) {
    final exp = r.expiresAt;
    if (exp == null) return '${r.name} needs your attention';
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return '${r.name} has expired';
    if (days == 0) return '${r.name} expires today';
    return '${r.name} expires in $days day${days == 1 ? '' : 's'}';
  }

  // ---- Mutations -----------------------------------------------------------

  void _toggleFavorite(DocumentRecord r) {
    final updated = r.copyWith(isFavorite: !r.isFavorite);
    WalletDetailRepository.instance.updateRecord(widget.category.name, updated);
    setState(() {
      final i = _records.indexWhere((e) => e.id == r.id);
      if (i != -1) {
        _records = [..._records]..[i] = updated;
      }
    });
    HapticFeedback.selectionClick();
  }

  void _archive(DocumentRecord r) {
    final updated = r.copyWith(status: DocumentStatus.archived);
    WalletDetailRepository.instance.updateRecord(widget.category.name, updated);
    setState(() {
      final i = _records.indexWhere((e) => e.id == r.id);
      if (i != -1) {
        _records = [..._records]..[i] = updated;
      }
    });
    _toast('${r.name} archived');
  }

  void _delete(DocumentRecord r) {
    WalletDetailRepository.instance.deleteRecord(widget.category.name, r.id);
    setState(() => _records = _records.where((e) => e.id != r.id).toList());
    _toast('${r.name} deleted');
  }

  // ---- Multi-select & Share via QR ----------------------------------------

  void _enterSelection(DocumentRecord r) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selectedIds.add(r.id);
    });
  }

  void _toggleSelect(DocumentRecord r) {
    setState(() {
      // remove() returns true when it was present (and removed it).
      if (!_selectedIds.remove(r.id)) _selectedIds.add(r.id);
      if (_selectedIds.isEmpty) _selecting = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  /// Card tap: toggles selection while selecting, otherwise opens the document.
  void _onCardTap(DocumentRecord r) =>
      _selecting ? _toggleSelect(r) : _openDocument(r);

  /// Card long-press: enters selection (or toggles when already selecting).
  void _onCardLongPress(DocumentRecord r) =>
      _selecting ? _toggleSelect(r) : _enterSelection(r);

  /// True for the Property wallet, which gets the extra Area Converter action.
  bool get _isPropertyWallet => widget.category.name == 'Property Wallet';

  /// Opens the Property Area Converter tool (a pure calculator — touches no
  /// documents, so it can't affect existing property data).
  void _openAreaConverter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AreaConverterScreen()),
    );
  }

  void _shareSelected() =>
      _startShare(_records.where((r) => _selectedIds.contains(r.id)).toList());

  void _shareSingle(DocumentRecord r) => _startShare([r]);

  /// Opens the Share Configuration flow for [docs]. Only documents with an
  /// uploaded file can be shared; any without one are skipped (never fabricated).
  void _startShare(List<DocumentRecord> docs) {
    final shareable = docs.where((r) => r.filePath != null).toList();
    final skipped = docs.length - shareable.length;
    if (shareable.isEmpty) {
      _toast('These documents have no uploaded file to share yet');
      return;
    }
    if (skipped > 0) {
      _toast('$skipped document${skipped == 1 ? '' : 's'} without a file skipped');
    }
    _exitSelection();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShareConfigScreen(documents: shareable)),
    );
  }

  void _openManageShares() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManageSharesScreen()),
    );
  }

  // ---- Biometric protection ------------------------------------------------

  /// Opens a document in the full viewer — gating protected ones behind the
  /// native biometric prompt first. Never reveals the document before a
  /// successful unlock; a cancel simply returns the user to the list. Changes
  /// made inside the viewer (favorite / rename / archive / delete / move) are
  /// applied back to the list on return.
  Future<void> _openDocument(DocumentRecord r) async {
    final isProtected = DocumentProtectionStore.instance.isProtected(r.id);
    if (isProtected) {
      final unlocked = await VaultGuard.instance.ensureUnlocked(
        context,
        reason: 'Authenticate to access this protected document.',
        title: AppLocalizations.of(context).t('verifyIdentity'),
      );
      if (!unlocked || !mounted) return;
    }
    final result = await Navigator.of(context).push<DocumentViewerResult>(
      MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(
          record: r,
          walletName: widget.category.name,
          accent: widget.category.gradient,
          protected: isProtected,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.removed) {
        _records = _records.where((e) => e.id != r.id).toList();
      } else if (result.updated != null) {
        final i = _records.indexWhere((e) => e.id == r.id);
        if (i != -1) _records = [..._records]..[i] = result.updated!;
      }
    });
  }

  /// Toggles per-document biometric protection. Changing a security setting is
  /// itself sensitive, so it requires a successful prompt first.
  Future<void> _toggleProtection(DocumentRecord r) async {
    final isProtected = DocumentProtectionStore.instance.isProtected(r.id);
    final unlocked = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: isProtected
          ? 'Authenticate to remove protection from this document.'
          : 'Authenticate to protect this document.',
      title: 'Verify your identity',
    );
    if (!unlocked || !mounted) return;
    await DocumentProtectionStore.instance.setProtected(r.id, !isProtected);
    if (!mounted) return;
    setState(() {}); // refresh the lock badge
    _toast(isProtected
        ? '${r.name} is no longer protected'
        : '${r.name} is now protected');
  }

  // ---- Action sheets -------------------------------------------------------

  void _openActions(DocumentRecord r) {
    final palette = AppPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Icon(r.icon, color: AppColors.primaryGreen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _action(Icons.open_in_full_rounded, 'Open', () => _openDocument(r)),
            _action(Icons.qr_code_2_rounded, 'Share via QR',
                () => _shareSingle(r)),
            _action(
              DocumentProtectionStore.instance.isProtected(r.id)
                  ? Icons.lock_open_rounded
                  : Icons.lock_rounded,
              DocumentProtectionStore.instance.isProtected(r.id)
                  ? 'Remove protection'
                  : 'Protect with Biometrics',
              () => _toggleProtection(r),
            ),
            _action(
              r.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              r.isFavorite ? 'Remove favorite' : 'Favorite',
              () => _toggleFavorite(r),
            ),
            _action(Icons.archive_rounded, 'Archive', () => _archive(r)),
            _action(Icons.delete_outline_rounded, 'Delete',
                () => _delete(r), danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final palette = AppPalette.of(context);
    final color = danger ? AppColors.critical : palette.textPrimary;
    return ListTile(
      leading: Icon(icon,
          color: danger ? AppColors.critical : AppColors.primaryGreen),
      title: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  void _openSort() {
    final palette = AppPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(AppLocalizations.of(context).t('sortBy'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary)),
            const SizedBox(height: 6),
            for (final s in WalletSort.values)
              ListTile(
                title: Text(s.localizedLabel(AppLocalizations.of(context)),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight:
                          s == _sort ? FontWeight.w700 : FontWeight.w500,
                    )),
                trailing: s == _sort
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.primaryGreen)
                    : null,
                onTap: () {
                  setState(() => _sort = s);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onNavTab(int i) {
    ShellController.tab.value = i;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopScope(
      // While selecting, the system back gesture first exits selection mode.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              FutureBuilder<WalletDetailData>(
                future: _future,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      // 1. Compact header.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: WalletHeader(
                            title: localizedWalletName(
                                AppLocalizations.of(context),
                                widget.category.name),
                            onBack: () => Navigator.of(context).maybePop(),
                            onSearch: () => _searchFocus.requestFocus(),
                            onFilter: _openSort,
                            onManageShares: _openManageShares,
                            onAreaConverter:
                                _isPropertyWallet ? _openAreaConverter : null,
                          ),
                        ),
                      ),
                      if (data == null)
                        _loadingSliver()
                      else
                        ..._loadedSlivers(data),
                    ],
                  );
                },
              ),
              // The selection action bar takes over from the FAB while the user
              // is multi-selecting documents to share.
              if (_selecting)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _SelectionBar(
                    count: _selectedIds.length,
                    onCancel: _exitSelection,
                    onShare: _shareSelected,
                  ),
                )
              else
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    child: ExpandableFab(
                      actions: _detailFabActions,
                      onAction: _onFabAction,
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: InoBottomNav(index: 1, onSelect: _onNavTab),
      ),
    );
  }

  Widget _loadingSliver() {
    return const SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 120),
      sliver: SliverToBoxAdapter(
        child: Column(
          children: [
            SummarySkeleton(),
            SizedBox(height: 24),
            DocumentSkeleton(),
          ],
        ),
      ),
    );
  }

  List<Widget> _loadedSlivers(WalletDetailData data) {
    final palette = AppPalette.of(context);
    final attention = _attentionRecord;
    final showBanner = attention != null && !_bannerDismissed;
    final expiring = _records
        .where((r) =>
            r.status == DocumentStatus.expiringSoon ||
            r.status == DocumentStatus.expired)
        .length;

    return [
      // 2. Sticky search.
      SliverPersistentHeader(
        pinned: true,
        delegate: SearchHeaderDelegate(
          controller: _searchController,
          focusNode: _searchFocus,
          background: palette.bg,
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      // 3. Compact summary card.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: FadeSlideIn(
            child: WalletSummaryCard(
              totalDocuments: _records.length,
              expiring: expiring,
              protected: data.security.vaultLocked,
            ),
          ),
        ),
      ),
      // 4. Smart banner (only when something needs attention).
      if (showBanner)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: FadeSlideIn(
              child: SmartBanner(
                message: _bannerMessage(attention),
                icon: Icons.warning_amber_rounded,
                accent: AppColors.warning,
                actionLabel: 'Open',
                onAction: () {
                  setState(() => _bannerDismissed = true);
                  _openDocument(attention);
                },
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            ),
          ),
        ),
      // 5. Status filter + sort (single row).
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: DocumentFilterBar(
            filters: _filters,
            selected: _filter,
            sort: _sort,
            onFilter: (f) => setState(() => _filter = f),
            onSortTap: _openSort,
          ),
        ),
      ),
      // 7. Documents — the primary focus.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context).t('documents'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_visible.length} of ${_records.length}',
                style: TextStyle(fontSize: 12, color: palette.textFaint),
              ),
            ],
          ),
        ),
      ),
      _documentsSliver(),
      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ];
  }

  Widget _documentsSliver() {
    final visible = _visible;

    if (visible.isEmpty) {
      final emptyAll = _records.isEmpty;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WalletEmptyState(
            title: emptyAll
                ? AppLocalizations.of(context).t('noDocumentsYet')
                : 'No matching documents',
            subtitle: emptyAll
                ? 'Start building your digital vault.'
                : 'Try a different category, filter or search term.',
            onScan: () => _onFabAction(_detailFabActions.first),
            onUpload: () => _onFabAction(_detailFabActions[1]),
            onCreate: _createCategory,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i.isOdd) return const SizedBox(height: 10);
            final record = visible[i ~/ 2];
            return DocumentCard(
              record: record,
              accent: widget.category.gradient,
              protected: DocumentProtectionStore.instance.isProtected(record.id),
              selectionMode: _selecting,
              selected: _selectedIds.contains(record.id),
              onOpen: () => _onCardTap(record),
              onLongPress: () => _onCardLongPress(record),
              onFavorite: () => _toggleFavorite(record),
              onMore: () => _openActions(record),
            );
          },
          childCount: visible.length * 2 - 1,
        ),
      ),
    );
  }
}

/// The floating action bar shown while multi-selecting documents to share.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onShare,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final enabled = count > 0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onCancel,
                icon: Icon(Icons.close_rounded, color: palette.textPrimary),
                tooltip: l10n.t('cancel'),
              ),
              Expanded(
                child: Text(
                  l10n.t('selectedCount').replaceAll('{n}', '$count'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              PressableScale(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color:
                                  AppColors.primaryGreen.withValues(alpha: 0.32),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  foregroundDecoration: enabled
                      ? null
                      : BoxDecoration(
                          color: palette.bg.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: enabled ? onShare : null,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_2_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(l10n.t('shareViaQr'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
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

// FAB actions for the document manager (per the brief).
const List<QuickAction> _detailFabActions = [
  QuickAction(
      label: 'Scan Document',
      icon: Icons.document_scanner_rounded,
      color: AppColors.primaryGreen),
  QuickAction(
      label: 'Upload PDF',
      icon: Icons.picture_as_pdf_rounded,
      color: AppColors.lightBlue),
  QuickAction(
      label: 'Import Image',
      icon: Icons.image_rounded,
      color: Color(0xFF38BDF8)),
  QuickAction(
      label: 'Create Category',
      icon: Icons.new_label_rounded,
      color: Color(0xFF0EA5A5)),
];
