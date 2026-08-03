import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/family_vault_repository.dart';
import '../../models/document.dart';
import '../../repositories/document_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Adds a document to a Family Vault, from inside the vault itself.
///
/// The only way to share used to be the Family Vault button in the document
/// viewer, several taps deep inside a wallet. An owner looking at their own
/// empty vault had no way to fill it from where they were standing, which is
/// the natural place to want to. This sheet offers both routes:
///
///   * **Choose from my documents** - pick something already in a wallet. This
///     registers a grant against the existing storage object, so nothing is
///     duplicated and withdrawing it genuinely revokes access.
///   * **Upload from this device** - pick a file, upload it to the caller's own
///     storage folder, then share that. Used when the document isn't in a
///     wallet yet.
///
/// Both paths end in `share_document_to_vault()`, which re-checks the caller's
/// role server-side - this sheet is only reachable for editors and above, but
/// that is presentation, not enforcement.
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

  List<Document> _all = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _busyDocId;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await _docs.listAll();
      if (!mounted) return;
      setState(() {
        // Only documents with a stored file can be shared - the grant is
        // against a storage object, so a metadata-only record has nothing to
        // point at.
        _all = docs
            .where((d) => (d.filePath ?? '').isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your documents.';
        _loading = false;
      });
    }
  }

  List<Document> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((d) =>
            d.name.toLowerCase().contains(q) ||
            d.wallet.toLowerCase().contains(q) ||
            (d.category ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _shareExisting(Document doc) async {
    setState(() {
      _busyDocId = doc.id;
      _error = null;
    });
    try {
      await _repo.shareDocument(
        vaultId: widget.vaultId,
        objectPath: doc.filePath!,
        name: doc.name,
        category: doc.category,
        sourceTable: doc.wallet,
        sourceId: doc.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      developer.log('shareDocument failed', name: 'vault', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _busyDocId = null;
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
        return; // cancelled - not an error
      }

      // Upload into the caller's OWN storage folder first. A vault share is a
      // grant on an object you own; it never writes into anyone else's space.
      final objectPath = await _docs.uploadFile(path);
      final file = File(path);
      final name = path.split(RegExp(r'[\\/]')).last;

      await _repo.shareDocument(
        vaultId: widget.vaultId,
        objectPath: objectPath,
        name: name,
        sizeBytes: await file.length(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      developer.log('upload+share failed', name: 'vault', error: e, stackTrace: st);
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
    final visible = _visible;
    final busy = _uploading || _busyDocId != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
                color: AppColors.tealPale,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add to ${widget.vaultName}',
                      style:
                          AppText.title.copyWith(color: palette.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    'Everyone in this vault will be able to view and open what '
                    'you add. Remove them, or withdraw the document, and their '
                    'access ends immediately.',
                    style: AppText.caption
                        .copyWith(color: palette.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Upload straight from the device.
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _uploadAndShare,
                      icon: _uploading
                          ?  SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryGreen),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 20),
                      label: Text(_uploading
                          ? 'Uploading…'
                          : 'Upload from this device'),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: AppText.caption
                            .copyWith(color: AppColors.critical, height: 1.35)),
                  ],

                  const SizedBox(height: AppSpacing.lg),
                  Text('Or choose from your documents',
                      style: AppText.subtitle
                          .copyWith(color: palette.textPrimary, fontSize: 14)),
                  const SizedBox(height: AppSpacing.sm),
                  if (_all.length > 6)
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search your documents',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ?  Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: AppColors.primaryGreen),
                    )
                  : visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _all.isEmpty
                                  ? 'None of your documents have a stored file '
                                      'yet. Upload one above, or add documents '
                                      'to a wallet first.'
                                  : 'No documents match that search.',
                              textAlign: TextAlign.center,
                              style: AppText.body.copyWith(
                                  color: palette.textSecondary, height: 1.45),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final d = visible[i];
                            final isBusy = _busyDocId == d.id;
                            return InkWell(
                              onTap: busy ? null : () => _shareExisting(d),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: palette.surfaceVariant,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.card),
                                  border: Border.all(color: palette.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: AppColors.tealMist,
                                        borderRadius:
                                            BorderRadius.circular(11),
                                      ),
                                      child:  Icon(
                                          Icons.description_rounded,
                                          size: 19,
                                          color: AppColors.primaryGreen),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.subtitle.copyWith(
                                                color: palette.textPrimary,
                                                fontSize: 14.5),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              d.wallet,
                                              if ((d.category ?? '').isNotEmpty)
                                                d.category!,
                                            ].join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.caption.copyWith(
                                                color: palette.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isBusy)
                                       SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.primaryGreen),
                                      )
                                    else
                                      Icon(Icons.add_circle_outline_rounded,
                                          size: 20, color: palette.textFaint),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
