import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_detail_repository.dart';
import '../../models/dashboard_models.dart' show QuickAction;
import '../../models/wallet_detail_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/sections/insights_section.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/wallet/security_center.dart';
import '../../widgets/wallet_detail/detail_header.dart';
import '../../widgets/wallet_detail/detail_overview_card.dart';
import '../../widgets/wallet_detail/document_card.dart';
import '../../widgets/wallet_detail/empty_state.dart';
import '../../widgets/wallet_detail/filter_bar.dart';
import '../../widgets/wallet_detail/recently_accessed_row.dart';
import '../../widgets/wallet_detail/search_section.dart';
import '../../widgets/wallet_detail/storage_analytics_card.dart';
import '../shell/shell_controller.dart';

/// The reusable Wallet Detail screen — the primary document-management surface.
///
/// Opened from the Wallet Hub for ANY wallet ([category]); the structure never
/// changes, only the data from [WalletDetailRepository]. Holds the working list
/// of records plus search / filter / sort state, and wires premium swipe +
/// quick-action interactions. Keeps the shared bottom nav (Wallet active) and
/// the expandable FAB for full ecosystem consistency.
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
  WalletFilter _filter = WalletFilter.all;
  WalletSort _sort = WalletSort.recent;

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

  // ---- Derived list --------------------------------------------------------

  List<DocumentRecord> get _visible {
    bool passFilter(DocumentRecord r) {
      switch (_filter) {
        case WalletFilter.all:
          return true;
        case WalletFilter.active:
          return r.status == DocumentStatus.active;
        case WalletFilter.expiringSoon:
          return r.status == DocumentStatus.expiringSoon;
        case WalletFilter.favorites:
          return r.isFavorite;
        case WalletFilter.shared:
          return r.status == DocumentStatus.shared;
        case WalletFilter.archived:
          return r.status == DocumentStatus.archived;
      }
    }

    final list = _records.where((r) => r.matches(_query) && passFilter(r)).toList();
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

  // ---- Mutations -----------------------------------------------------------

  void _toggleFavorite(DocumentRecord r) {
    setState(() {
      final i = _records.indexWhere((e) => e.id == r.id);
      if (i != -1) {
        _records = [..._records]
          ..[i] = _records[i].copyWith(isFavorite: !_records[i].isFavorite);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _archive(DocumentRecord r) {
    setState(() {
      final i = _records.indexWhere((e) => e.id == r.id);
      if (i != -1) {
        _records = [..._records]
          ..[i] = _records[i].copyWith(status: DocumentStatus.archived);
      }
    });
    _toast('${r.name} archived');
  }

  void _delete(DocumentRecord r) {
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
      leading: Icon(icon, color: danger ? AppColors.critical : AppColors.primaryGreen),
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
                    // Header.
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: DetailHeader(
                          name: widget.category.name,
                          subtitle: data?.subtitle ??
                              'Manage your records securely.',
                          icon: widget.category.icon,
                          gradient: widget.category.gradient,
                          totalDocuments: _records.length,
                          lastUpdatedLabel: data?.lastUpdatedLabel ?? '—',
                          onBack: () => Navigator.of(context).maybePop(),
                          onSearch: () => _searchFocus.requestFocus(),
                          onFilter: _openSort,
                        ),
                      ),
                    ),

                    if (data == null)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      // Overview hero.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: FadeSlideIn(
                            child: DetailOverviewCard(
                              overview: _liveOverview(data),
                              gradient: widget.category.gradient,
                            ),
                          ),
                        ),
                      ),
                      // Sticky search.
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: SearchHeaderDelegate(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          background: palette.bg,
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      // Filters.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: FilterBar(
                            selected: _filter,
                            sort: _sort,
                            onFilter: (f) => setState(() => _filter = f),
                            onSortTap: _openSort,
                          ),
                        ),
                      ),
                      // Documents section header + list / empty state.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: SectionHeader(
                            title: 'Documents',
                            subtitle:
                                '${_visible.length} of ${_records.length} shown',
                            icon: Icons.description_rounded,
                          ),
                        ),
                      ),
                      _documentsSliver(data),
                      // Trailing sections.
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            const SizedBox(height: 16),
                            FadeSlideIn(
                              child: RecentlyAccessedRow(
                                items: data.recents,
                                onOpen: (i) =>
                                    _toast('Opening ${i.name} — coming soon'),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FadeSlideIn(
                                child: InsightsSection(insights: data.insights)),
                            const SizedBox(height: 24),
                            FadeSlideIn(
                                child: SecurityCenter(status: data.security)),
                            const SizedBox(height: 24),
                            FadeSlideIn(
                                child: StorageAnalyticsCard(
                                    storage: data.storage)),
                          ]),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            // Expandable FAB above the floating nav.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                child: ExpandableFab(
                  actions: _detailFabActions,
                  onAction: (a) => _toast('${a.label} — coming soon'),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: InoBottomNav(index: 1, onSelect: _onNavTab),
    );
  }

  /// Overview recomputed from the live record list so counts stay in sync as
  /// the user favorites / archives / deletes.
  DetailOverview _liveOverview(WalletDetailData data) {
    final active =
        _records.where((r) => r.status == DocumentStatus.active).length;
    final expiring =
        _records.where((r) => r.status == DocumentStatus.expiringSoon).length;
    return DetailOverview(
      totalRecords: _records.length,
      activeRecords: active,
      expiringSoon: expiring,
      lastAccessed: data.overview.lastAccessed,
      storageUsedLabel: data.overview.storageUsedLabel,
      storageFraction: data.overview.storageFraction,
    );
  }

  Widget _documentsSliver(WalletDetailData data) {
    final visible = _visible;

    if (visible.isEmpty) {
      final emptyAll = _records.isEmpty;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WalletEmptyState(
            title: emptyAll ? 'No Records Available' : 'No matching records',
            subtitle: emptyAll
                ? 'Start building your digital vault.'
                : 'Try a different filter or search term.',
            onScan: () => _toast('Scan — coming soon'),
            onUpload: () => _toast('Upload — coming soon'),
            onCreate: () => _toast('Create record — coming soon'),
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

// FAB actions for the detail screen (per the brief).
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
      label: 'Upload Image',
      icon: Icons.image_rounded,
      color: Color(0xFF38BDF8)),
  QuickAction(
      label: 'Create Record',
      icon: Icons.note_add_rounded,
      color: AppColors.secondaryGreen),
  QuickAction(
      label: 'Import File',
      icon: Icons.drive_folder_upload_rounded,
      color: Color(0xFF0EA5A5)),
];
