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
import '../../models/wallet_models.dart';
import '../../repositories/document_repository.dart';
import '../../services/card_store.dart';
import '../../services/investment_store.dart';
import '../../services/property_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_loader.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;

/// Represents any shareable wallet item (document or structured record).
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
  final Map<String, dynamic>? structuredJson;

  bool get hasFile => filePath != null && filePath!.trim().isNotEmpty;
  bool get hasCustomizableFields =>
      structuredJson != null && structuredJson!.isNotEmpty;
}

/// Adds documents or wallet items to a Family Vault with granular wallet/document
/// selection and customized field disclosure (e.g. for properties/assets).
///
/// Returns true when something was added.
Future<bool> showAddVaultDocumentSheet(
  BuildContext context, {
  required String vaultId,
  required String vaultName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddVaultDocumentSheet(
      vaultId: vaultId,
      vaultName: vaultName,
    ),
  );
  return result ?? false;
}

class _AddVaultDocumentSheet extends StatefulWidget {
  const _AddVaultDocumentSheet({
    required this.vaultId,
    required this.vaultName,
  });

  final String vaultId;
  final String vaultName;

  @override
  State<_AddVaultDocumentSheet> createState() => _AddVaultDocumentSheetState();
}

class _AddVaultDocumentSheetState extends State<_AddVaultDocumentSheet> {
  final _repo = FamilyVaultRepository.instance;
  final _docs = DocumentRepository.instance;

  List<VaultShareItem> _allItems = const [];
  String? _selectedWallet; // null = 'All'
  final Set<String> _selectedIds = <String>{};
  final Map<String, Map<String, bool>> _itemDisclosures = {};

  bool _loading = true;
  bool _uploading = false;
  String? _busyItemId;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. Load documents across all tables
      final docs = await _docs.listAll(forceRefresh: true);

      // 2. Ensure specialized stores are loaded
      await Future.wait([
        PropertyStore.instance.ensureLoaded(),
        InvestmentStore.instance.ensureLoaded(),
        CardStore.instance.ensureLoaded(),
      ]);

      final items = <VaultShareItem>[];
      final seenIds = <String>{};

      // A. Add documents from all wallets
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

      // B. Add Property Store records if not already represented
      for (final p in PropertyStore.instance.items) {
        if (!seenIds.contains(p.id)) {
          seenIds.add(p.id);
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

      // C. Add Investment Store records if not already represented
      for (final i in InvestmentStore.instance.items) {
        if (!seenIds.contains(i.id)) {
          seenIds.add(i.id);
          items.add(
            VaultShareItem(
              id: i.id,
              name: i.name,
              wallet: 'Investment Wallet',
              category: i.type.name,
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

      // D. Add Card Store records if not already represented
      for (final c in CardStore.instance.items) {
        if (!seenIds.contains(c.id)) {
          seenIds.add(c.id);
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

  static Color _colorForWallet(String wallet) {
    return AppColors.vaultAccentFor(wallet);
  }

  List<WalletCategory> get _availableWallets {
    return SupabaseWalletRepository.categories;
  }

  int _countForWallet(String? walletName) {
    if (walletName == null) return _allItems.length;
    return _allItems
        .where((item) => _isMatchingWallet(item.wallet, walletName))
        .length;
  }

  bool _isMatchingWallet(String itemWallet, String targetWallet) {
    final a = itemWallet.trim().toLowerCase();
    final b = targetWallet.trim().toLowerCase();
    return a == b || a.replaceAll(' ', '') == b.replaceAll(' ', '');
  }

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

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final visible = _visibleItems;
      final allSelected =
          visible.isNotEmpty && visible.every((item) => _selectedIds.contains(item.id));
      if (allSelected) {
        for (final item in visible) {
          _selectedIds.remove(item.id);
        }
      } else {
        for (final item in visible) {
          _selectedIds.add(item.id);
        }
      }
    });
  }

  Future<void> _customizeDisclosure(VaultShareItem item) async {
    final rawJson = item.structuredJson ?? {};
    final isProperty = item.wallet.toLowerCase().contains('property');
    final isInvestment = item.wallet.toLowerCase().contains('investment');
    final isBanking = item.wallet.toLowerCase().contains('bank');

    // Default configuration for disclosure fields
    final currentConfig = Map<String, bool>.from(_itemDisclosures[item.id] ?? {
      'name': true,
      'file': true,
      'price': true,
      'location': true,
      'registration_number': true,
      'institution': true,
      'card_details': true,
    });

    final updated = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final palette = AppPalette.of(ctx);
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: palette.bgElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (item.accentColor ?? AppColors.primaryGreen)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        item.icon ?? Icons.shield_rounded,
                        size: 20,
                        color: item.accentColor ?? AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customize Disclosure',
                            style: AppText.title.copyWith(
                              color: palette.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Choose what details family members can see for ${item.name}',
                            style: AppText.caption.copyWith(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: palette.border),
                const SizedBox(height: 10),

                // Name switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: AppColors.primaryGreen,
                  title: Text(
                    isProperty
                        ? 'Property Name'
                        : isBanking
                            ? 'Bank Name'
                            : 'Title / Name',
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    item.name,
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                  value: currentConfig['name'] ?? true,
                  onChanged: (v) => setModalState(() => currentConfig['name'] = v),
                ),

                // Uploaded document / file switch
                if (item.hasFile)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: AppColors.primaryGreen,
                    title: Text(
                      isProperty
                          ? 'Uploaded Deed / Document'
                          : 'Uploaded File Attachment',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Allow members to view/download the document attachment',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                    value: currentConfig['file'] ?? true,
                    onChanged: (v) => setModalState(() => currentConfig['file'] = v),
                  ),

                // Price / Value switch
                if (isProperty || isInvestment || rawJson.containsKey('current_value') || rawJson.containsKey('currentValue'))
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: AppColors.primaryGreen,
                    title: Text(
                      isProperty ? 'Property Price & Valuation' : 'Asset Value / Valuation',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Display property estimated price and purchase valuation',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                    value: currentConfig['price'] ?? true,
                    onChanged: (v) => setModalState(() => currentConfig['price'] = v),
                  ),

                // Location / City switch
                if (isProperty || rawJson.containsKey('city') || rawJson.containsKey('address'))
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: AppColors.primaryGreen,
                    title: Text(
                      'Location & City Details',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Display address, city, and location coordinates',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                    value: currentConfig['location'] ?? true,
                    onChanged: (v) => setModalState(() => currentConfig['location'] = v),
                  ),

                // Registration / Survey / Account Number switch
                if (item.recordNumber != null || isProperty || isInvestment || isBanking)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: AppColors.primaryGreen,
                    title: Text(
                      isProperty
                          ? 'Registration / Survey Number'
                          : isInvestment
                              ? 'Folio / Account Number'
                              : 'Card & Record Number',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Display official registration or account reference numbers',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                    value: currentConfig['registration_number'] ?? true,
                    onChanged: (v) =>
                        setModalState(() => currentConfig['registration_number'] = v),
                  ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(currentConfig),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text(
                      'Save Disclosure Settings',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _itemDisclosures[item.id] = updated;
        _selectedIds.add(item.id);
      });
    }
  }

  Future<void> _shareItems(List<VaultShareItem> itemsToShare) async {
    if (itemsToShare.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _uploading = false;
        _error = 'You must be signed in to share.';
      });
      return;
    }

    try {
      // 1. Ensure token is valid before interacting with storage
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && session.isExpired) {
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {}
      }

      for (final item in itemsToShare) {
        final disclosure = _itemDisclosures[item.id];
        final includeFile = disclosure?['file'] ?? true;
        final includePrice = disclosure?['price'] ?? true;
        final includeLoc = disclosure?['location'] ?? true;
        final includeReg = disclosure?['registration_number'] ?? true;
        final includeName = disclosure?['name'] ?? true;

        String objectPath;

        // Check if item has a valid file path that is already in storage vs local
        final isLocalFile = item.hasFile &&
            (item.filePath!.contains(Platform.pathSeparator) ||
                File(item.filePath!).existsSync());

        if (item.hasFile && includeFile) {
          if (isLocalFile && File(item.filePath!).existsSync()) {
            // Local file on device (e.g. from local PropertyStore) -> upload first
            objectPath = await _docs.uploadFile(item.filePath!);
          } else {
            // Already an object in Supabase storage bucket
            objectPath = item.filePath!;
          }
        } else {
          // It's a structured record without an uploaded storage file
          final filteredData = <String, dynamic>{};
          if (item.structuredJson != null) {
            final raw = item.structuredJson!;
            raw.forEach((k, v) {
              final key = k.toLowerCase();
              if ((key.contains('price') ||
                      key.contains('value') ||
                      key.contains('worth')) &&
                  !includePrice) {
                return;
              }
              if ((key.contains('city') ||
                      key.contains('address') ||
                      key.contains('loc')) &&
                  !includeLoc) {
                return;
              }
              if ((key.contains('reg') ||
                      key.contains('survey') ||
                      key.contains('acc')) &&
                  !includeReg) {
                return;
              }
              filteredData[k] = v;
            });
          }

          final ts = DateTime.now().millisecondsSinceEpoch;
          final summaryPayload = {
            'id': item.id,
            'name': includeName ? item.name : 'Shared Asset',
            'wallet': item.wallet,
            'category': item.category,
            if (includeReg) 'record_number': item.recordNumber,
            'details': item.details,
            if (filteredData.isNotEmpty) 'data': filteredData,
            'shared_at': DateTime.now().toIso8601String(),
          };

          final bytes =
              Uint8List.fromList(utf8.encode(jsonEncode(summaryPayload)));
          objectPath = '$uid/record_${ts}_${item.id}.json';
          try {
            await _docs.uploadBytes(
              objectPath,
              bytes,
              contentType: 'application/json',
            );
          } catch (e) {
            developer.log(
                'uploadBytes snapshot note fallback: $e',
                name: 'vault');
          }
        }

        final notePayload = <String, dynamic>{
          'hidden': false,
          'is_hidden': false,
          'active': true,
          'source_id': item.id,
          ...?((disclosure != null) ? {'fields': disclosure} : null),
        };

        await _repo.shareDocument(
          vaultId: widget.vaultId,
          objectPath: objectPath,
          name: includeName ? item.name : 'Shared Asset',
          category: item.category ?? item.wallet,
          sourceTable: item.wallet,
          sourceId: item.id,
          note: jsonEncode(notePayload),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      developer.log('shareItems failed',
          name: 'vault', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _busyItemId = null;
        _error = describeVaultError(e);
      });
    }
  }

  Future<void> _uploadAndShare() async {
    setState(() {
      _uploading = true;
      _error = null;
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

      final notePayload = {
        'hidden': false,
        'is_hidden': false,
        'active': true,
      };

      await _repo.shareDocument(
        vaultId: widget.vaultId,
        objectPath: objectPath,
        name: name,
        category: _selectedWallet ?? 'Uploaded Document',
        sourceTable: _selectedWallet ?? 'Document Wallet',
        sizeBytes: await file.length(),
        note: jsonEncode(notePayload),
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final visible = _visibleItems;
    final busy = _uploading || _busyItemId != null;
    final allSelectedInView = visible.isNotEmpty &&
        visible.every((item) => _selectedIds.contains(item.id));

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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.folder_shared_rounded,
                          size: 20,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n
                                  .t('addToVault')
                                  .replaceAll('{name}', widget.vaultName),
                              style: AppText.title.copyWith(
                                color: palette.textPrimary,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              'Share full wallets, specific documents, or custom disclosures',
                              style: AppText.caption.copyWith(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Upload straight from device button.
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _uploadAndShare,
                      icon: _uploading
                          ? InoLoader(size: 16, color: AppColors.primaryGreen)
                          : const Icon(Icons.upload_file_rounded, size: 20),
                      label: Text(
                        _uploading
                            ? l10n.t('uploading')
                            : l10n.t('uploadFromThisDevice'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.primaryGreen
                                .withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.critical.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.critical.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: AppColors.critical),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: AppText.caption.copyWith(
                                  color: AppColors.critical, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.sm),

                  // Search bar
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

                  // Wallet Segregation Selector Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        // "All" pill
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

                  // Selection Header Row
                  if (visible.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _selectedWallet != null
                              ? '${localizedWalletName(l10n, _selectedWallet!)} (${visible.length})'
                              : 'All Wallet Items (${visible.length})',
                          style: AppText.caption.copyWith(
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _toggleSelectAll,
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
                                      ? 'Deselect All'
                                      : _selectedWallet != null
                                          ? 'Select Wallet'
                                          : 'Select All',
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
              child: _loading
                  ? Center(
                      child: InoLoader(color: AppColors.primaryGreen),
                    )
                  : visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 40,
                                  color: palette.textFaint,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _allItems.isEmpty
                                      ? l10n.t('noStoredFilesYet')
                                      : l10n.t('noDocumentsMatchSearch'),
                                  textAlign: TextAlign.center,
                                  style: AppText.body.copyWith(
                                    color: palette.textSecondary,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final item = visible[i];
                            final isBusy = _busyItemId == item.id;
                            final isSelected = _selectedIds.contains(item.id);
                            final hasCustomDisclosure =
                                _itemDisclosures.containsKey(item.id);

                            return _ShareItemCard(
                              item: item,
                              isSelected: isSelected,
                              isBusy: isBusy,
                              disabled: busy,
                              hasCustomDisclosure: hasCustomDisclosure,
                              onToggleSelect: () => _toggleSelection(item.id),
                              onCustomize: () => _customizeDisclosure(item),
                              onDirectShare: () => _shareItems([item]),
                            );
                          },
                        ),
            ),

            // Bottom Sticky Multi-Share Bar
            if (_selectedIds.isNotEmpty)
              Container(
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selectedIds.length} item${_selectedIds.length > 1 ? "s" : ""} selected',
                            style: AppText.subtitle.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          Text(
                            'Ready to share with vault members',
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
                      onPressed: busy
                          ? null
                          : () {
                              final selected = _allItems
                                  .where((i) => _selectedIds.contains(i.id))
                                  .toList();
                              _shareItems(selected);
                            },
                      icon: _uploading
                          ? InoLoader(size: 16, color: Colors.white)
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _uploading ? 'Sharing...' : 'Share Selected',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
    final isSelected = selected;
    return PressableScale(
      pressedScale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.16)
                : palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isSelected ? accentColor : palette.border,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? accentColor : palette.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? accentColor : palette.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : palette.textFaint.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : palette.textSecondary,
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
    required this.isBusy,
    required this.disabled,
    required this.hasCustomDisclosure,
    required this.onToggleSelect,
    required this.onCustomize,
    required this.onDirectShare,
  });

  final VaultShareItem item;
  final bool isSelected;
  final bool isBusy;
  final bool disabled;
  final bool hasCustomDisclosure;
  final VoidCallback onToggleSelect;
  final VoidCallback onCustomize;
  final VoidCallback onDirectShare;

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
            // Compact Checkbox
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

            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                item.icon ?? Icons.description_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 8),

            // Name + Meta
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
                      if (item.details != null &&
                          item.details!.isNotEmpty) ...[
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
            const SizedBox(width: 4),

            // Trailing Actions (Compact)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.hasCustomizableFields || item.wallet.contains('Property'))
                  IconButton(
                    onPressed: disabled ? null : onCustomize,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Customize Disclosure',
                    icon: Icon(
                      hasCustomDisclosure
                          ? Icons.tune_rounded
                          : Icons.tune_outlined,
                      size: 18,
                      color: hasCustomDisclosure
                          ? AppColors.primaryGreen
                          : palette.textSecondary,
                    ),
                  ),
                if (isBusy)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: InoLoader(size: 16, color: AppColors.primaryGreen),
                  )
                else
                  IconButton(
                    onPressed: disabled ? null : onDirectShare,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Share now',
                    icon: Icon(
                      Icons.send_rounded,
                      size: 17,
                      color: AppColors.primaryGreen,
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
