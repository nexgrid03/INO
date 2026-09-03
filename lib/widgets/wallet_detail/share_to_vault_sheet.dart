import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../data/family_vault_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/family_vault_models.dart';
import '../../services/family_vault_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_loader.dart';

/// Lets the user share the open document into one of their Family Vaults.
///
/// Only vaults where they hold **editor or above** are offered - a viewer can
/// read a vault but not contribute to it. That is presentation only: the
/// `share_document_to_vault()` RPC re-checks the role server-side, so a client
/// that called it anyway would simply be refused.
///
/// Sharing does NOT copy the file. It records a grant against the existing
/// storage object, which is what lets removing a member (or withdrawing the
/// document) revoke access immediately instead of leaving duplicates behind in
/// other people's accounts.
///
/// Returns true when something was shared.
Future<bool> showShareToVaultSheet(
  BuildContext context, {
  required String objectPath,
  required String documentName,
  String? category,
  int? sizeBytes,
  String? sourceTable,
  String? sourceId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareToVaultSheet(
      objectPath: objectPath,
      documentName: documentName,
      category: category,
      sizeBytes: sizeBytes,
      sourceTable: sourceTable,
      sourceId: sourceId,
    ),
  );
  return result ?? false;
}

class _ShareToVaultSheet extends StatefulWidget {
  const _ShareToVaultSheet({
    required this.objectPath,
    required this.documentName,
    this.category,
    this.sizeBytes,
    this.sourceTable,
    this.sourceId,
  });

  final String objectPath;
  final String documentName;
  final String? category;
  final int? sizeBytes;
  final String? sourceTable;
  final String? sourceId;

  @override
  State<_ShareToVaultSheet> createState() => _ShareToVaultSheetState();
}

class _ShareToVaultSheetState extends State<_ShareToVaultSheet> {
  final _store = FamilyVaultStore.instance;
  final _repo = FamilyVaultRepository.instance;

  bool _loading = true;
  String? _busyVaultId;

  /// Either a localization key or an already-worded message from
  /// [describeVaultError]; both are safe to pass through [AppLocalizations.t],
  /// which falls back to the string itself when it is not a known key.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _store.ensureLoaded();
    } catch (e) {
      if (mounted) setState(() => _error = 'couldNotLoadVaults');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Vaults the user may contribute to. A viewer-only membership is filtered
  /// out here so the sheet never offers an action that would be refused.
  List<VaultSummary> get _eligible =>
      _store.vaults.where((v) => v.myRole.canEditDocuments).toList();

  Future<void> _share(VaultSummary vault) async {
    setState(() {
      _busyVaultId = vault.vault.id;
      _error = null;
    });
    try {
      await _repo.shareDocument(
        vaultId: vault.vault.id,
        objectPath: widget.objectPath,
        name: widget.documentName,
        category: widget.category,
        sizeBytes: widget.sizeBytes,
        sourceTable: widget.sourceTable,
        sourceId: widget.sourceId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      developer.log('shareDocument failed', name: 'vault', error: e, stackTrace: st);
      if (!mounted) return;
      // Report the real cause. Guessing "permission" here sent an Owner
      // hunting for a problem they did not have.
      setState(() {
        _busyVaultId = null;
        _error = describeVaultError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final eligible = _eligible;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                 Icon(Icons.family_restroom_rounded,
                    size: 22, color: AppColors.primaryGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.t('shareToFamilyVault'),
                    style: AppText.title.copyWith(color: palette.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.t('shareToVaultSubtitle'),
              style: AppText.caption
                  .copyWith(color: palette.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (_loading)
               Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: InoLoader(color: AppColors.primaryGreen),
                ),
              )
            else if (eligible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  l10n.t(_store.vaults.isEmpty
                      ? 'noFamilyVaultYet'
                      : 'viewerCannotAddDocuments'),
                  style: AppText.body.copyWith(
                      color: palette.textSecondary, height: 1.45),
                ),
              )
            else
              ...eligible.map((v) {
                final busy = _busyVaultId == v.vault.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: _busyVaultId == null ? () => _share(v) : null,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: v.myRole.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(v.myRole.icon,
                                size: 19, color: v.myRole.color),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.vault.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.subtitle.copyWith(
                                      color: palette.textPrimary,
                                      fontSize: 14.5),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n
                                      .t('youAreRole')
                                      .replaceAll('{role}', _roleLabel(l10n, v.myRole)),
                                  style: AppText.caption
                                      .copyWith(color: palette.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (busy)
                             InoLoader(size: 18, color: AppColors.primaryGreen)
                          else
                            Icon(Icons.chevron_right_rounded,
                                size: 20, color: palette.textFaint),
                        ],
                      ),
                    ),
                  ),
                );
              }),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                l10n.t(_error!),
                style: AppText.caption.copyWith(color: AppColors.critical),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The role name in the active language (the model's own [VaultRoleX.label]
  /// is English-only).
  String _roleLabel(AppLocalizations l10n, VaultRole role) => switch (role) {
        VaultRole.owner => l10n.t('owner'),
        VaultRole.admin => l10n.t('roleAdmin'),
        VaultRole.editor => l10n.t('roleEditor'),
        VaultRole.viewer => l10n.t('roleViewer'),
      };
}
