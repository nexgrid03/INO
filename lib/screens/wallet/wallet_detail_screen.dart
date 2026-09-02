import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_detail_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/document.dart';
import '../../models/dashboard_models.dart' show QuickAction;
import '../../models/wallet_detail_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../repositories/document_repository.dart';
import '../../services/document_protection_store.dart';
import '../../services/offline_document_store.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/documents/create_category_sheet.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/shell/quick_actions.dart';
import '../../widgets/wallet_detail/document_card.dart';
import '../../widgets/wallet_detail/document_filter_bar.dart';
import '../../widgets/wallet_detail/document_quick_view.dart';
import '../../widgets/wallet_detail/document_skeleton.dart';
import '../../widgets/wallet_detail/category_chips.dart';
import '../../widgets/wallet_detail/empty_state.dart';
import '../../widgets/wallet_detail/search_section.dart';
import '../../widgets/wallet_detail/smart_banner.dart';
import '../../widgets/wallet_detail/wallet_header.dart';
import '../../widgets/wallet_detail/wallet_summary_card.dart';
import '../documents/add_document_screen.dart';
import '../property/area_converter_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../share/manage_shares_screen.dart';
import '../share/share_settings_screen.dart';
import '../shell/shell_controller.dart';
import 'document_viewer_screen.dart';

/// The reusable Wallet Detail screen - a premium *document manager*, not a
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

  /// Theme brand for in-wallet chrome / icons (Home hub tiles keep vault accents).
  Color get _vaultAccent => AppColors.primaryGreen;

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
    // Hydrate the offline library (local read) so the action sheet can show
    // "Save to app" vs "Remove offline copy" correctly on first open.
    OfflineDocumentStore.instance.ensureLoaded();
    _future = _loadFuture();
  }

  /// Last successfully loaded payload. Shown while a reload is in flight so
  /// the list never blanks back to the skeleton after a scan / upload / back
  /// navigation — only the very first load shows the skeleton.
  WalletDetailData? _lastData;

  Future<WalletDetailData> _loadFuture() {
    return WalletDetailRepository.instance.load(widget.category).then((data) {
      _records = data.records;
      _lastData = data;
      return data;
    });
  }

  void _reload() {
    setState(() {
      _future = _loadFuture();
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
        backgroundColor: _vaultAccent,
      ),
    );
  }

  Future<void> _onFabAction(QuickAction action) async {
    // Scan opens the dedicated Scan & OCR flow, pre-selecting this wallet.
    if (action.label == 'Scan Document') {
      await launchScanFlow(context, initialWallet: widget.category.name);
      if (mounted) _reload();
      return;
    }
    if (action.label == 'Create Category') {
      await _createCategory();
      return;
    }
    // Upload / health-record actions go straight to Add Document.
    const uploadActions = {'Upload PDF', 'Import Image', 'Add Health Record'};
    if (uploadActions.contains(action.label)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              AddDocumentScreen(initialWallet: widget.category.name),
        ),
      );
      if (mounted) _reload();
      return;
    }
    // Every other action opens Add Document as a safe default.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddDocumentScreen(initialWallet: widget.category.name),
      ),
    );
    if (mounted) _reload();
  }

  /// Opens the Create Category sheet; the new category becomes selectable when
  /// adding documents.
  Future<void> _createCategory() async {
    final created = await showCreateCategorySheet(context);
    if (created == null || !mounted) return;
    setState(() => _category = created.name);
    _toast(AppLocalizations.of(context)
        .t('categoryCreated')
        .replaceAll('{name}', created.name));
  }

  // ---- Derived data --------------------------------------------------------

  bool get _isHealthWallet => widget.category.name == 'Health Wallet';

  bool get _isPropertyWallet => widget.category.name == 'Property Wallet';

  List<QuickAction> get _fabActionsForWallet {
    final scan = QuickAction(
      label: 'Scan Document',
      icon: Icons.document_scanner_rounded,
      color: _vaultAccent,
    );
    final rest = _detailFabActions.skip(1);
    if (!_isHealthWallet) return [scan, ...rest];
    return [
      QuickAction(
        label: 'Add Health Record',
        icon: Icons.medical_services_rounded,
        color: _vaultAccent,
      ),
      ...rest,
    ];
  }

  /// Category chips: wallet folder labels plus any categories present on records.
  List<String> get _categoryChips {
    final labels = <String>{
      ...widget.category.contents,
      for (final r in _records)
        if (r.category.trim().isNotEmpty) r.category.trim(),
    };
    final list = labels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  bool _matchesCategory(DocumentRecord r) {
    if (_category == null) return true;
    final c = _category!.toLowerCase().trim();
    final rc = r.category.toLowerCase().trim();
    if (rc == c) return true;
    if (r.tags.any((t) => t.toLowerCase().trim() == c)) return true;
    // Soft match so "Medical Records" still hits category "Medical".
    if (rc.isNotEmpty && (rc.contains(c) || c.contains(rc))) return true;
    return false;
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
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
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
    final expiring =
        _records
            .where(
              (r) =>
                  r.status == DocumentStatus.expiringSoon ||
                  r.status == DocumentStatus.expired,
            )
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
    final l10n = AppLocalizations.of(context);
    String named(String key) => l10n.t(key).replaceAll('{name}', r.name);
    final exp = r.expiresAt;
    if (exp == null) return named('needsYourAttentionName');
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return named('hasExpiredName');
    if (days == 0) return named('expiresTodayName');
    if (days == 1) return named('expiresInOneDayName');
    return named('expiresInDaysName').replaceAll('{n}', '$days');
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
    _toast(AppLocalizations.of(context)
        .t('archivedName')
        .replaceAll('{name}', r.name));
  }

  void _delete(DocumentRecord r) {
    WalletDetailRepository.instance.deleteRecord(widget.category.name, r.id);
    setState(() => _records = _records.where((e) => e.id != r.id).toList());
    _toast(AppLocalizations.of(context)
        .t('deletedName')
        .replaceAll('{name}', r.name));
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

  /// Opens the Property Area Converter tool (a pure calculator - touches no
  /// documents, so it can't affect existing property data).
  void _openAreaConverter() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AreaConverterScreen()));
  }

  void _shareSelected() =>
      _startShare(_records.where((r) => _selectedIds.contains(r.id)).toList());

  void _shareSingle(DocumentRecord r) => _startShare([r]);

  /// Opens the Secure Share portal for [docs].
  ///
  /// Always navigates to [ShareSettingsScreen] (the portal). File paths are
  /// refreshed first so Generate Secure Link can succeed when Storage has the
  /// file even if the in-memory list was stale.
  Future<void> _startShare(List<DocumentRecord> docs) async {
    if (docs.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      ),
    );

    List<DocumentRecord> hydrated;
    try {
      hydrated = await _hydrateShareDocs(docs);
    } catch (_) {
      hydrated = docs;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;

    if (hydrated.any((d) => d.hasUploadedFile)) {
      setState(() {
        _records = [
          for (final r in _records)
            hydrated.firstWhere((h) => h.id == r.id, orElse: () => r),
        ];
      });
    }

    _exitSelection();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareSettingsScreen(documents: hydrated),
      ),
    );
  }

  /// Prefer live DB `file_path`, then offline object path, then the list value.
  Future<List<DocumentRecord>> _hydrateShareDocs(
    List<DocumentRecord> docs,
  ) async {
    final wallet = widget.category.name;
    final offline = OfflineDocumentStore.instance;
    final byId = <String, Document>{};

    try {
      final freshList = await DocumentRepository.instance.listForWallet(
        wallet,
        forceRefresh: true,
      );
      for (final d in freshList) {
        byId[d.id] = d;
      }
    } catch (_) {}

    final out = <DocumentRecord>[];
    for (final doc in docs) {
      String? path = doc.hasUploadedFile ? doc.filePath!.trim() : null;

      final listed = byId[doc.id];
      if ((path == null || path.isEmpty) &&
          listed != null &&
          listed.hasUploadedFile) {
        path = listed.filePath!.trim();
      }

      if (path == null || path.isEmpty) {
        final fresh = await DocumentRepository.instance.getById(
          doc.id,
          wallet: wallet,
        );
        if (fresh != null && fresh.hasUploadedFile) {
          path = fresh.filePath!.trim();
        }
      }

      if (path == null || path.isEmpty) {
        final offlineDoc = offline.byId(doc.id);
        final offlinePath = offlineDoc?.objectPath.trim();
        if (offlinePath != null && offlinePath.isNotEmpty) {
          path = offlinePath;
          // Persist recovered path so future share / open use the DB.
          DocumentRepository.instance
              .update(doc.id, {'file_path': path}, wallet: wallet)
              .catchError((_) {});
        }
      }

      out.add(
        (path == null || path.isEmpty) ? doc : doc.copyWith(filePath: path),
      );
    }
    return out;
  }

  void _openManageShares() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManageSharesScreen()));
  }

  // ---- Biometric protection ------------------------------------------------

  /// Opens a document in the full viewer - gating protected ones behind the
  /// native biometric prompt first. Never reveals the document before a
  /// successful unlock; a cancel simply returns the user to the list. Changes
  /// made inside the viewer (favorite / rename / archive / delete / move) are
  /// applied back to the list on return.
  Future<void> _openDocument(DocumentRecord r) async {
    final isProtected = DocumentProtectionStore.instance.isProtected(r.id);
    if (isProtected) {
      final unlocked = await VaultGuard.instance.ensureUnlocked(
        context,
        reason: AppLocalizations.of(context).t('authProtectedDocReason'),
        title: AppLocalizations.of(context).t('verifyIdentity'),
      );
      if (!unlocked || !mounted) return;
    }
    // If the document carries OCR-extracted data, peek at it in a Quick View
    // first - the user shouldn't need to open the full file every time (#6).
    final isHealth = _isHealthWallet;
    if ((r.extraction.hasData || isHealth) && mounted) {
      await showDocumentQuickView(
        context,
        record: r,
        accent: widget.category.gradient,
        onOpenFull: () => _openViewer(r, isProtected),
        isHealth: isHealth,
      );
      return;
    }
    await _openViewer(r, isProtected);
  }

  /// Pushes the full document viewer and applies any changes back to the list.
  Future<void> _openViewer(DocumentRecord r, bool isProtected) async {
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
    final l10n = AppLocalizations.of(context);
    final isProtected = DocumentProtectionStore.instance.isProtected(r.id);
    final unlocked = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: isProtected
          ? l10n.t('authRemoveProtectionReason')
          : l10n.t('authProtectDocReason'),
      title: l10n.t('verifyIdentity'),
    );
    if (!unlocked || !mounted) return;
    await DocumentProtectionStore.instance.setProtected(r.id, !isProtected);
    if (!mounted) return;
    setState(() {}); // refresh the lock badge
    _toast(
      AppLocalizations.of(context)
          .t(isProtected ? 'noLongerProtected' : 'nowProtectedName')
          .replaceAll('{name}', r.name),
    );
  }

  /// Saves this document's durable offline copy (or removes it). Saving from
  /// the list downloads the file once, so it needs internet the first time;
  /// after that the doc opens from the device with no network at all.
  Future<void> _toggleOffline(DocumentRecord r) async {
    final store = OfflineDocumentStore.instance;
    await store.ensureLoaded();
    if (!mounted) return;
    if (store.isSaved(r.id)) {
      await store.remove(r.id);
      if (!mounted) return;
      setState(() {});
      _toast(AppLocalizations.of(context).t('removedFromOffline'));
      return;
    }
    final path = r.filePath;
    if (path == null || path.trim().isEmpty) {
      _toast(AppLocalizations.of(context).t('noFileToSaveOffline'));
      return;
    }
    _toast(AppLocalizations.of(context).t('savingForOffline'));
    final saved = await store.save(
      docId: r.id,
      name: r.name,
      wallet: widget.category.name,
      objectPath: path,
      category: r.category,
    );
    if (!mounted) return;
    setState(() {});
    _toast(
      saved != null
          ? AppLocalizations.of(context)
              .t('savedForOfflineName')
              .replaceAll('{name}', r.name)
          : AppLocalizations.of(context).t('couldNotSaveOffline'),
    );
  }

  // ---- Action sheets -------------------------------------------------------

  void _openActions(DocumentRecord r) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // The action list has outgrown short screens (8 rows) - scroll inside
      // the sheet rather than overflow.
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
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
              // Document title — a true header, not another action row.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.primaryGreen.withValues(alpha: 0.28),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        r.icon,
                        color: AppColors.primaryGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: palette.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.t('document'),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: palette.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: palette.border.withValues(alpha: 0.7),
                ),
              ),
              _action(
                Icons.open_in_full_rounded,
                l10n.t('open'),
                () => _openDocument(r),
              ),
              _action(
                OfflineDocumentStore.instance.isSaved(r.id)
                    ? Icons.offline_pin_rounded
                    : Icons.download_for_offline_outlined,
                OfflineDocumentStore.instance.isSaved(r.id)
                    ? l10n.t('removeOfflineCopy')
                    : l10n.t('saveToAppOffline'),
                () => _toggleOffline(r),
              ),
              _action(
                Icons.qr_code_2_rounded,
                l10n.t('shareViaQr'),
                () => _shareSingle(r),
              ),
              _action(
                DocumentProtectionStore.instance.isProtected(r.id)
                    ? Icons.lock_open_rounded
                    : Icons.lock_rounded,
                DocumentProtectionStore.instance.isProtected(r.id)
                    ? l10n.t('removeProtection')
                    : l10n.t('protectWithBiometrics'),
                () => _toggleProtection(r),
              ),
              _action(
                r.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                r.isFavorite ? l10n.t('unfavorite') : l10n.t('favorite'),
                () => _toggleFavorite(r),
              ),
              _action(
                  Icons.archive_rounded, l10n.t('archive'), () => _archive(r)),
              _action(
                Icons.delete_outline_rounded,
                l10n.t('delete'),
                () => _delete(r),
                danger: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final palette = AppPalette.of(context);
    final color = danger ? AppColors.critical : palette.textPrimary;
    return ListTile(
      leading: Icon(
        icon,
        color: danger ? AppColors.critical : AppColors.primaryGreen,
      ),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
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
            Text(
              AppLocalizations.of(context).t('sortBy'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            for (final s in WalletSort.values)
              ListTile(
                title: Text(
                  s.localizedLabel(AppLocalizations.of(context)),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: s == _sort ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: s == _sort
                    ? Icon(Icons.check_rounded, color: AppColors.primaryGreen)
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

  /// The centre "+" quick menu, shared with the shell. Scans launched from
  /// here stay scoped to this wallet.
  void _onQuickAction(QuickMenuAction action) {
    openQuickMenuAction(context, action, initialWallet: widget.category.name);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopScope(
      // Prevent pop when either document selection or FAB menu is active.
      canPop: !_selecting && !InoBottomNav.isMenuOpen,
      onPopInvokedWithResult: (didPop, _) {
        final routeName = ModalRoute.of(context)?.settings.name ?? 'WalletDetailScreen';
        final isFabOpen = InoBottomNav.isMenuOpen;
        debugPrint('[Navigation] Android back pressed in WalletDetailScreen -> route: $routeName, isFabOpen: $isFabOpen, selecting: $_selecting');
        if (isFabOpen) {
          debugPrint('[FAB Menu] Intercepted Android back in WalletDetailScreen -> closing FAB menu');
          InoBottomNav.closeActiveMenu();
          return;
        }
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        extendBody: true,
        body: InoBackground(
          showDots: false,
          sky: divineGlassEnabled(context),
          child: SafeArea(
            // Launcher frosted header paints under the status bar itself.
            top: !divineGlassEnabled(context),
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    divineGlassEnabled(context)
                        ? WalletHeader(
                            title: localizedWalletName(
                              AppLocalizations.of(context),
                              widget.category.name,
                            ),
                            icon: widget.category.icon,
                            accent: _vaultAccent,
                            onBack: () => Navigator.of(context).maybePop(),
                            onManageShares: _openManageShares,
                            onAreaConverter: _isPropertyWallet
                                ? _openAreaConverter
                                : null,
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: WalletHeader(
                              title: localizedWalletName(
                                AppLocalizations.of(context),
                                widget.category.name,
                              ),
                              icon: widget.category.icon,
                              accent: _vaultAccent,
                              onBack: () => Navigator.of(context).maybePop(),
                              onManageShares: _openManageShares,
                              onAreaConverter: _isPropertyWallet
                                  ? _openAreaConverter
                                  : null,
                            ),
                          ),
                    Expanded(
                      child: FutureBuilder<WalletDetailData>(
                        future: _future,
                        builder: (context, snapshot) {
                          // Fall back to the previous data mid-reload — no
                          // skeleton blink after every FAB action.
                          final data = snapshot.data ?? _lastData;
                          return CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            // Build ~5 cards of runway beyond the viewport
                            // instead of the 250px default (~2). A hard fling
                            // pulls rows in faster than they can be built, and
                            // the default left visible gaps at the leading edge.
                            // Cards are cheap now that thumbnails decode small
                            // and `extraction` no longer re-parses JSON.
                            cacheExtent: 600.0,
                            slivers: [
                              if (data == null)
                                _loadingSliver()
                              else if (_records.isEmpty)
                                _emptyWalletSliver()
                              else
                                ..._loadedSlivers(data),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
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
                  Positioned(
                    right: 16,
                    // Clear the floating InoBottomNav pill + centre + bump.
                    bottom: MediaQuery.paddingOf(context).bottom + 108,
                    child: ExpandableFab(
                      actions: _fabActionsForWallet,
                      onAction: _onFabAction,
                      accent: AppColors.primaryGreen,
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: InoBottomNav(
          index: 1,
          onSelect: _onNavTab,
          onQuickMenuAction: _onQuickAction,
        ),
      ),
    );
  }

  Widget _loadingSliver() {
    return const SliverPadding(
      padding: EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 120),
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

  /// Brand-new / emptied wallet: skip search/summary/filters so the empty
  /// template can fill the viewport (same pattern as Property / Cards).
  Widget _emptyWalletSliver() {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        child: WalletEmptyState(
          title: _isHealthWallet
              ? l10n.t('noHealthRecordsYet')
              : l10n.t('noDocumentsYet'),
          subtitle: _isHealthWallet
              ? l10n.t('healthEmptySubtitle')
              : l10n.t('walletEmptySubtitle'),
          accent: _vaultAccent,
          onScan: () => _onFabAction(_fabActionsForWallet.first),
          onUpload: () => _onFabAction(_fabActionsForWallet[1]),
          onCreate: _createCategory,
        ),
      ),
    );
  }

  List<Widget> _loadedSlivers(WalletDetailData data) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final attention = _attentionRecord;
    final showBanner = attention != null && !_bannerDismissed;
    final expiring = _records
        .where(
          (r) =>
              r.status == DocumentStatus.expiringSoon ||
              r.status == DocumentStatus.expired,
        )
        .length;
    final animate = !divineGlassEnabled(context);

    Widget maybeAnimate(Widget child) =>
        animate ? FadeSlideIn(child: child) : child;

    return [
      // 2. Search (+ filter button under Launcher / Figma Identity).
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            AppSpacing.md,
            16,
            AppSpacing.sm,
          ),
          child: maybeAnimate(
            divineGlassEnabled(context)
                ? Row(
                    children: [
                      Expanded(
                        child: DetailSearchBar(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          accent: _vaultAccent,
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DivineGlassFilterButton(onTap: _openSort),
                    ],
                  )
                : DetailSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    accent: _vaultAccent,
                    onChanged: (v) => setState(() => _query = v),
                  ),
          ),
        ),
      ),
      // 3. Compact summary card.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: maybeAnimate(
            WalletSummaryCard(
              totalDocuments: _records.length,
              expiring: expiring,
              protected: data.security.vaultLocked,
              accent: _vaultAccent,
            ),
          ),
        ),
      ),
      // 4. Smart banner (only when something needs attention).
      if (showBanner)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: maybeAnimate(
              SmartBanner(
                message: _bannerMessage(attention),
                icon: Icons.warning_amber_rounded,
                accent: AppColors.warning,
                actionLabel: l10n.t('open'),
                onAction: () {
                  setState(() => _bannerDismissed = true);
                  _openDocument(attention);
                },
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            ),
          ),
        ),
      // 5. Status filter chips (scrolls; sort moved to "View recents").
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: DocumentFilterBar(
            filters: _filters,
            selected: _filter,
            accent: _vaultAccent,
            onFilter: (f) => setState(() => _filter = f),
          ),
        ),
      ),
      // 6. Category chips from wallet folders + document categories.
      if (_categoryChips.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: CategoryChips(
              categories: _categoryChips,
              selected: _category,
              accent: _vaultAccent,
              onSelected: (c) => setState(() => _category = c),
            ),
          ),
        ),
      // 7. Documents - count on the left, "View recents" on the right.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Text(
                _isHealthWallet ? l10n.t('records') : l10n.t('documents'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n
                    .t('countOfTotal')
                    .replaceAll('{n}', '${_visible.length}')
                    .replaceAll('{total}', '${_records.length}'),
                style: TextStyle(fontSize: 12, color: palette.textFaint),
              ),
              const Spacer(),
              _ViewRecentsButton(onTap: _openSort, accent: _vaultAccent),
            ],
          ),
        ),
      ),
      _documentsSliver(),
      // FAB clearance only when the list is showing — empty state centers
      // in the remaining viewport without a plain bottom band.
      if (_visible.isNotEmpty)
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ];
  }

  Widget _documentsSliver() {
    final visible = _visible;

    if (visible.isEmpty) {
      final emptyAll = _records.isEmpty;
      final l10n = AppLocalizations.of(context);
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WalletEmptyState(
            title: emptyAll
                ? (_isHealthWallet
                      ? l10n.t('noHealthRecordsYet')
                      : l10n.t('noDocumentsYet'))
                : l10n.t('noMatchingDocuments'),
            subtitle: emptyAll
                ? (_isHealthWallet
                      ? l10n.t('healthEmptySubtitle')
                      : l10n.t('startBuildingVault'))
                : l10n.t('tryDifferentFilter'),
            accent: _vaultAccent,
            onScan: () => _onFabAction(_fabActionsForWallet.first),
            onUpload: () => _onFabAction(_fabActionsForWallet[1]),
            onCreate: _createCategory,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          if (i.isOdd) return const SizedBox(height: 10);
          final record = visible[i ~/ 2];
          return DocumentCard(
            // Keyed by document id so filtering, sorting or a favourite toggle
            // re-associates each element with its own card instead of having
            // every card past the change point rebuild against new data.
            key: ValueKey(record.id),
            record: record,
            walletAccent: _vaultAccent,
            isHealth: _isHealthWallet,
            protected: DocumentProtectionStore.instance.isProtected(record.id),
            selectionMode: _selecting,
            selected: _selectedIds.contains(record.id),
            onOpen: () => _onCardTap(record),
            onLongPress: () => _onCardLongPress(record),
            onFavorite: () => _toggleFavorite(record),
            onMore: () => _openActions(record),
          );
        }, childCount: visible.length * 2 - 1),
      ),
    );
  }
}

/// A compact "View recents" affordance on the document-count row - a small
/// label + arrow that opens the sort options (Recent / A–Z / …).
class _ViewRecentsButton extends StatelessWidget {
  const _ViewRecentsButton({required this.onTap, this.accent});

  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.94,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).t('viewRecents'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: tint,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward_rounded, size: 15, color: tint),
          ],
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
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color: AppColors.primaryGreen.withValues(
                                alpha: 0.32,
                              ),
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
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: enabled ? onShare : null,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.qr_code_2_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.t('shareViaQr'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
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
final List<QuickAction> _detailFabActions = [
  QuickAction(
    label: 'Scan Document',
    icon: Icons.document_scanner_rounded,
    color: AppColors.primaryGreen,
  ),
  QuickAction(
    label: 'Upload PDF',
    icon: Icons.picture_as_pdf_rounded,
    color: AppColors.lightBlue,
  ),
  QuickAction(
    label: 'Import Image',
    icon: Icons.image_rounded,
    color: AppColors.lightBlue,
  ),
  QuickAction(
    label: 'Create Category',
    icon: Icons.new_label_rounded,
    color: Color(0xFF0EA5E9),
  ),
];
