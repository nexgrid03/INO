import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/property_models.dart';
import '../../models/wallet_detail_models.dart';
import '../../services/document_pdf_service.dart';
import '../../services/document_protection_store.dart';
import '../../services/property_store.dart';
import '../../services/screen_security_service.dart';
import '../../services/vault_guard.dart';
import '../../services/wallet_media_sync.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/ino_loader.dart';
import '../../widgets/common/wallet_media_image.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import '../share/share_settings_screen.dart';

/// Full-screen viewer for property documents and attachments.
///
/// Features:
/// - Screen security enabled (app-switcher masking and iOS capture
///   detection). Screenshots are NOT blocked - INO allows them everywhere
///   except the Family Vault.
/// - Pinch-to-zoom & pan for images
/// - System PDF & file launcher via [OpenFilex]
/// - Biometric protection lock/unlock toggle
/// - File sharing via [SharePlus]
/// - Remove attachment capability
class PropertyAttachmentViewerScreen extends StatefulWidget {
  const PropertyAttachmentViewerScreen({
    super.key,
    required this.propertyId,
    required this.attachment,
  });

  final String propertyId;
  final PropertyAttachment attachment;

  @override
  State<PropertyAttachmentViewerScreen> createState() =>
      _PropertyAttachmentViewerScreenState();
}

class _PropertyAttachmentViewerScreenState
    extends State<PropertyAttachmentViewerScreen> {
  final TransformationController _transformController =
      TransformationController();
  late PropertyAttachment _attachment = widget.attachment;
  int _rotationQuarterTurns = 0;
  bool _openingFile = false;

  @override
  void initState() {
    super.initState();
    ScreenSecurityService.instance.enable();
  }

  @override
  void dispose() {
    ScreenSecurityService.instance.disable();
    _transformController.dispose();
    super.dispose();
  }

  bool get _isProtected =>
      _attachment.isBiometricProtected ||
      DocumentProtectionStore.instance.isProtected(_attachment.id);

  Future<void> _toggleBiometricProtection() async {
    final currentlyProtected = _isProtected;

    // Authenticate before toggling protection
    final ok = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: currentlyProtected
          ? 'Authenticate to unlock this document'
          : 'Authenticate to protect this document with biometrics',
      title: 'Biometric Verification',
    );
    if (!ok || !mounted) return;

    final updatedProtection = !currentlyProtected;
    await DocumentProtectionStore.instance
        .setProtected(_attachment.id, updatedProtection);

    final updatedAttachment =
        _attachment.copyWith(isBiometricProtected: updatedProtection);

    // Persist to property store
    final property = PropertyStore.instance.byId(widget.propertyId);
    if (property != null) {
      final updatedAttachments = property.attachments.map((a) {
        return a.id == _attachment.id ? updatedAttachment : a;
      }).toList();

      final updatedProperty =
          property.copyWith(attachments: updatedAttachments);
      await PropertyStore.instance.update(updatedProperty);
    }

    if (mounted) {
      setState(() => _attachment = updatedAttachment);
      showModuleToast(
        context,
        updatedProtection
            ? 'Biometric protection enabled'
            : 'Biometric protection removed',
      );
    }
  }

  DocumentRecord _toDocumentRecord() {
    final l10n = AppLocalizations.of(context);
    final now = _attachment.addedAt ?? DateTime.now();
    return DocumentRecord(
      id: _attachment.linkedDocumentId ?? _attachment.id,
      name: _attachment.name,
      category: _attachment.kind.localizedLabel(l10n),
      icon: _attachment.isImage
          ? Icons.image_rounded
          : Icons.description_rounded,
      uploadedAt: now,
      updatedAt: now,
      status: DocumentStatus.active,
      filePath: _attachment.path,
      notes: null,
      tags: const [],
      isFavorite: false,
    );
  }

  void _shareFile() {
    final path = _attachment.path;
    if (path == null || path.isEmpty) {
      showModuleToast(context, 'No file available to share', error: true);
      return;
    }

    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final record = _toDocumentRecord();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded,
                    color: Color(0xFF0284C7)),
                title: Text(l10n.t('shareViaQr').isNotEmpty
                    ? l10n.t('shareViaQr')
                    : 'Share via QR'),
                subtitle: const Text('Generate a secure time-limited QR code'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShareSettingsScreen(documents: [record]),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFFEF4444)),
                title: Text(l10n.t('shareAsPdf').isNotEmpty
                    ? l10n.t('shareAsPdf')
                    : 'Share as PDF'),
                subtitle: const Text('Export original quality PDF to any app'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final origin = shareOrigin(context);
                  showModuleToast(
                    context,
                    l10n.t('preparingPdf').isNotEmpty
                        ? l10n.t('preparingPdf')
                        : 'Preparing PDF...',
                  );
                  final success =
                      await DocumentPdfService.instance.shareDocumentAsPdf(
                    record,
                    sharePositionOrigin: origin,
                  );
                  if (!success && mounted) {
                    showModuleToast(context, 'Unable to share as PDF',
                        error: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded,
                    color: Color(0xFF10B981)),
                title: const Text('Share Original File'),
                subtitle: const Text('Share file directly via system apps'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareRawFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareRawFile() async {
    final path = _attachment.path;
    if (path == null || path.isEmpty) {
      showModuleToast(context, 'No file available to share', error: true);
      return;
    }

    final file = await WalletMediaSync.instance.resolve(path);
    if (!mounted) return;
    if (file == null) {
      showModuleToast(context, 'File could not be loaded', error: true);
      return;
    }

    try {
      final origin = shareOrigin(context);
      await Share.shareXFiles(
        [XFile(file.path, name: _attachment.name)],
        text: _attachment.name,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        showModuleToast(context, 'Unable to share document', error: true);
      }
    }
  }

  Future<void> _openWithSystemApp() async {
    final path = _attachment.path;
    if (path == null || path.isEmpty) {
      showModuleToast(context, 'No file available', error: true);
      return;
    }

    setState(() => _openingFile = true);
    try {
      final file = await WalletMediaSync.instance.resolve(path);
      if (file == null) {
        if (mounted) {
          showModuleToast(context, 'File could not be loaded', error: true);
        }
        return;
      }
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        showModuleToast(
          context,
          result.message.isNotEmpty
              ? result.message
              : 'Could not open document viewer',
          error: true,
        );
      }
    } catch (_) {
      if (mounted) {
        showModuleToast(context, 'Failed to open file viewer', error: true);
      }
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  Future<void> _deleteAttachment() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove Document',
      message:
          'Are you sure you want to remove "${_attachment.name}" from this property?',
      confirmLabel: l10n.t('delete'),
    );
    if (!confirmed || !mounted) return;

    final property = PropertyStore.instance.byId(widget.propertyId);
    if (property != null) {
      final updatedAttachments =
          property.attachments.where((a) => a.id != _attachment.id).toList();
      final updatedProperty =
          property.copyWith(attachments: updatedAttachments);
      await PropertyStore.instance.update(updatedProperty);
    }

    await DocumentProtectionStore.instance.setProtected(_attachment.id, false);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final isImg = _attachment.isImage;
    final path = _attachment.path;
    // A stored attachment is an object path, not a file on this device, so an
    // existsSync() here reported every synced attachment as missing. Presence
    // of a path is the test; the viewers below resolve it.
    final exists = path != null &&
        path.isNotEmpty &&
        (WalletMediaSync.isRemote(path) || WalletMediaSync.isLocalFile(path));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context, palette, l10n),

            // Main Viewer Canvas
            Expanded(
              child: !exists
                  ? _buildMissingFileView(palette)
                  : isImg
                      ? _buildImageView(path)
                      : _buildDocumentView(palette, path),
            ),

            // Bottom Info & Controls Bar
            _buildBottomControls(palette, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
      BuildContext context, AppPalette palette, AppLocalizations l10n) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 6,
        12,
        8,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _attachment.name,
                        style: AppText.title.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isProtected) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen
                              .withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: AppColors.primaryGreen
                                .withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded,
                                size: 11, color: AppColors.primaryGreen),
                            const SizedBox(width: 3),
                            Text(
                              'Locked',
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  _attachment.kind.localizedLabel(l10n),
                  style: AppText.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_attachment.isImage)
            IconButton(
              icon: const Icon(Icons.rotate_right_rounded,
                  color: Colors.white, size: 22),
              tooltip: 'Rotate',
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.share_rounded,
                color: Colors.white, size: 20),
            tooltip: 'Share',
            onPressed: _shareFile,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFEF4444), size: 22),
            tooltip: 'Delete',
            onPressed: _deleteAttachment,
          ),
        ],
      ),
    );
  }

  Widget _buildImageView(String path) {
    return Center(
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 0.5,
        maxScale: 5.0,
        child: RotatedBox(
          quarterTurns: _rotationQuarterTurns,
          child: WalletMediaImage(
            path: path,
            fit: BoxFit.contain,
            // Full-screen and pinch-zoomable: decode within the texture limit
            // or a full-resolution photo paints nothing at all.
            zoomable: true,
            loading: const Center(child: InoLoader(color: Colors.white)),
            fallback: const Center(
              child: Text(
                'Failed to load image',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentView(AppPalette palette, String path) {
    final l10n = AppLocalizations.of(context);
    final ext = _attachment.fileExtension.toUpperCase();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _attachment.isPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.description_rounded,
                  size: 38,
                  color: const Color(0xFFE11D48),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _attachment.name,
                style: AppText.headline.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (ext.isNotEmpty) ext,
                  if (_attachment.formattedSize != null)
                    _attachment.formattedSize!,
                  _attachment.kind.localizedLabel(l10n),
                ].join(' · '),
                style: AppText.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: _openingFile ? 'Opening...' : 'Open in PDF Viewer',
                icon: Icons.open_in_new_rounded,
                onTap: _openingFile ? null : _openWithSystemApp,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _shareFile,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share Document'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side:
                      BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMissingFileView(AppPalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded,
              size: 54, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'Document file not found on device',
            style: AppText.body
                .copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 4),
          Text(
            'The file may have been moved or deleted.',
            style: AppText.caption
                .copyWith(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(AppPalette palette, AppLocalizations l10n) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Biometric Toggle Button
          Expanded(
            child: GestureDetector(
              onTap: _toggleBiometricProtection,
              child: PressableScale(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isProtected
                        ? AppColors.primaryGreen.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: _isProtected
                          ? AppColors.primaryGreen.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isProtected
                            ? Icons.fingerprint_rounded
                            : Icons.lock_open_rounded,
                        size: 18,
                        color: _isProtected
                            ? AppColors.primaryGreen
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _isProtected ? 'Protected' : 'Protect with Biometrics',
                          style: AppText.caption.copyWith(
                            color: _isProtected
                                ? AppColors.primaryGreen
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_attachment.isImage) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _openWithSystemApp,
              child: PressableScale(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_new_rounded,
                          size: 17, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Open with...',
                        style: AppText.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
