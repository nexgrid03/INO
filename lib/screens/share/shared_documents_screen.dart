import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/public_share.dart';
import '../../repositories/share_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../auth/login_screen.dart';
import '../documents/add_document_screen.dart';
import 'qr_share_screen.dart' show remainingShareLabel;

/// The recipient-facing viewer for a shared link/QR — Figma **Vault Viewer**.
///
/// Fetches public metadata from the `share` Edge Function (anonymous) and shows
/// a preview + details card with Save to INO Vault / Download Copy. Files are
/// streamed through the Edge Function so storage paths are never exposed.
class SharedDocumentsScreen extends StatefulWidget {
  const SharedDocumentsScreen({super.key, required this.token});

  final String token;

  @override
  State<SharedDocumentsScreen> createState() => _SharedDocumentsScreenState();
}

class _SharedDocumentsScreenState extends State<SharedDocumentsScreen> {
  PublicShare? _share;
  bool _loading = true;
  String? _busyDocId;
  SharedDoc? _selected;
  SharedFile? _previewFile;
  bool _previewLoading = false;
  double _zoom = 1.0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final share = await ShareRepository.instance.fetchPublicShare(widget.token);
    if (!mounted) return;
    setState(() {
      _share = share;
      _loading = false;
      if (share.isActive && share.documents.length == 1) {
        _selected = share.documents.first;
      }
    });
    if (_selected != null) await _loadPreview(_selected!);
  }

  PublicShareStatus get _status {
    final s = _share;
    if (s == null) return PublicShareStatus.error;
    if (s.status == PublicShareStatus.active &&
        s.expiresAt != null &&
        s.expiresAt!.isBefore(DateTime.now())) {
      return PublicShareStatus.expired;
    }
    return s.status;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
      ),
    );
  }

  Future<void> _loadPreview(SharedDoc doc) async {
    setState(() {
      _previewLoading = true;
      _previewFile = null;
      _zoom = 1.0;
    });
    try {
      final file = await ShareRepository.instance
          .fetchSharedFile(widget.token, doc, download: false);
      if (!mounted || _selected?.id != doc.id) return;
      setState(() {
        _previewFile = file;
        _previewLoading = false;
      });
    } catch (_) {
      if (!mounted || _selected?.id != doc.id) return;
      setState(() => _previewLoading = false);
    }
  }

  Future<void> _selectDoc(SharedDoc doc) async {
    setState(() => _selected = doc);
    await _loadPreview(doc);
  }

  Future<SharedFile?> _ensureFile(SharedDoc doc) async {
    if (_previewFile != null && _selected?.id == doc.id) return _previewFile;
    return ShareRepository.instance
        .fetchSharedFile(widget.token, doc, download: true);
  }

  Future<void> _downloadCopy(SharedDoc doc) async {
    if (_busyDocId != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busyDocId = doc.id);
    final origin = shareOrigin(context);
    try {
      final file = await _ensureFile(doc);
      if (file == null) throw StateError('empty');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path, mimeType: file.mimeType, name: file.filename)],
        subject: doc.name,
        text: 'Shared with you via INO',
        sharePositionOrigin: origin,
      );
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('couldNotDownloadDoc'), error: true);
    } finally {
      if (mounted) setState(() => _busyDocId = null);
    }
  }

  Future<void> _saveToVault(SharedDoc doc) async {
    if (_busyDocId != null) return;
    final l10n = AppLocalizations.of(context);

    if (AuthService.instance.currentUser == null) {
      _toast(l10n.t('signInToSaveVault'), error: true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    setState(() => _busyDocId = doc.id);
    try {
      final file = await _ensureFile(doc);
      if (file == null) throw StateError('empty');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/ino_import_${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddDocumentScreen(
            initialWallet: 'Document Wallet',
            initialFilePath: path,
          ),
        ),
      );
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('couldNotDownloadDoc'), error: true);
    } finally {
      if (mounted) setState(() => _busyDocId = null);
    }
  }

  Future<void> _openExternally(SharedDoc doc) async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await _ensureFile(doc);
      if (file == null) return;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      final result = await OpenFilex.open(path, type: file.mimeType);
      if (result.type != ResultType.done) {
        _toast(l10n.t('noAppToOpenFile'), error: true);
      }
    } catch (_) {
      _toast(l10n.t('couldNotOpenDoc'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        sky: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VaultViewerHeader(
                title: l10n.t('vaultViewer'),
                onClose: () => Navigator.of(context).maybePop(),
              ),
              Expanded(child: _body(palette, l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(AppPalette palette, AppLocalizations l10n) {
    if (_loading) {
      return  Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    switch (_status) {
      case PublicShareStatus.active:
        return _activeBody(palette, l10n);
      case PublicShareStatus.expired:
        return _TerminalState(
          icon: Icons.timer_off_rounded,
          color: AppColors.critical,
          title: l10n.t('shareLinkExpiredTitle'),
          subtitle: l10n.t('shareLinkExpiredBody'),
          showLinkActions: true,
        );
      case PublicShareStatus.revoked:
        return _TerminalState(
          icon: Icons.link_off_rounded,
          color: AppColors.critical,
          title: l10n.t('shareLinkRevokedTitle'),
          subtitle: l10n.t('shareLinkRevokedBody'),
          showLinkActions: true,
        );
      case PublicShareStatus.notFound:
        return _TerminalState(
          icon: Icons.search_off_rounded,
          color: palette.textFaint,
          title: l10n.t('linkNotFound'),
          subtitle: l10n.t('linkNotFoundBody'),
          showLinkActions: true,
        );
      case PublicShareStatus.error:
        return _TerminalState(
          icon: Icons.cloud_off_rounded,
          color: AppColors.critical,
          title: l10n.t('couldntLoadShare'),
          subtitle: _share?.message ?? l10n.t('checkConnection'),
          onRetry: _load,
          showLinkActions: true,
        );
    }
  }

  Widget _activeBody(AppPalette palette, AppLocalizations l10n) {
    final share = _share!;
    final docs = share.documents;
    final selected = _selected;

    if (docs.isEmpty) {
      return Center(
        child: Text(l10n.t('noDocumentsYet'),
            style: AppText.body.copyWith(color: palette.textSecondary)),
      );
    }

    // Multi-doc picker before opening the viewer.
    if (selected == null) {
      return ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.lg),
        children: [
          Text(
            l10n
                .t(docs.length == 1 ? 'docCountOne' : 'docCountMany')
                .replaceFirst('{n}', '${docs.length}'),
            style: AppText.subtitle.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final d in docs) ...[
            _FilePickRow(doc: d, onTap: () => _selectDoc(d)),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }

    final busy = _busyDocId == selected.id;
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 4, AppSpacing.screen, AppSpacing.lg),
      children: [
        if (docs.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _selected = null;
                _previewFile = null;
              }),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(l10n.t('sharedDocuments')),
            ),
          ),
        _PreviewCard(
          loading: _previewLoading,
          file: _previewFile,
          zoom: _zoom,
          onZoomIn: () => setState(() => _zoom = math.min(2.5, _zoom + 0.25)),
          onZoomOut: () => setState(() => _zoom = math.max(0.75, _zoom - 0.25)),
          onFullscreen: () => _openExternally(selected),
        ),
        const SizedBox(height: AppSpacing.md),
        _DetailsCard(
          doc: selected,
          file: _previewFile,
          share: share,
          busy: busy,
          onSave: () => _saveToVault(selected),
          onDownload: () => _downloadCopy(selected),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _VaultViewerHeader extends StatelessWidget {
  const _VaultViewerHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child:  Icon(Icons.shield_rounded,
                size: 18, color: AppColors.primaryGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          PressableScale(
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context).t('close'),
                      style: AppText.caption.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close_rounded,
                        size: 16, color: palette.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.loading,
    required this.file,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFullscreen,
  });

  final bool loading;
  final SharedFile? file;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFullscreen;

  bool get _isImage {
    final mime = file?.mimeType ?? '';
    return mime.startsWith('image/');
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Page 1 of 1',
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
              const Spacer(),
              _ToolIcon(icon: Icons.zoom_out_rounded, onTap: onZoomOut),
              _ToolIcon(icon: Icons.zoom_in_rounded, onTap: onZoomIn),
              _ToolIcon(
                  icon: Icons.open_in_full_rounded, onTap: onFullscreen),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: loading
                ?  Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryGreen),
                  )
                : file == null
                    ? Center(
                        child: Icon(Icons.description_outlined,
                            size: 48, color: palette.textFaint),
                      )
                    : InteractiveViewer(
                        minScale: 0.75,
                        maxScale: 3,
                        child: Transform.scale(
                          scale: zoom,
                          child: _isImage
                              ? Image.memory(file!.bytes, fit: BoxFit.contain)
                              : _PdfPlaceholder(filename: file!.filename),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PdfPlaceholder extends StatelessWidget {
  const _PdfPlaceholder({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text(
            'CONFIDENTIAL',
            style: TextStyle(
              color: AppColors.primaryGreen,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filename,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[
            Container(
              height: 8,
              margin: EdgeInsets.only(bottom: 8, right: i == 3 ? 40 : 0),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
          const Spacer(),
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bar_chart_rounded,
                color: Color(0xFF94A3B8), size: 28),
          ),
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: AppPalette.of(context).textSecondary),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.doc,
    required this.file,
    required this.share,
    required this.busy,
    required this.onSave,
    required this.onDownload,
  });

  final SharedDoc doc;
  final SharedFile? file;
  final PublicShare share;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onDownload;

  String get _sizeLabel {
    final b = file?.bytes.length ?? 0;
    if (b <= 0) return doc.type;
    if (b >= 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB · ${doc.type}';
    }
    if (b >= 1024) return '${(b / 1024).round()} KB · ${doc.type}';
    return '$b B · ${doc.type}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ownerName = share.ownerName;
    final ownerEmail = share.ownerEmail;
    final initial = (ownerName == null || ownerName.trim().isEmpty)
        ? 'I'
        : ownerName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p[0])
            .join()
            .toUpperCase();

    final expiryParts = <String>[];
    if (share.sharedOnLabel != null) {
      expiryParts.add('Shared on ${share.sharedOnLabel}');
    }
    if (share.expiresAt != null) {
      final d = share.expiresAt!.difference(DateTime.now());
      if (!d.isNegative) {
        expiryParts.add(remainingShareLabel(l10n, d));
      }
    }

    return InoCard(
      radius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A574),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: AppText.title.copyWith(
                        color: palette.textPrimary,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _sizeLabel,
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.t('sharedBy').toUpperCase(),
            style: AppText.caption.copyWith(
              color: palette.textFaint,
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.tealMist,
                child: Text(
                  initial,
                  style:  TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName ?? 'INO Share',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    if (ownerEmail != null && ownerEmail.isNotEmpty)
                      Text(
                        ownerEmail,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (expiryParts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 15, color: palette.textFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    expiryParts.join(' · '),
                    style: AppText.caption
                        .copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Icon(Icons.lock_rounded,
                    size: 16, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.t('viewOnlyRestricted'),
                    style: AppText.caption.copyWith(
                      color: AppColors.darkGreen,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (busy)
             Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: AppColors.primaryGreen),
              ),
            )
          else ...[
            _CtaButton(
              icon: Icons.download_for_offline_rounded,
              label: l10n.t('saveToInoVault'),
              filled: true,
              onTap: onSave,
            ),
            const SizedBox(height: 10),
            _CtaButton(
              icon: Icons.download_rounded,
              label: l10n.t('downloadCopy'),
              filled: false,
              onTap: onDownload,
            ),
          ],
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.primaryGreen : palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: filled
                ? null
                : Border.all(color: AppColors.primaryGreen, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: filled ? Colors.white : AppColors.primaryGreen),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : AppColors.primaryGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePickRow extends StatelessWidget {
  const _FilePickRow({required this.doc, required this.onTap});

  final SharedDoc doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: InoCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tealMist,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:  Icon(Icons.description_rounded,
                    color: AppColors.primaryGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    Text(doc.type,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalState extends StatelessWidget {
  const _TerminalState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onRetry,
    this.showLinkActions = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  final bool showLinkActions;

  Future<void> _requestNewLink() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@ino.app',
      queryParameters: {'subject': 'Request new INO share link'},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _returnToDashboard(BuildContext context) async {
    final uri = Uri.parse('https://inoapp.in');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: color),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(
                      color: palette.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: AppText.body
                      .copyWith(color: palette.textSecondary, height: 1.45)),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                PressableScale(
                  child: Material(
                    color: AppColors.primaryGreen,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      onTap: onRetry,
                      child: SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: Center(
                          child: Text(l10n.t('tryAgain'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (showLinkActions) ...[
                const SizedBox(height: AppSpacing.md),
                PressableScale(
                  child: Material(
                    color: AppColors.primaryGreen,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      onTap: _requestNewLink,
                      child: SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: Center(
                          child: Text(l10n.t('requestNewLink'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                PressableScale(
                  child: Material(
                    color: palette.surface,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      side: BorderSide(color: AppColors.primaryGreen
                          .withValues(alpha: 0.35)),
                    ),
                    child: InkWell(
                      onTap: () => _returnToDashboard(context),
                      child: SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: Center(
                          child: Text(l10n.t('returnToDashboard'),
                              style: AppText.subtitle.copyWith(
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
