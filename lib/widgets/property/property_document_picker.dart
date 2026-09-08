import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document.dart';
import '../../models/property_models.dart';
import '../../repositories/document_repository.dart';
import '../../services/document_protection_store.dart';
import '../../services/document_scanner_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/gallery_import_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';
import '../wallet_modules/module_kit.dart';

/// Opens the complete Property Document Picker flow:
/// 1. Source selection (Scanner, Gallery, PDF/File, Vault)
/// 2. Pick file or link vault document
/// 3. Document Details & Biometric Protection confirmation sheet
///
/// Returns the constructed [PropertyAttachment], or `null` if cancelled.
Future<PropertyAttachment?> showPropertyAttachmentPicker(
  BuildContext context, {
  PropertyDocKind? initialKind,
}) async {
  return showModalBottomSheet<PropertyAttachment>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PropertyDocumentPickerSheet(initialKind: initialKind),
  );
}

enum _PickerSource { scan, gallery, file, vault }

class _PropertyDocumentPickerSheet extends StatefulWidget {
  const _PropertyDocumentPickerSheet({this.initialKind});

  final PropertyDocKind? initialKind;

  @override
  State<_PropertyDocumentPickerSheet> createState() =>
      _PropertyDocumentPickerSheetState();
}

class _PropertyDocumentPickerSheetState
    extends State<_PropertyDocumentPickerSheet> {
  bool _busy = false;

  Future<void> _pickSource(_PickerSource source) async {
    setState(() => _busy = true);

    try {
      String? localPath;
      String? originalName;
      int? fileSize;
      String? mimeType;
      String? linkedDocId;
      PropertyDocKind chosenKind = widget.initialKind ?? PropertyDocKind.custom;

      switch (source) {
        case _PickerSource.scan:
          // Try ML Kit auto scanner first; fallback to camera
          String? scanned;
          try {
            scanned = await DocumentScannerService.instance.scan();
          } catch (_) {
            scanned = null;
          }
          scanned ??= await GalleryImportService.instance.captureFromCamera();
          if (scanned == null) return;
          localPath = scanned;
          originalName = 'Scanned Document';
          break;

        case _PickerSource.gallery:
          final picked = await GalleryImportService.instance.pickImage();
          if (picked == null) return;
          localPath = picked;
          final fileName = picked.split(Platform.pathSeparator).last;
          originalName = fileName.isNotEmpty ? fileName : 'Property Image';
          break;

        case _PickerSource.file:
          final files = await FilePickerService.instance.pickDocuments();
          if (files.isEmpty) return;
          final file = files.first;
          localPath = file.path;
          originalName = file.name;
          fileSize = file.size;
          if (file.extension != null) {
            mimeType = file.extension!.toLowerCase() == 'pdf'
                ? 'application/pdf'
                : 'file/${file.extension}';
          }
          break;

        case _PickerSource.vault:
          // Show Vault Document Browser
          if (!mounted) return;
          final doc = await _showVaultPicker(context);
          if (doc == null) return;
          linkedDocId = doc.id;
          originalName = doc.name;
          if (doc.filePath != null && doc.filePath!.isNotEmpty) {
            localPath = doc.filePath;
          }
          break;
      }

      if (localPath != null && fileSize == null) {
        try {
          final f = File(localPath);
          if (f.existsSync()) {
            fileSize = f.lengthSync();
          }
        } catch (_) {}
      }

      if (!mounted) return;

      // Show configuration dialog / sheet to set document kind and biometrics
      final configured = await showModalBottomSheet<PropertyAttachment>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AttachmentConfigSheet(
          initialName: originalName ?? 'Document',
          path: localPath,
          linkedDocumentId: linkedDocId,
          fileSize: fileSize,
          mimeType: mimeType,
          initialKind: chosenKind,
        ),
      );

      if (configured != null && mounted) {
        Navigator.of(context).pop(configured);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Document?> _showVaultPicker(BuildContext context) async {
    return showModalBottomSheet<Document>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _VaultDocumentPickerModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('attachDocument'),
                        style: AppText.title.copyWith(
                          color: palette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Add deeds, tax receipts, building plans, or agreements',
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xFF0891B2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // 4 Grid Options
            Row(
              children: [
                Expanded(
                  child: _SourceTile(
                    title: l10n.t('scanDocument'),
                    subtitle: 'Camera / ML Scanner',
                    icon: Icons.document_scanner_rounded,
                    accent: AppColors.primaryGreen,
                    onTap: _busy ? null : () => _pickSource(_PickerSource.scan),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _SourceTile(
                    title: 'Gallery',
                    subtitle: 'Photos & Images',
                    icon: Icons.photo_library_rounded,
                    accent: const Color(0xFF0284C7),
                    onTap:
                        _busy ? null : () => _pickSource(_PickerSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _SourceTile(
                    title: 'PDF & Files',
                    subtitle: 'PDFs, Docs, Records',
                    icon: Icons.picture_as_pdf_rounded,
                    accent: const Color(0xFFE11D48),
                    onTap: _busy ? null : () => _pickSource(_PickerSource.file),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _SourceTile(
                    title: 'From Vault',
                    subtitle: 'Link Existing Docs',
                    icon: Icons.folder_shared_rounded,
                    accent: const Color(0xFF8B5CF6),
                    onTap:
                        _busy ? null : () => _pickSource(_PickerSource.vault),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: PressableScale(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: palette.surfaceVariant.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border.withValues(alpha: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: AppText.body.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppText.caption.copyWith(
                  color: palette.textFaint,
                  fontSize: 11.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal configuration sheet allowing user to edit document name, select kind,
/// and enable Biometric Protection before attaching.
class _AttachmentConfigSheet extends StatefulWidget {
  const _AttachmentConfigSheet({
    required this.initialName,
    this.path,
    this.linkedDocumentId,
    this.fileSize,
    this.mimeType,
    this.initialKind = PropertyDocKind.custom,
  });

  final String initialName;
  final String? path;
  final String? linkedDocumentId;
  final int? fileSize;
  final String? mimeType;
  final PropertyDocKind initialKind;

  @override
  State<_AttachmentConfigSheet> createState() => _AttachmentConfigSheetState();
}

class _AttachmentConfigSheetState extends State<_AttachmentConfigSheet> {
  late final TextEditingController _nameController;
  late PropertyDocKind _kind;
  bool _isBiometricProtected = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final id = 'att_${DateTime.now().microsecondsSinceEpoch}';
    if (_isBiometricProtected) {
      DocumentProtectionStore.instance.setProtected(id, true);
    }

    final attachment = PropertyAttachment(
      id: id,
      kind: _kind,
      name: name,
      path: widget.path,
      linkedDocumentId: widget.linkedDocumentId,
      addedAt: DateTime.now(),
      isBiometricProtected: _isBiometricProtected,
      fileSize: widget.fileSize,
      mimeType: widget.mimeType,
    );

    Navigator.of(context).pop(attachment);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.large),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Document Details',
                style: AppText.title.copyWith(
                  color: palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Document Name Field
              ModuleField(
                label: 'Document Title',
                controller: _nameController,
                hint: 'e.g. Sale Deed 2026',
                autofocus: false,
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: AppSpacing.sm),
              Text(
                'Document Category',
                style: AppText.label.copyWith(
                  color: palette.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),

              // Category selector chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in PropertyDocKind.values)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _kind = k;
                          if (_nameController.text.trim().isEmpty ||
                              _nameController.text == 'Document' ||
                              _nameController.text == 'Scanned Document') {
                            _nameController.text = k.localizedLabel(l10n);
                          }
                        });
                      },
                      child: PressableScale(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: _kind == k
                                ? AppColors.primaryGreen
                                    .withValues(alpha: 0.15)
                                : palette.surfaceVariant,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: _kind == k
                                  ? AppColors.primaryGreen
                                  : palette.border,
                              width: _kind == k ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                k.icon,
                                size: 15,
                                color: _kind == k
                                    ? AppColors.primaryGreen
                                    : palette.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                k.localizedLabel(l10n),
                                style: AppText.caption.copyWith(
                                  color: _kind == k
                                      ? AppColors.primaryGreen
                                      : palette.textPrimary,
                                  fontWeight: _kind == k
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Biometric Lock Toggle
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _isBiometricProtected
                      ? AppColors.primaryGreen.withValues(alpha: 0.10)
                      : palette.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: _isBiometricProtected
                        ? AppColors.primaryGreen.withValues(alpha: 0.45)
                        : palette.border,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _isBiometricProtected
                            ? AppColors.primaryGreen.withValues(alpha: 0.20)
                            : palette.surface,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _isBiometricProtected
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        size: 18,
                        color: _isBiometricProtected
                            ? AppColors.primaryGreen
                            : palette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Biometric Protection',
                            style: AppText.body.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Require fingerprint / Face ID to open and view',
                            style: AppText.caption.copyWith(
                              color: palette.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isBiometricProtected,
                      activeTrackColor: AppColors.primaryGreen,
                      onChanged: (val) {
                        HapticFeedback.selectionClick();
                        setState(() => _isBiometricProtected = val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Save Action Button
              GradientButton(
                label: 'Attach to Property',
                icon: Icons.check_circle_rounded,
                onTap: _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive Vault Document Selector Modal
class _VaultDocumentPickerModal extends StatefulWidget {
  const _VaultDocumentPickerModal();

  @override
  State<_VaultDocumentPickerModal> createState() =>
      _VaultDocumentPickerModalState();
}

class _VaultDocumentPickerModalState extends State<_VaultDocumentPickerModal> {
  final _searchController = TextEditingController();
  List<Document>? _allDocs;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadVaultDocs();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVaultDocs() async {
    try {
      final docs = await DocumentRepository.instance.listAll();
      if (mounted) {
        setState(() {
          _allDocs = docs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final filtered = (_allDocs ?? []).where((d) {
      if (_query.isEmpty) return true;
      return d.name.toLowerCase().contains(_query) ||
          d.wallet.toLowerCase().contains(_query) ||
          (d.category ?? '').toLowerCase().contains(_query);
    }).toList();

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.75,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Select from Document Vault',
              style: AppText.title.copyWith(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: palette.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: palette.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      size: 20, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: AppText.body.copyWith(color: palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search vault documents...',
                        hintStyle: AppText.caption
                            .copyWith(color: palette.textFaint),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () => _searchController.clear(),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: palette.textFaint),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // List of Documents
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF0891B2),
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded,
                                  size: 48, color: palette.textFaint),
                              const SizedBox(height: 8),
                              Text(
                                _allDocs?.isEmpty ?? true
                                    ? 'No documents in your Vault yet'
                                    : 'No matching documents found',
                                style: AppText.body.copyWith(
                                    color: palette.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            return GestureDetector(
                              onTap: () => Navigator.of(context).pop(doc),
                              child: PressableScale(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: palette.surfaceVariant
                                        .withValues(alpha: 0.5),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.chip),
                                    border: Border.all(color: palette.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryGreen
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.description_rounded,
                                          size: 18,
                                          color: Color(0xFF0891B2),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              doc.name,
                                              style: AppText.body.copyWith(
                                                color: palette.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              doc.wallet,
                                              style: AppText.caption.copyWith(
                                                color: palette.textSecondary,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                        color: Color(0xFF0891B2),
                                      ),
                                    ],
                                  ),
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
