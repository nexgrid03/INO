import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/document_share.dart';
import '../../models/wallet_detail_models.dart';
import '../../repositories/share_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import 'shared_documents_screen.dart';

/// QR Share screen — the generated share, ready to hand out.
///
/// Shows the large QR, live expiry, the shared-document count, and the four
/// owner actions: Copy Link, Share Link, Download QR, Revoke Access. A live
/// ticker keeps the expiry honest and flips the screen to an "expired" state
/// the moment it lapses; revoking flips it to a "revoked" state. All access
/// (validation, signed URLs, analytics) is enforced server-side by the `share`
/// Edge Function — this screen only presents and manages the share.
class QrShareScreen extends StatefulWidget {
  const QrShareScreen({
    super.key,
    required this.share,
    this.documents = const [],
  });

  final DocumentShare share;

  /// The documents included (for the on-screen summary). Optional — the share
  /// itself is the source of truth for what's accessible.
  final List<DocumentRecord> documents;

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen> {
  late DocumentShare _share = widget.share;
  Timer? _ticker;
  bool _busy = false;

  static const _qrDark = Color(0xFF04121A);

  @override
  void initState() {
    super.initState();
    developer.log(
      'QR share opened → id=${_share.shareId} url=${_share.url} '
      'docs=${_share.documentCount} expires=${_share.expiresAt.toIso8601String()}',
      name: 'share',
    );
    // Refresh the countdown every second; cheap and only while this screen is up.
    // Guarded by `mounted` and cancelled in dispose() so it can never call
    // setState() after the screen is gone.
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

  ShareStatus get _status => _share.effectiveStatus;

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

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _share.url));
    HapticFeedback.selectionClick();
    _toast('Link copied to clipboard');
  }

  Future<void> _shareLink() async {
    await Share.share(
      _share.url,
      subject: 'Documents shared with you via INO',
    );
  }

  Future<void> _downloadQr() async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _renderQrPng(_share.url);
      if (bytes == null) {
        _toast('Could not export the QR image.', error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ino_share_${_share.shareId}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'INO share QR code',
        text: 'Scan this QR to view the shared documents.',
      );
    } catch (_) {
      _toast('Could not export the QR image.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy) return;
    final confirmed = await _confirmRevoke();
    if (confirmed != true) return;
    // The confirm dialog awaited above — the screen may be gone now.
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ShareRepository.instance.revoke(_share.shareId);
      if (!mounted) return;
      setState(() => _share = _share.copyAsRevoked());
      HapticFeedback.mediumImpact();
      _toast('Share revoked — the link no longer works');
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not revoke the share. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmRevoke() {
    final palette = AppPalette.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text('Revoke access?',
            style: AppText.title.copyWith(color: palette.textPrimary)),
        content: Text(
          'Anyone who already has this QR or link will immediately lose access. '
          'This cannot be undone.',
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep',
                style: TextStyle(color: palette.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke',
                style: TextStyle(
                    color: AppColors.critical, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Renders the QR to a white-backed PNG (with a quiet-zone margin) so it
  /// scans reliably on any background when saved or shared.
  Future<Uint8List?> _renderQrPng(String data,
      {double moduleSize = 660, double margin = 56}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square, color: _qrDark),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: _qrDark),
    );
    final full = moduleSize + margin * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, full, full), Paint()..color = Colors.white);
    canvas.translate(margin, margin);
    painter.paint(canvas, Size(moduleSize, moduleSize));
    final image =
        await recorder.endRecording().toImage(full.toInt(), full.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              status: _status,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.lg),
                children: [
                  if (_status == ShareStatus.active)
                    _activeBody(palette)
                  else
                    _inactiveBody(palette),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeBody(AppPalette palette) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xs),
        _QrCard(url: _share.url, dark: _qrDark),
        const SizedBox(height: AppSpacing.md),
        _ExpiryPill(share: _share),
        const SizedBox(height: AppSpacing.sm),
        _DocCountRow(count: _share.documentCount, palette: palette),
        const SizedBox(height: AppSpacing.lg),
        _LinkCard(url: _share.url, palette: palette, onCopy: _copyLink),
        const SizedBox(height: AppSpacing.lg),
        _ActionGrid(
          busy: _busy,
          onCopy: _copyLink,
          onShare: _shareLink,
          onDownload: _downloadQr,
          onRevoke: _revoke,
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton.icon(
            onPressed: _preview,
            icon: const Icon(Icons.visibility_rounded,
                size: 18, color: AppColors.primaryGreen),
            label: Text('Preview what recipients see',
                style: AppText.subtitle.copyWith(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  void _preview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedDocumentsScreen(token: _share.token),
      ),
    );
  }

  Widget _inactiveBody(AppPalette palette) {
    final revoked = _status == ShareStatus.revoked;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: (revoked ? AppColors.critical : AppColors.warning)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              revoked ? Icons.link_off_rounded : Icons.timer_off_rounded,
              size: 44,
              color: revoked ? AppColors.critical : AppColors.warning,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            revoked ? 'This share has been revoked.' : 'This shared link has expired.',
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No documents are accessible through this QR anymore.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          PressableScale(
            child: Material(
              color: palette.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                side: BorderSide(color: palette.border),
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                  child: Text('Done',
                      style: AppText.subtitle
                          .copyWith(color: palette.textPrimary)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.onClose});

  final ShareStatus status;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final title = switch (status) {
      ShareStatus.active => 'Share Ready',
      ShareStatus.revoked => 'Share Revoked',
      ShareStatus.expired => 'Share Expired',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onClose,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.close_rounded,
                      size: 22, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text('Anyone can scan to view the shared documents',
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.url, required this.dark});

  final String url;
  final Color dark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: QrImageView(
          data: url,
          version: QrVersions.auto,
          size: 226,
          backgroundColor: Colors.white,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: dark),
          dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square, color: dark),
        ),
      ),
    );
  }
}

class _ExpiryPill extends StatelessWidget {
  const _ExpiryPill({required this.share});

  final DocumentShare share;

  @override
  Widget build(BuildContext context) {
    final remaining = share.expiresAt.difference(DateTime.now());
    final label = _remainingLabel(remaining);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded,
                size: 16, color: AppColors.primaryGreen),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.caption.copyWith(
                color: AppColors.darkGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _remainingLabel(Duration d) {
    if (d.isNegative) return 'Expired';
    if (d.inHours >= 24) {
      final days = d.inDays;
      return 'Expires in $days day${days == 1 ? '' : 's'}';
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return 'Expires in ${h}h ${m}m';
    if (m > 0) return 'Expires in ${m}m ${s}s';
    return 'Expires in ${s}s';
  }
}

class _DocCountRow extends StatelessWidget {
  const _DocCountRow({required this.count, required this.palette});

  final int count;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$count document${count == 1 ? '' : 's'} shared',
        style: AppText.caption.copyWith(color: palette.textSecondary),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard(
      {required this.url, required this.palette, required this.onCopy});

  final String url;
  final AppPalette palette;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return InoCard(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      onTap: onCopy,
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: AppColors.lightBlue, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
          IconButton(
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded, size: 18, color: palette.textFaint),
            tooltip: 'Copy link',
          ),
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.busy,
    required this.onCopy,
    required this.onShare,
    required this.onDownload,
    required this.onRevoke,
  });

  final bool busy;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy Link',
                onTap: busy ? null : onCopy,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionButton(
                icon: Icons.ios_share_rounded,
                label: 'Share Link',
                onTap: busy ? null : onShare,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.download_rounded,
                label: 'Download QR',
                onTap: busy ? null : onDownload,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionButton(
                icon: Icons.link_off_rounded,
                label: 'Revoke Access',
                danger: true,
                onTap: busy ? null : onRevoke,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = danger ? AppColors.critical : AppColors.primaryGreen;
    return PressableScale(
      child: Material(
        color: palette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: BorderSide(
              color: danger
                  ? AppColors.critical.withValues(alpha: 0.35)
                  : palette.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
