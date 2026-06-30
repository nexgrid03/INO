import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_detail_repository.dart';
import '../../models/dashboard_models.dart' show QuickAction;
import '../../models/wallet_detail_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/wallet_detail/category_chips.dart';
import '../../widgets/wallet_detail/document_card.dart';
import '../../widgets/wallet_detail/document_filter_bar.dart';
import '../../widgets/wallet_detail/document_skeleton.dart';
import '../../widgets/wallet_detail/empty_state.dart';
import '../../widgets/wallet_detail/search_section.dart';
import '../../widgets/wallet_detail/smart_banner.dart';
import '../../widgets/wallet_detail/wallet_header.dart';
import '../../widgets/wallet_detail/wallet_summary_card.dart';
import '../documents/add_document_screen.dart';
import '../shell/shell_controller.dart';

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
    // Document-add actions open Add Document, pre-selecting this wallet.
    const docActions = {'Scan Document', 'Upload PDF', 'Import Image'};
    if (docActions.contains(action.label)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              AddDocumentScreen(initialWallet: widget.category.name),
        ),
      );
      return;
    }
    _toast('${action.label} — coming soon');
  }

  // ---- Derived data --------------------------------------------------------

  /// Category chip labels derived from the wallet's actual records: the distinct
  /// document categories, or — when a wallet holds a single category — the
  /// distinct tags, so the row always resolves to real results.
  List<String> get _categoryChips {
    final cats = <String>{for (final r in _records) r.category};
    if (cats.length > 1) return cats.toList()..sort();
    final tags = <String>{for (final r in _records) ...r.tags};
    return tags.toList()..sort();
  }

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
            _action(Icons.ios_share_rounded, 'Share',
                () => _toast('Share — coming soon')),
            _action(Icons.download_rounded, 'Download',
                () => _toast('Download — coming soon')),
            _action(Icons.edit_rounded, 'Edit',
                () => _toast('Edit — coming soon')),
            _action(
              r.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              r.isFavorite ? 'Remove favorite' : 'Favorite',
              () => _toggleFavorite(r),
            ),
            _action(Icons.drive_file_move_rounded, 'Move',
                () => _toast('Move — coming soon')),
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
            Text('Sort by',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary)),
            const SizedBox(height: 6),
            for (final s in WalletSort.values)
              ListTile(
                title: Text(s.label,
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
    return Scaffold(
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
                          title: widget.category.name,
                          onBack: () => Navigator.of(context).maybePop(),
                          onSearch: () => _searchFocus.requestFocus(),
                          onFilter: _openSort,
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
            // Premium gradient FAB above the floating nav.
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
              lastUpdatedLabel: data.lastUpdatedLabel,
              gradient: widget.category.gradient,
              onViewVault: () => _toast('Vault overview — coming soon'),
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
                actionLabel: 'Renew',
                onAction: () {
                  setState(() => _bannerDismissed = true);
                  _toast('Renew ${attention.name} — coming soon');
                },
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            ),
          ),
        ),
      // 5. Category chips.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 0, 0),
          child: CategoryChips(
            categories: _categoryChips,
            selected: _category,
            onSelected: (c) => setState(() => _category = c),
          ),
        ),
      ),
      // 6. Status filter + sort.
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
                'Documents',
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
            title: emptyAll ? 'No Documents Yet' : 'No matching documents',
            subtitle: emptyAll
                ? 'Start building your digital vault.'
                : 'Try a different category, filter or search term.',
            onScan: () => _onFabAction(_detailFabActions.first),
            onUpload: () => _onFabAction(_detailFabActions[1]),
            onCreate: () => _toast('Create category — coming soon'),
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
              onOpen: () => _toast('Opening ${record.name} — coming soon'),
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
      label: 'Create Folder',
      icon: Icons.create_new_folder_rounded,
      color: AppColors.secondaryGreen),
  QuickAction(
      label: 'Create Category',
      icon: Icons.new_label_rounded,
      color: Color(0xFF0EA5A5)),
];
