import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/family_vault_repository.dart';
import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_share_field.dart';
import '../../models/wallet_models.dart';
import '../../repositories/document_repository.dart';
import '../../services/card_store.dart';
import '../../services/investment_store.dart';
import '../../services/property_store.dart';
import '../../services/wallet_media_sync.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_loader.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;

/// What the contributor chose to share: one document, or a whole wallet.
enum VaultShareMode {
  /// Pick individual documents / records out of any wallet.
  document,

  /// Pick a wallet and send everything in it under one disclosure decision.
  wallet,
}

/// Anything that can be shared into a Family Vault: an uploaded document, or a
/// structured wallet record (a property, an investment, a card) that carries
/// data as well as — or instead of — a file.
class VaultShareItem {
  const VaultShareItem({
    required this.id,
    required this.name,
    required this.wallet,
    this.category,
    this.filePath,
    this.recordNumber,
    this.details,
    this.icon,
    this.accentColor,
    this.structuredJson,
    this.sizeBytes,
    this.contentType,
  });

  final String id;
  final String name;
  final String wallet;
  final String? category;
  final String? filePath;
  final String? recordNumber;
  final String? details;
  final IconData? icon;
  final Color? accentColor;

  /// The record's own JSON — the source the field checklist is built from.
  final Map<String, dynamic>? structuredJson;

  final int? sizeBytes;
  final String? contentType;

  bool get hasFile => filePath != null && filePath!.trim().isNotEmpty;

  /// The checklist this item offers. Empty means there is nothing to choose:
  /// a plain document with no data fields is shared whole or not at all.
  List<VaultShareField> get shareFields => VaultShareFields.forRecord(
        structuredJson,
        hasFile: hasFile,
        fileLabel: 'Attached file',
        filePreview: 'Members can open and download it',
      );

  bool get hasChoices => shareFields.length > 1;
}

/// Opens the "share with family" flow for [vaultId].
///
/// Returns true when something was actually shared, so the caller can refresh.
Future<bool> showAddVaultDocumentSheet(
  BuildContext context, {
  required String vaultId,
  required String vaultName,
  VaultShareMode? mode,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddVaultDocumentSheet(
      vaultId: vaultId,
      vaultName: vaultName,
      initialMode: mode,
    ),
  );
  return result ?? false;
}

class _AddVaultDocumentSheet extends StatefulWidget {
  const _AddVaultDocumentSheet({
    required this.vaultId,
    required this.vaultName,
    this.initialMode,
  });

  final String vaultId;
  final String vaultName;
  final VaultShareMode? initialMode;

  @override
  State<_AddVaultDocumentSheet> createState() => _AddVaultDocumentSheetState();
}

/// Where the sheet is in the flow. Kept as one sheet with steps rather than a
/// stack of nested modals: the contributor can go back and change what they
/// picked without the earlier choice being torn down and re-made.
enum _Step { mode, documents, wallets, fields }

class _AddVaultDocumentSheetState extends State<_AddVaultDocumentSheet> {
  final _repo = FamilyVaultRepository.instance;
  final _docs = DocumentRepository.instance;

  _Step _step = _Step.mode;
  VaultShareMode _mode = VaultShareMode.document;

  List<VaultShareItem> _allItems = const [];
  String? _selectedWallet; // the filter pill on the document list
  String? _shareWallet; // the wallet chosen in wallet mode
  final Set<String> _selectedIds = <String>{};

  /// Per-item disclosure masks (document mode).
  final Map<String, Map<String, bool>> _itemMasks = {};

  /// The one mask applied to every record in the chosen wallet (wallet mode).
  final Map<String, bool> _walletMask = {};

  /// Whether what is shared shows up for the family straight away. Off shares
  /// it hidden — staged, ready to switch on from the vault.
  bool _visibleToFamily = true;

  bool _loading = true;
  bool _uploading = false;
  String _query = '';
  String? _error;

  /// Progress while a multi-item share is in flight ("Sharing 3 of 7…").
  int _shared = 0;
  int _shareTotal = 0;

  @override
  void initState() {
    super.initState();
    final mode = widget.initialMode;
    if (mode != null) {
      _mode = mode;
      _step = mode == VaultShareMode.document ? _Step.documents : _Step.wallets;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await _docs.listAll(forceRefresh: true);

      await Future.wait([
        PropertyStore.instance.ensureLoaded(),
        InvestmentStore.instance.ensureLoaded(),
        CardStore.instance.ensureLoaded(),
      ]);

      final items = <VaultShareItem>[];
      final seenIds = <String>{};

      for (final d in docs) {
        seenIds.add(d.id);
        final walletName = d.wallet.isNotEmpty ? d.wallet : 'Document Wallet';
        items.add(
          VaultShareItem(
            id: d.id,
            name: d.name,
            wallet: walletName,
            category: d.category,
            filePath: d.filePath,
            recordNumber: d.recordNumber,
            details: d.doctorName ??
                d.recordNumber ??
                (d.tags.isNotEmpty ? d.tags.join(', ') : null),
            icon: _iconForWallet(walletName, d.category),
            accentColor: _colorForWallet(walletName),
          ),
        );
      }

      for (final p in PropertyStore.instance.items) {
        if (seenIds.add(p.id)) {
          items.add(
            VaultShareItem(
              id: p.id,
              name: p.name,
              wallet: 'Property Wallet',
              category: p.type.name,
              filePath: p.imagePath,
              recordNumber: p.registrationNumber,
              details: [
                if (p.city != null && p.city!.isNotEmpty) p.city!,
                if (p.currentValue != null) '₹${p.currentValue}',
              ].join(' · '),
              icon: Icons.home_work_rounded,
              accentColor: _colorForWallet('Property Wallet'),
              structuredJson: p.toJson(),
            ),
          );
        }
      }

      for (final i in InvestmentStore.instance.items) {
        if (seenIds.add(i.id)) {
          items.add(
            VaultShareItem(
              id: i.id,
              name: i.name,
              wallet: 'Investment Wallet',
              category: i.type.name,
              filePath: i.attachments
                  .map((a) => a.path)
                  .firstWhere((p) => p != null && p.isNotEmpty,
                      orElse: () => null),
              recordNumber: i.accountNumber,
              details: [
                if (i.institution != null && i.institution!.isNotEmpty)
                  i.institution!,
                if (i.currentValue != null) '₹${i.currentValue}',
              ].join(' · '),
              icon: Icons.trending_up_rounded,
              accentColor: _colorForWallet('Investment Wallet'),
              structuredJson: i.toJson(),
            ),
          );
        }
      }

      for (final c in CardStore.instance.items) {
        if (seenIds.add(c.id)) {
          items.add(
            VaultShareItem(
              id: c.id,
              name: c.bank,
              wallet: 'Banking Wallet',
              category: c.kind.name,
              details: [
                c.network.name.toUpperCase(),
                '•••• ${c.last4}',
              ].join(' · '),
              icon: Icons.credit_card_rounded,
              accentColor: _colorForWallet('Banking Wallet'),
              structuredJson: c.toJson(),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _allItems = items;
        _loading = false;
      });
    } catch (e) {
      developer.log('vault share list failed', name: 'vault', error: e);
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).t('couldNotLoadYourDocuments');
        _loading = false;
      });
    }
  }

  static IconData _iconForWallet(String wallet, String? category) {
    final cat = category?.toLowerCase() ?? '';
    if (cat.contains('identity') ||
        cat.contains('aadhaar') ||
        cat.contains('pan') ||
        cat.contains('passport')) {
      return Icons.badge_rounded;
    }
    if (cat.contains('health') ||
        cat.contains('medical') ||
        cat.contains('doctor')) {
      return Icons.favorite_rounded;
    }
    if (cat.contains('insurance') || cat.contains('policy')) {
      return Icons.shield_rounded;
    }
    if (cat.contains('property') || cat.contains('deed')) {
      return Icons.home_work_rounded;
    }
    if (cat.contains('investment') ||
        cat.contains('stock') ||
        cat.contains('gold')) {
      return Icons.trending_up_rounded;
    }
    if (cat.contains('bank') ||
        cat.contains('statement') ||
        cat.contains('card')) {
      return Icons.account_balance_rounded;
    }

    switch (wallet) {
      case 'Identity Wallet':
        return Icons.badge_rounded;
      case 'Property Wallet':
        return Icons.home_work_rounded;
      case 'Insurance Wallet':
        return Icons.shield_rounded;
      case 'Health Wallet':
        return Icons.favorite_rounded;
      case 'Investment Wallet':
        return Icons.trending_up_rounded;
      case 'Banking Wallet':
        return Icons.account_balance_rounded;
      case 'Cards Wallet':
        return Icons.credit_card_rounded;
      case 'Password Vault':
        return Icons.lock_rounded;
      default:
        return Icons.folder_shared_rounded;
    }
  }

  static Color _colorForWallet(String wallet) =>
      AppColors.vaultAccentFor(wallet);

  List<WalletCategory> get _availableWallets =>
      SupabaseWalletRepository.categories;

  static bool _isMatchingWallet(String itemWallet, String targetWallet) {
    String norm(String s) =>
        s.trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    return norm(itemWallet) == norm(targetWallet);
  }

  int _countForWallet(String? walletName) => walletName == null
      ? _allItems.length
      : _allItems.where((i) => _isMatchingWallet(i.wallet, walletName)).length;

  List<VaultShareItem> _itemsInWallet(String wallet) =>
      _allItems.where((i) => _isMatchingWallet(i.wallet, wallet)).toList();

  List<VaultShareItem> get _visibleItems {
    final q = _query.trim().toLowerCase();
    return _allItems.where((item) {
      if (_selectedWallet != null &&
          !_isMatchingWallet(item.wallet, _selectedWallet!)) {
        return false;
      }
      if (q.isEmpty) return true;
      return item.name.toLowerCase().contains(q) ||
          item.wallet.toLowerCase().contains(q) ||
          (item.category ?? '').toLowerCase().contains(q) ||
          (item.details ?? '').toLowerCase().contains(q) ||
          (item.recordNumber ?? '').toLowerCase().contains(q);
    }).toList();
  }

  /// The items the current step is about to share.
  List<VaultShareItem> get _pendingItems {
    if (_mode == VaultShareMode.wallet) {
      final wallet = _shareWallet;
      if (wallet == null) return const [];
      return _itemsInWallet(wallet)
          .where((i) => _selectedIds.contains(i.id))
          .toList();
    }
    return _allItems.where((i) => _selectedIds.contains(i.id)).toList();
  }

  /// The mask for [item] — its own in document mode, the wallet-wide one in
  /// wallet mode. Anything not answered defaults to shared, so a field the
  /// contributor never looked at is not silently withheld.
  Map<String, bool> _maskFor(VaultShareItem item) {
    final source =
        _mode == VaultShareMode.wallet ? _walletMask : (_itemMasks[item.id] ?? const {});
    final mask = <String, bool>{};
    for (final f in item.shareFields) {
      mask[f.key] = source[f.key] ?? true;
    }
    return mask;
  }

  void _toggleSelection(String id) => setState(() {
        _selectedIds.contains(id)
            ? _selectedIds.remove(id)
            : _selectedIds.add(id);
      });

  void _toggleSelectAll(List<VaultShareItem> visible) => setState(() {
        final allSelected = visible.isNotEmpty &&
            visible.every((item) => _selectedIds.contains(item.id));
        for (final item in visible) {
          allSelected
              ? _selectedIds.remove(item.id)
              : _selectedIds.add(item.id);
        }
      });

  void _chooseMode(VaultShareMode mode) => setState(() {
        _mode = mode;
        _selectedIds.clear();
        _shareWallet = null;
        _step = mode == VaultShareMode.document ? _Step.documents : _Step.wallets;
      });

  void _chooseWallet(String wallet) => setState(() {
        _shareWallet = wallet;
        _selectedIds
          ..clear()
          ..addAll(_itemsInWallet(wallet).map((i) => i.id));
        _walletMask.clear();
        _step = _Step.fields;
      });

  void _back() => setState(() {
        _error = null;
        switch (_step) {
          case _Step.mode:
            Navigator.of(context).pop(false);
          case _Step.documents:
          case _Step.wallets:
            // A mode passed in by the caller means the chooser was skipped;
            // going "back" from the first real step should close, not strand
            // the user on a step they never saw.
            if (widget.initialMode != null) {
              Navigator.of(context).pop(false);
            } else {
              _step = _Step.mode;
            }
          case _Step.fields:
            _step = _mode == VaultShareMode.document
                ? _Step.documents
                : _Step.wallets;
        }
      });

  /// Whether the pending selection has anything worth a checklist. A set of
  /// plain documents with no data fields skips the step entirely rather than
  /// showing a page with one switch on it.
  bool get _needsFieldStep => _pendingItems.any((i) => i.hasChoices);

  void _continueFromDocuments() {
    if (_selectedIds.isEmpty) return;
    if (_needsFieldStep) {
      setState(() => _step = _Step.fields);
    } else {
      _shareItems(_pendingItems);
    }
  }

  // ---- Sharing --------------------------------------------------------------

  Future<void> _shareItems(List<VaultShareItem> itemsToShare) async {
    if (itemsToShare.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
      _shared = 0;
      _shareTotal = itemsToShare.length;
    });

    // Read before the first await: _shareOne runs across several of them, and
    // reaching for an inherited widget afterwards is how a share crashes on a
    // screen the user has already navigated away from.
    final anonymousLabel =
        AppLocalizations.of(context).t('sharedItemFallback');

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _uploading = false;
        _error = 'You must be signed in to share.';
      });
      return;
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && session.isExpired) {
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {}
      }

      for (final item in itemsToShare) {
        await _shareOne(item, uid, anonymousLabel);
        if (!mounted) return;
        setState(() => _shared++);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      developer.log('shareItems failed', name: 'vault', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = describeVaultError(e);
      });
    }
  }

  Future<void> _shareOne(
    VaultShareItem item,
    String uid,
    String anonymousLabel,
  ) async {
    final mask = _maskFor(item);
    final includeFile = mask[VaultShareField.fileKey] ?? item.hasFile;
    final disclosed = VaultShareFields.applyMask(item.structuredJson, mask);

    // The name is a field like any other, and it is the ONE field that also
    // travels as a column. Switching "Name" off and then sending the name in
    // vault_documents.name would break the promise the checklist just made.
    final shareName = (mask['name'] ?? true)
        ? item.name
        : '$anonymousLabel · ${item.category ?? item.wallet}';

    String objectPath;
    int? sizeBytes = item.sizeBytes;
    String? contentType = item.contentType;

    // Three cases, and the difference matters. The file is already in the
    // bucket; or it is on this device and needs uploading; or the stored path
    // is a dead reference from before wallet media was uploaded at all, and
    // there is nothing left to send.
    final path = item.filePath;
    final fileExists = item.hasFile &&
        (WalletMediaSync.isRemote(path) || WalletMediaSync.isLocalFile(path));

    if (includeFile && fileExists) {
      final resolved = await WalletMediaSync.instance.ensureUploaded(path);
      if (resolved == null || !WalletMediaSync.isRemote(resolved)) {
        // The file is right here and still would not upload — almost always
        // the network. Sharing a row that points at a path no member can read
        // would look like success and fail silently on their side, so stop.
        throw VaultShareFailure(
          'Could not upload "${item.name}". Check your connection and try again.',
        );
      }
      objectPath = resolved;
      if (sizeBytes == null && WalletMediaSync.isLocalFile(path)) {
        sizeBytes = await File(path!).length();
      }
    } else {
      // No file, or the file was withheld: share a snapshot of the disclosed
      // fields instead, so the family still sees the record.
      //
      // The path is DETERMINISTIC per (vault, record) and written with upsert.
      // A timestamped name would leave the previous, less-redacted snapshot in
      // the bucket — and the member who already had that row could still open
      // it. Re-sharing has to overwrite what it replaces.
      final safeId = item.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      objectPath = '$uid/vault_${widget.vaultId}_$safeId.json';
      final payload = <String, dynamic>{
        'name': shareName,
        'wallet': item.wallet,
        if (item.category != null) 'category': item.category,
        'fields': disclosed,
        // Say so rather than letting a missing attachment read as a choice the
        // contributor made. This is the pre-upload record whose photo only ever
        // existed on the phone that created it.
        if (includeFile && item.hasFile && !fileExists)
          'file_unavailable': true,
        'shared_at': DateTime.now().toIso8601String(),
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      await _docs.uploadBytes(
        objectPath,
        bytes,
        contentType: 'application/json',
        upsert: true,
      );
      sizeBytes = bytes.length;
      contentType = 'application/json';
    }

    await _repo.shareItem(
      vaultId: widget.vaultId,
      objectPath: objectPath,
      name: shareName,
      category: item.category ?? item.wallet,
      sizeBytes: sizeBytes,
      contentType: contentType,
      sourceTable: item.wallet,
      sourceRef: item.id,
      sharedFields: mask,
      sharedData: disclosed.isEmpty ? null : disclosed,
      isHidden: !_visibleToFamily,
    );
  }

  Future<void> _uploadAndShare() async {
    setState(() {
      _uploading = true;
      _error = null;
      _shared = 0;
      _shareTotal = 1;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(withData: false);
      final path = picked?.files.single.path;
      if (path == null) {
        if (mounted) setState(() => _uploading = false);
        return; // cancelled
      }

      final objectPath = await _docs.uploadFile(path);
      final file = File(path);
      final name = path.split(RegExp(r'[\\/]')).last;

      await _repo.shareItem(
        vaultId: widget.vaultId,
        objectPath: objectPath,
        name: name,
        category: _selectedWallet ?? 'Uploaded Document',
        sourceTable: _selectedWallet ?? 'Document Wallet',
        sizeBytes: await file.length(),
        isHidden: !_visibleToFamily,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      developer.log('upload+share failed',
          name: 'vault', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = describeVaultError(e);
      });
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(palette),
            if (_error != null) _errorBanner(),
            Expanded(child: _body(scrollController, palette)),
            _bottomBar(palette),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final (title, subtitle) = switch (_step) {
      _Step.mode => (
          l10n.t('shareWithFamily'),
          l10n.t('shareWithFamilySubtitle')
              .replaceAll('{name}', widget.vaultName),
        ),
      _Step.documents => (
          l10n.t('shareSpecificDocument'),
          l10n.t('shareSpecificDocumentSubtitle'),
        ),
      _Step.wallets => (
          l10n.t('shareCompleteWallet'),
          l10n.t('shareCompleteWalletSubtitle'),
        ),
      _Step.fields => (
          l10n.t('chooseWhatToShare'),
          l10n.t('chooseWhatToShareSubtitle'),
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: _uploading ? null : _back,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _step == _Step.mode
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.title
                      .copyWith(color: palette.textPrimary, fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.caption
                      .copyWith(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.critical.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.critical.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: AppColors.critical),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: AppText.caption
                      .copyWith(color: AppColors.critical, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _body(ScrollController controller, AppPalette palette) {
    if (_loading) {
      return Center(child: InoLoader(color: AppColors.primaryGreen));
    }
    return switch (_step) {
      _Step.mode => _modeStep(controller, palette),
      _Step.documents => _documentsStep(controller, palette),
      _Step.wallets => _walletsStep(controller, palette),
      _Step.fields => _fieldsStep(controller, palette),
    };
  }

  // -- Step 1: what kind of share ---------------------------------------------

  Widget _modeStep(ScrollController controller, AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final walletCount = _allItems.map((i) => i.wallet).toSet().length;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _ModeCard(
          icon: Icons.description_rounded,
          accent: AppColors.primaryGreen,
          title: l10n.t('shareSpecificDocument'),
          body: l10n.t('shareSpecificDocumentBody'),
          meta: l10n
              .t('itemsAvailable')
              .replaceAll('{n}', '${_allItems.length}'),
          onTap: () => _chooseMode(VaultShareMode.document),
        ),
        const SizedBox(height: 10),
        _ModeCard(
          icon: Icons.folder_copy_rounded,
          accent: const Color(0xFF2563EB),
          title: l10n.t('shareCompleteWallet'),
          body: l10n.t('shareCompleteWalletBody'),
          meta: l10n
              .t('walletsAvailable')
              .replaceAll('{n}', '$walletCount'),
          onTap: () => _chooseMode(VaultShareMode.wallet),
        ),
        const SizedBox(height: 10),
        _ModeCard(
          icon: Icons.upload_file_rounded,
          accent: const Color(0xFF8B6CEF),
          title: l10n.t('uploadFromThisDevice'),
          body: l10n.t('uploadFromDeviceBody'),
          onTap: _uploading ? null : _uploadAndShare,
        ),
        const SizedBox(height: 16),
        _visibilitySwitch(palette),
      ],
    );
  }

  /// The "show this to the family now" switch. Sharing something hidden is a
  /// real workflow — stage the documents, then flip the wallet on from the
  /// vault when the family is ready to see them.
  Widget _visibilitySwitch(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(
            _visibleToFamily
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            size: 19,
            color: _visibleToFamily
                ? AppColors.primaryGreen
                : palette.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.t('visibleToFamily'),
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _visibleToFamily
                      ? l10n.t('visibleToFamilyOn')
                      : l10n.t('visibleToFamilyOff'),
                  style: AppText.caption.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _visibleToFamily,
            activeTrackColor: AppColors.primaryGreen,
            onChanged: _uploading
                ? null
                : (v) => setState(() => _visibleToFamily = v),
          ),
        ],
      ),
    );
  }

  // -- Step 2a: pick documents ------------------------------------------------

  Widget _documentsStep(ScrollController controller, AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final visible = _visibleItems;
    final allSelectedInView = visible.isNotEmpty &&
        visible.every((item) => _selectedIds.contains(item.id));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: AppText.body
                    .copyWith(color: palette.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.t('searchYourDocuments'),
                  hintStyle:
                      AppText.caption.copyWith(color: palette.textFaint),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 19, color: palette.textFaint),
                  filled: true,
                  fillColor: palette.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    borderSide: BorderSide(
                        color: AppColors.primaryGreen, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _WalletPill(
                      label: l10n.t('all'),
                      count: _countForWallet(null),
                      icon: Icons.grid_view_rounded,
                      accentColor: AppColors.primaryGreen,
                      selected: _selectedWallet == null,
                      onTap: () => setState(() => _selectedWallet = null),
                    ),
                    const SizedBox(width: 6),
                    for (final w in _availableWallets)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _WalletPill(
                          label: localizedWalletName(l10n, w.name),
                          count: _countForWallet(w.name),
                          icon: w.icon,
                          accentColor: w.gradient.first,
                          selected: _selectedWallet == w.name,
                          onTap: () => setState(() {
                            _selectedWallet =
                                _selectedWallet == w.name ? null : w.name;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              if (visible.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _selectedWallet != null
                          ? '${localizedWalletName(l10n, _selectedWallet!)} (${visible.length})'
                          : l10n
                              .t('allWalletItems')
                              .replaceAll('{n}', '${visible.length}'),
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => _toggleSelectAll(visible),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              allSelectedInView
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 16,
                              color: AppColors.primaryGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              allSelectedInView
                                  ? l10n.t('deselectAll')
                                  : l10n.t('selectAll'),
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: visible.isEmpty
              ? _emptyState(palette)
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = visible[i];
                    return _ShareItemCard(
                      item: item,
                      isSelected: _selectedIds.contains(item.id),
                      disabled: _uploading,
                      customised: _itemMasks.containsKey(item.id),
                      onToggleSelect: () => _toggleSelection(item.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: palette.textFaint),
            const SizedBox(height: 10),
            Text(
              _allItems.isEmpty
                  ? l10n.t('noStoredFilesYet')
                  : l10n.t('noDocumentsMatchSearch'),
              textAlign: TextAlign.center,
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  // -- Step 2b: pick a wallet -------------------------------------------------

  Widget _walletsStep(ScrollController controller, AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final wallets = <String>{for (final i in _allItems) i.wallet}.toList()
      ..sort();

    if (wallets.isEmpty) return _emptyState(palette);

    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: wallets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final wallet = wallets[i];
        final items = _itemsInWallet(wallet);
        final withFiles = items.where((it) => it.hasFile).length;
        return _ModeCard(
          icon: _iconForWallet(wallet, null),
          accent: _colorForWallet(wallet),
          title: localizedWalletName(l10n, wallet),
          body: l10n
              .t('walletShareBody')
              .replaceAll('{n}', '${items.length}')
              .replaceAll('{files}', '$withFiles'),
          onTap: _uploading ? null : () => _chooseWallet(wallet),
        );
      },
    );
  }

  // -- Step 3: the checklist --------------------------------------------------

  Widget _fieldsStep(ScrollController controller, AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final items = _pendingItems;

    if (_mode == VaultShareMode.wallet) {
      final wallet = _shareWallet ?? '';
      final all = _itemsInWallet(wallet);
      final fields = VaultShareFields.forWallet(
        [for (final i in all) i.structuredJson],
        anyHasFile: all.any((i) => i.hasFile),
      );
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _visibilitySwitch(palette),
          const SizedBox(height: 14),
          if (fields.isEmpty)
            _noChoicesNote(palette)
          else ...[
            _sectionLabel(
              palette,
              l10n
                  .t('fieldsSharedForEvery')
                  .replaceAll('{wallet}', localizedWalletName(l10n, wallet)),
            ),
            for (final f in fields)
              _FieldTile(
                field: f,
                value: _walletMask[f.key] ?? true,
                onChanged: (v) => setState(() => _walletMask[f.key] = v),
              ),
          ],
          const SizedBox(height: 18),
          _sectionLabel(
            palette,
            l10n
                .t('itemsIncluded')
                .replaceAll('{n}', '${_selectedIds.length}')
                .replaceAll('{total}', '${all.length}'),
          ),
          for (final item in all)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.primaryGreen,
              value: _selectedIds.contains(item.id),
              onChanged: _uploading ? null : (_) => _toggleSelection(item.id),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle
                    .copyWith(color: palette.textPrimary, fontSize: 13.5),
              ),
              subtitle: item.details == null || item.details!.isEmpty
                  ? null
                  : Text(
                      item.details!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary, fontSize: 11),
                    ),
            ),
        ],
      );
    }

    // Document mode: one section per selected item that has choices to make.
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _visibilitySwitch(palette),
        const SizedBox(height: 14),
        for (final item in items) ...[
          _ItemFieldsSection(
            item: item,
            mask: _maskFor(item),
            onChanged: (key, value) => setState(() {
              final mask = _itemMasks.putIfAbsent(item.id, () => {});
              mask[key] = value;
            }),
          ),
          const SizedBox(height: 12),
        ],
        if (items.every((i) => !i.hasChoices)) _noChoicesNote(palette),
      ],
    );
  }

  Widget _sectionLabel(AppPalette palette, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: AppText.caption.copyWith(
            color: palette.textFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _noChoicesNote(AppPalette palette) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.border),
        ),
        child: Text(
          AppLocalizations.of(context).t('nothingToCustomise'),
          style: AppText.caption
              .copyWith(color: palette.textSecondary, height: 1.4),
        ),
      );

  // -- Bottom bar -------------------------------------------------------------

  Widget? _bottomBarChild(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    if (_step == _Step.mode || _step == _Step.wallets) return null;

    final count = _selectedIds.length;
    if (count == 0) return null;

    final isFinal = _step == _Step.fields || !_needsFieldStep;
    final label = _uploading
        ? (_shareTotal > 1
            ? l10n
                .t('sharingProgress')
                .replaceAll('{n}', '${_shared + 1}')
                .replaceAll('{total}', '$_shareTotal')
            : l10n.t('sharingEllipsis'))
        : isFinal
            ? l10n.t('shareNItems').replaceAll('{n}', '$count')
            : l10n.t('nextChooseDetails');

    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('nItemsSelected').replaceAll('{n}', '$count'),
                style: AppText.subtitle.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              Text(
                _visibleToFamily
                    ? l10n.t('willBeVisibleImmediately')
                    : l10n.t('willBeAddedHidden'),
                style: AppText.caption.copyWith(
                  color: palette.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _uploading
              ? null
              : isFinal
                  ? () => _shareItems(_pendingItems)
                  : _continueFromDocuments,
          icon: _uploading
              ? const InoLoader(size: 16, color: Colors.white)
              : Icon(isFinal ? Icons.send_rounded : Icons.arrow_forward_rounded,
                  size: 18),
          label: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(AppPalette palette) {
    final child = _bottomBarChild(palette);
    if (child == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: palette.bgElevated,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A big tappable choice card — the two share modes and the wallet list.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.meta,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                    if (meta != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          meta!,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The checklist for one item, with its own header.
class _ItemFieldsSection extends StatelessWidget {
  const _ItemFieldsSection({
    required this.item,
    required this.mask,
    required this.onChanged,
  });

  final VaultShareItem item;
  final Map<String, bool> mask;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // With only one thing to offer there is no choice to make: switching it off
    // would share an empty record. Say what will happen instead of presenting a
    // switch whose only setting is the one it is already on.
    final fields = item.hasChoices ? item.shareFields : const <VaultShareField>[];
    final color = item.accentColor ?? AppColors.primaryGreen;
    final withheld = mask.values.where((v) => !v).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon ?? Icons.description_rounded,
                    size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      localizedWalletName(l10n, item.wallet),
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (withheld > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    l10n.t('nHidden').replaceAll('{n}', '$withheld'),
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (fields.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.t('sharedAsIs'),
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            for (final f in fields)
              _FieldTile(
                field: f,
                value: mask[f.key] ?? true,
                onChanged: (v) => onChanged(f.key, v),
              ),
          ],
        ],
      ),
    );
  }
}

/// One switch in the checklist: the field, what it currently says, and whether
/// the family will be able to read it.
class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final VaultShareField field;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      activeTrackColor: AppColors.primaryGreen,
      value: value,
      onChanged: onChanged,
      title: Row(
        children: [
          if (field.isFile) ...[
            Icon(Icons.attach_file_rounded, size: 14, color: palette.textFaint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              field.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.subtitle.copyWith(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (field.sensitive) ...[
            const SizedBox(width: 5),
            Icon(Icons.lock_outline_rounded,
                size: 12, color: AppColors.warning),
          ],
        ],
      ),
      subtitle: field.preview == null
          ? null
          : Text(
              field.preview!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: value ? palette.textSecondary : palette.textFaint,
                fontSize: 11.5,
                decoration: value ? null : TextDecoration.lineThrough,
              ),
            ),
    );
  }
}

class _WalletPill extends StatelessWidget {
  const _WalletPill({
    required this.label,
    required this.count,
    required this.icon,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.16)
                : palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? accentColor : palette.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: selected ? accentColor : palette.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? accentColor : palette.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? accentColor
                      : palette.textFaint.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : palette.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
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

class _ShareItemCard extends StatelessWidget {
  const _ShareItemCard({
    required this.item,
    required this.isSelected,
    required this.disabled,
    required this.customised,
    required this.onToggleSelect,
  });

  final VaultShareItem item;
  final bool isSelected;
  final bool disabled;
  final bool customised;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = item.accentColor ?? AppColors.primaryGreen;
    final l10n = AppLocalizations.of(context);

    return InkWell(
      onTap: disabled ? null : onToggleSelect,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen.withValues(alpha: 0.6)
                : palette.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: isSelected,
                activeColor: AppColors.primaryGreen,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                onChanged: disabled ? null : (_) => onToggleSelect(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon ?? Icons.description_rounded,
                  size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          localizedWalletName(l10n, item.wallet),
                          style: TextStyle(
                            color: color,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (item.category != null &&
                          item.category!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '· ${item.category}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: palette.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                      if (item.details != null && item.details!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '· ${item.details}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: palette.textFaint,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (item.hasChoices)
              Tooltip(
                message: l10n.t('hasFieldsToChoose'),
                child: Icon(
                  customised ? Icons.tune_rounded : Icons.tune_outlined,
                  size: 17,
                  color: customised
                      ? AppColors.primaryGreen
                      : palette.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
