import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/view_once_share.dart';
import '../../repositories/share_repository.dart' show ShareException;
import '../../repositories/view_once_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import 'qr_share_screen.dart' show remainingShareLabel;

/// The sender's screen for a freshly minted **view-once** link.
///
/// Deliberately close in look and feel to [QrShareScreen] - same QR card, same
/// action grid - with the differences that matter for a one-time link made
/// unmissable: a standing warning that the document opens exactly once, and a
/// live "opened yet?" indicator so the sender can see the moment it is spent.
///
/// This screen only presents and manages the link. Validation, the atomic
/// one-time gate and the signed URLs all live server-side.
class ViewOnceShareScreen extends StatefulWidget {
  const ViewOnceShareScreen({
    super.key,
    required this.share,
    this.documentName,
  });

  final ViewOnceShare share;

  /// Shown in the summary row. Optional - the share itself is the source of
  /// truth for what is accessible.
  final String? documentName;

  @override
  State<ViewOnceShareScreen> createState() => _ViewOnceShareScreenState();
}

class _ViewOnceShareScreenState extends State<ViewOnceShareScreen> {
  late ViewOnceShare _share = widget.share;
  Timer? _ticker;
  Timer? _statusPoll;
  bool _busy = false;

  // Crisp near-black for the EXPORTED PNG; softer slate on screen. Same values
  // as the regular QR screen so exported codes look identical.
  static const _qrDark = Color(0xFF04121A);
  static const _qrDisplayDark = Color(0xFF37474F);

  @override
  void initState() {
    super.initState();
    developer.log(
      'view-once link created → url=${_share.url} '
      'expires=${_share.expiryTime.toIso8601String()}',
      name: 'view-once',
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    // Cheap poll so "Opened" flips over on its own the moment the recipient
    // burns the link. Only runs while this screen is up.
    _statusPoll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _statusPoll?.cancel();
    _ticker = null;
    _statusPoll = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _share.viewed || _share.revoked) return;
    try {
      final fresh = await ViewOnceRepository.instance.fetch(_share.token);
      if (!mounted || fresh == null) return;
      if (fresh.viewed != _share.viewed || fresh.revoked != _share.revoked) {
        setState(() => _share = fresh);
      }
    } catch (_) {
      // A failed poll is not worth surfacing - the next tick tries again.
    }
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

  Future<void> _copyLink() async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _share.url));
    HapticFeedback.selectionClick();
    _toast(l10n.t('linkCopied'));
  }

  Future<void> _shareLink() async {
    final l10n = AppLocalizations.of(context);
    await Share.share(
      // The warning travels WITH the link - the recipient should know before
      // they tap that tapping spends their only view.
      '${_share.url}\n\n${l10n.t('viewOnceSenderWarning')}',
      subject: l10n.t('viewOnceShareSubject'),
      sharePositionOrigin: shareOrigin(context),
    );
  }

  Future<void> _downloadQr() async {
    if (!mounted || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final origin = shareOrigin(context);
    try {
      final bytes = await _renderQrPng(_share.url);
      if (bytes == null) {
        _toast(l10n.t('couldNotExportQr'), error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ino_view_once_${_share.token}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: l10n.t('viewOnceShareSubject'),
        text: l10n.t('viewOnceSenderWarning'),
        sharePositionOrigin: origin,
      );
    } catch (_) {
      _toast(l10n.t('couldNotExportQr'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmRevoke();
    if (confirmed != true) return;
    if (!mounted) return; // the dialog awaited - the screen may be gone
    setState(() => _busy = true);
    try {
      await ViewOnceRepository.instance.revoke(_share.token);
      if (!mounted) return;
      setState(() => _share = _share.copyWith(revoked: true));
      HapticFeedback.mediumImpact();
      _toast(l10n.t('viewOnceRevokedToast'));
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('couldNotRevokeShare'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmRevoke() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text(l10n.t('revokeViewOnceTitle'),
            style: AppText.title.copyWith(color: palette.textPrimary)),
        content: Text(l10n.t('revokeViewOnceBody'),
            style: AppText.body.copyWith(color: palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('keep'),
                style: TextStyle(color: palette.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('revoke'),
                style: const TextStyle(
                    color: AppColors.critical, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Renders the QR to a white-backed PNG (with a quiet-zone margin) so it scans
  /// reliably on any background when saved or shared.
  Future<Uint8List?> _renderQrPng(String data,
      {double moduleSize = 660, double margin = 56}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _qrDark),
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
    final l10n = AppLocalizations.of(context);
    final live = _share.isLive;
    final title = switch (_share.status) {
      ViewOnceStatus.ready => l10n.t('secureShare'),
      ViewOnceStatus.viewed => l10n.t('viewOnceOpenedTitle'),
      ViewOnceStatus.revoked => l10n.t('viewOnceRevokedTitle'),
      _ => l10n.t('shareLinkExpiredTitle'),
    };
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        sky: true,
        child: SafeArea(
          top: !divineGlassEnabled(context),
          child: Column(
            children: [
              DivineGlassAppBar(
                title: title,
                onBack: () => Navigator.of(context).pop(),
                centerTitle: false,
                includeStatusBar: true,
              ),
              Expanded(
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.lg),
                  children: [
                    if (live) _liveBody(palette) else _spentBody(palette),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveBody(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xs),
        _QrCard(url: _share.url, dark: _qrDisplayDark),
        const SizedBox(height: AppSpacing.md),
        const _OneTimePill(),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            remainingShareLabel(
                l10n, _share.expiryTime.difference(DateTime.now())),
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ),
        if (widget.documentName != null) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              widget.documentName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: palette.textFaint),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _WarningCard(text: l10n.t('viewOnceSenderWarning')),
        const SizedBox(height: AppSpacing.md),
        _LinkCard(url: _share.url, palette: palette, onCopy: _copyLink),
        const SizedBox(height: AppSpacing.md),
        _StatusRow(share: _share, palette: palette),
        const SizedBox(height: AppSpacing.lg),
        _ActionGrid(
          busy: _busy,
          onCopy: _copyLink,
          onShare: _shareLink,
          onDownload: _downloadQr,
          onRevoke: _revoke,
        ),
      ],
    );
  }

  Widget _spentBody(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final status = _share.status;
    final (icon, color, titleKey, bodyKey) = switch (status) {
      ViewOnceStatus.viewed => (
          Icons.visibility_off_rounded,
          AppColors.primaryGreen,
          'viewOnceOpenedTitle',
          'viewOnceOpenedBody',
        ),
      ViewOnceStatus.revoked => (
          Icons.link_off_rounded,
          AppColors.critical,
          'viewOnceRevokedTitle',
          'viewOnceRevokedBody',
        ),
      _ => (
          Icons.timer_off_rounded,
          AppColors.warning,
          'viewOnceExpiredTitle',
          'viewOnceExpiredBody',
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
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
          Text(l10n.t(titleKey),
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.t(bodyKey),
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary)),
          if (_share.viewedAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.t('viewOnceOpenedAt').replaceFirst(
                  '{t}', _formatTime(_share.viewedAt!)),
              style: AppText.caption.copyWith(color: palette.textFaint),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PressableScale(
            child: Material(
              color: palette.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                side: BorderSide(color: palette.border),
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                  child: Text(l10n.t('done'),
                      style:
                          AppText.subtitle.copyWith(color: palette.textPrimary)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final l10n = AppLocalizations.of(context);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${l10n.monthShort(local.month)}, $hh:$mm';
  }
}

// ---------------------------------------------------------------------------

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
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.tealPale),
          boxShadow: AppShadows.card,
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

/// The badge that makes "this is one-time" impossible to miss.
class _OneTimePill extends StatelessWidget {
  const _OneTimePill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_rounded,
                size: 16, color: AppColors.warning),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context).t('viewOnceBadge'),
              style: AppText.caption.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppText.caption
                  .copyWith(color: palette.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Not opened yet" → "Opened" the moment the recipient burns the link.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.share, required this.palette});

  final ViewOnceShare share;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final opened = share.viewed;
    final color = opened ? AppColors.primaryGreen : palette.textFaint;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          opened ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          l10n.t(opened ? 'viewOnceOpenedLabel' : 'viewOnceWaitingLabel'),
          style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
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
          Icon(Icons.link_rounded, color: AppColors.lightBlue, size: 20),
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
            tooltip: AppLocalizations.of(context).t('copyLink'),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.copy_rounded,
                label: l10n.t('copyLinkAction'),
                onTap: busy ? null : onCopy,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionButton(
                icon: Icons.ios_share_rounded,
                label: l10n.t('shareLinkAction'),
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
                label: l10n.t('downloadQr'),
                onTap: busy ? null : onDownload,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionButton(
                icon: Icons.link_off_rounded,
                label: l10n.t('revokeAccess'),
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
