import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/view_once_share.dart';
import '../../repositories/share_repository.dart' show ShareException;
import '../../repositories/view_once_repository.dart';
import '../../services/screen_security_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';

/// The recipient-facing viewer for a **view-once** link.
///
/// The whole design turns on one rule: **loading this screen must not spend the
/// view.** Opening the app from a notification, a mis-tap, a rebuild or a retry
/// can never burn the link - only the recipient pressing "Open once" does.
///
/// So there are two phases:
///
///   1. **Gate** - a non-consuming [ViewOnceRepository.peek] tells us whether a
///      view remains, and the recipient is warned before they spend it.
///   2. **Open** - one [ViewOnceRepository.claim] burns the token atomically
///      server-side and returns a short-lived key; the bytes are then streamed
///      and held **in memory**, never written to disk.
///
/// Screen-capture protection is on for the entire life of this screen (see
/// [ScreenSecurityService]): real blocking on Android via `FLAG_SECURE`, and on
/// iOS the best the platform allows - app-switcher masking plus live
/// screen-recording and screenshot detection, which hide the document.
class ViewOnceViewerScreen extends StatefulWidget {
  const ViewOnceViewerScreen({super.key, required this.token});

  /// The one-time token from the `/v/<token>` link.
  final String token;

  @override
  State<ViewOnceViewerScreen> createState() => _ViewOnceViewerScreenState();
}

enum _Phase { loading, gate, opening, open, spent }

class _ViewOnceViewerScreenState extends State<ViewOnceViewerScreen> {
  _Phase _phase = _Phase.loading;
  ViewOncePeek _peek = ViewOncePeek.errored;
  ViewOnceClaim? _claim;
  ViewOnceFile? _file;
  String? _error;

  /// Set when a screenshot is detected on iOS (Android blocks them outright).
  bool _screenshotSeen = false;

  /// True while iOS reports the screen is being recorded/mirrored. The document
  /// is hidden behind a notice for as long as this holds.
  bool _capturing = false;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Protection goes on IMMEDIATELY - before any document can appear, and even
    // while the gate is showing (the file name alone is worth protecting).
    ScreenSecurityService.instance.enable();
    ScreenSecurityService.instance.screenshotTaken.addListener(_onScreenshot);
    ScreenSecurityService.instance.captureDetected.addListener(_onCaptureChanged);
    _loadPeek();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase != _Phase.gate) return;
      setState(() {}); // keep the expiry countdown honest
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    ScreenSecurityService.instance.screenshotTaken.removeListener(_onScreenshot);
    ScreenSecurityService.instance.captureDetected
        .removeListener(_onCaptureChanged);
    ScreenSecurityService.instance.disable();
    super.dispose();
  }

  void _onScreenshot() {
    if (!mounted) return;
    setState(() => _screenshotSeen = true);
    developer.log('screenshot taken on a view-once document', name: 'view-once');
  }

  void _onCaptureChanged() {
    if (!mounted) return;
    setState(() => _capturing = ScreenSecurityService.instance.captureDetected.value);
  }

  /// NON-CONSUMING. Safe on every entry to the screen.
  Future<void> _loadPeek() async {
    if (!mounted) return;
    setState(() => _phase = _Phase.loading);
    final peek = await ViewOnceRepository.instance.peek(widget.token);
    if (!mounted) return;
    setState(() {
      _peek = peek;
      _phase = peek.status.isReady ? _Phase.gate : _Phase.spent;
    });
  }

  /// THE one-way door. Burns the token, then fetches the bytes with the grant it
  /// returned. Guarded so a double-tap can't fire it twice.
  Future<void> _open() async {
    if (_phase == _Phase.opening || _phase == _Phase.open) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _phase = _Phase.opening;
      _error = null;
    });
    HapticFeedback.mediumImpact();

    final result = await ViewOnceRepository.instance.claim(widget.token);
    if (!mounted) return;

    if (!result.isClaimed) {
      // An `error` status is ambiguous (the claim may not have landed) - let the
      // recipient retry. Anything else is terminal.
      if (result.status == ViewOnceStatus.error) {
        setState(() {
          _phase = _Phase.gate;
          _error = l10n.t('viewOnceCouldNotOpen');
        });
      } else {
        setState(() {
          _phase = _Phase.spent;
          _peek = ViewOncePeek(status: result.status, message: result.message);
        });
      }
      return;
    }

    final claim = result.claim!;
    try {
      final file = await ViewOnceRepository.instance
          .fetchFile(widget.token, claim);
      if (!mounted) return;
      setState(() {
        _claim = claim;
        _file = file;
        _phase = _Phase.open;
      });
    } on ShareException catch (e) {
      if (!mounted) return;
      // The token is already burned at this point - going back to the gate would
      // be a lie. Show the terminal state with the real reason.
      setState(() {
        _phase = _Phase.spent;
        _peek = ViewOncePeek(status: ViewOnceStatus.viewed, message: e.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.spent;
        _peek = ViewOncePeek(
            status: ViewOnceStatus.viewed,
            message: AppLocalizations.of(context).t('viewOnceCouldNotOpen'));
      });
    }
  }

  /// For file types the app can't render itself (PDF, Office). The bytes are
  /// written to a temp file, handed to the system viewer, and deleted the moment
  /// we come back - so nothing is left behind. Screenshot protection does NOT
  /// extend into another app, which is why the recipient is told first.
  Future<void> _openExternally() async {
    final file = _file;
    if (file == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmExternal();
    if (confirmed != true || !mounted) return;

    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/${file.filename}');
      await temp.writeAsBytes(file.bytes, flush: true);
      final result = await OpenFilex.open(temp.path, type: file.mimeType);
      if (result.type != ResultType.done && mounted) {
        _toast(l10n.t('noAppToOpenFile'), error: true);
      }
    } catch (_) {
      if (mounted) _toast(l10n.t('couldNotOpenDoc'), error: true);
    } finally {
      // Best-effort wipe. The system viewer has already read the file by the
      // time we return; leaving a decrypted copy on disk would defeat the point.
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {/* nothing more we can do */}
    }
  }

  Future<bool?> _confirmExternal() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text(l10n.t('openInSystemViewer'),
            style: AppText.title.copyWith(color: palette.textPrimary, fontSize: 17)),
        content: Text(l10n.t('viewOnceExternalWarning'),
            style: AppText.body.copyWith(color: palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel'),
                style: TextStyle(color: palette.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('continueAction'),
                style: const TextStyle(
                    color: AppColors.primaryGreen, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopScope(
      // Leaving after the document is open is irreversible - confirm it.
      canPop: _phase != _Phase.open,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !context.mounted) return;
        final leave = await _confirmLeave();
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: InoBackground(
          child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Brand(),
              Expanded(child: _body(palette)),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmLeave() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text(l10n.t('viewOnceCloseTitle'),
            style: AppText.title.copyWith(color: palette.textPrimary, fontSize: 17)),
        content: Text(l10n.t('viewOnceCloseBody'),
            style: AppText.body.copyWith(color: palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('keepReading'),
                style: TextStyle(color: palette.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('closeAction'),
                style: const TextStyle(
                    color: AppColors.critical, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _body(AppPalette palette) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        );
      case _Phase.gate:
      case _Phase.opening:
        return _gate(palette);
      case _Phase.open:
        return _document(palette);
      case _Phase.spent:
        return _terminal(palette);
    }
  }

  // ---- Phase 1: the gate ---------------------------------------------------

  Widget _gate(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final opening = _phase == _Phase.opening;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.lg),
        // Divine Glass secure-gate hero: a pastel lock chip above the centered
        // title and explainer, floating over the glass card below.
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.tealMist,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.tealPale),
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: AppColors.primaryGreen, size: 38),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.t('viewOnceGateTitle'),
            textAlign: TextAlign.center,
            style: AppText.headline.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.t('viewOnceGateSubtitle'),
            textAlign: TextAlign.center,
            style: AppText.subtitle.copyWith(color: palette.textSecondary)),
        const SizedBox(height: AppSpacing.lg),
        InoCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: AppSizes.iconContainerSm,
                    height: AppSizes.iconContainerSm,
                    decoration: BoxDecoration(
                      color: AppColors.tealMist,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: AppColors.tealPale),
                    ),
                    child: const Icon(Icons.visibility_rounded,
                        color: AppColors.primaryGreen, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_peek.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitle
                                .copyWith(color: palette.textPrimary)),
                        const SizedBox(height: 2),
                        Text('${_peek.type} · ${l10n.t('viewOnceBadge')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption
                                .copyWith(color: palette.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Warning(text: l10n.t('viewOnceGateWarning')),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _Warning(text: _error!, critical: true),
              ],
              const SizedBox(height: AppSpacing.md),
              PressableScale(
                child: GestureDetector(
                  onTap: opening ? null : _open,
                  child: Opacity(
                    opacity: opening ? 0.6 : 1,
                    child: Container(
                      height: AppSizes.button,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      child: Center(
                        child: opening
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.lock_open_rounded,
                                      color: Colors.white, size: 19),
                                  const SizedBox(width: 8),
                                  Text(l10n.t('openOnce'),
                                      style: AppText.subtitle.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800)),
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
        const SizedBox(height: AppSpacing.md),
        _ProtectionNote(palette: palette),
      ],
    );
  }

  // ---- Phase 2: the document ----------------------------------------------

  Widget _document(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final claim = _claim!;
    final file = _file!;

    // Screen recording / mirroring active (iOS) → hide the content outright.
    if (_capturing) {
      return _Notice(
        icon: Icons.screen_share_rounded,
        color: AppColors.critical,
        title: l10n.t('viewOnceCaptureTitle'),
        subtitle: l10n.t('viewOnceCaptureBody'),
      );
    }

    return Column(
      children: [
        if (_screenshotSeen)
          _Banner(
            icon: Icons.photo_camera_rounded,
            color: AppColors.warning,
            text: l10n.t('viewOnceScreenshotNotice'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(claim.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(color: palette.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  l10n.t('viewOnceViewedNow'),
                  style: AppText.caption.copyWith(
                      color: AppColors.darkGreen, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: claim.kind == ViewOnceKind.image
              // Rendered straight from memory - the bytes never touch disk.
              ? InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Image.memory(
                      file.bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _Notice(
                        icon: Icons.broken_image_rounded,
                        color: palette.textFaint,
                        title: l10n.t('couldNotOpenDoc'),
                        subtitle: l10n.t('viewOnceSpentBody'),
                      ),
                    ),
                  ),
                )
              : _unrenderable(palette),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: PressableScale(
            child: Material(
              color: palette.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                side: BorderSide(color: palette.border),
              ),
              child: InkWell(
                onTap: () async {
                  final leave = await _confirmLeave();
                  if (leave == true && mounted) Navigator.of(context).pop();
                },
                child: SizedBox(
                  height: AppSizes.button,
                  child: Center(
                    child: Text(l10n.t('closeAction'),
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// PDFs and office files: INO has no in-app renderer for them, so the choice
  /// is made explicit rather than silently handing the file to another app.
  Widget _unrenderable(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.lightBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _claim!.kind == ViewOnceKind.pdf
                    ? Icons.picture_as_pdf_rounded
                    : Icons.insert_drive_file_rounded,
                size: 40,
                color: AppColors.lightBlue,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.t('viewOnceCantPreview'),
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: palette.textPrimary, fontSize: 17)),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.t('viewOnceCantPreviewBody'),
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            PressableScale(
              child: GestureDetector(
                onTap: _openExternally,
                child: Container(
                  height: AppSizes.button,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_new_rounded,
                          color: Colors.white, size: 19),
                      const SizedBox(width: 8),
                      Text(l10n.t('openInSystemViewer'),
                          style: AppText.subtitle.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Terminal ------------------------------------------------------------

  Widget _terminal(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    switch (_peek.status) {
      case ViewOnceStatus.error:
        return _Notice(
          icon: Icons.wifi_off_rounded,
          color: palette.textFaint,
          title: l10n.t('couldntLoadShare'),
          subtitle: l10n.t('checkConnection'),
          onRetry: _loadPeek,
        );
      case ViewOnceStatus.revoked:
        return _Notice(
          icon: Icons.link_off_rounded,
          color: AppColors.critical,
          title: l10n.t('viewOnceRevokedTitle'),
          subtitle: _peek.message ?? l10n.t('viewOnceRevokedRecipientBody'),
        );
      default:
        // viewed / expired / notFound all mean the same thing to the recipient,
        // and deliberately look identical so a probe can't tell them apart.
        return _Notice(
          icon: Icons.visibility_off_rounded,
          color: AppColors.warning,
          title: l10n.t('viewOnceSpentTitle'),
          subtitle: _peek.message ?? l10n.t('viewOnceSpentBody'),
        );
    }
  }
}

// ---------------------------------------------------------------------------

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.sm),
      child: Row(
        children: [
          const InoBackButton(size: 42),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            alignment: Alignment.center,
            child: const Text('I',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('INO',
                  style: AppText.title.copyWith(
                      color: palette.textPrimary, fontWeight: FontWeight.w900)),
              Text(AppLocalizations.of(context).t('viewOnceBrandSubtitle'),
                  style: AppText.caption.copyWith(color: palette.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text, this.critical = false});

  final String text;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = critical ? AppColors.critical : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              critical
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              color: color,
              size: 19),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(text,
                style: AppText.caption
                    .copyWith(color: palette.textSecondary, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// Tells the recipient exactly what protection is (and is not) in force. The
/// wording differs per platform on purpose - claiming iOS blocks screenshots
/// would be false.
class _ProtectionNote extends StatelessWidget {
  const _ProtectionNote({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocks = ScreenSecurityService.instance.canBlockCapture;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.lightBlue.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_rounded, color: AppColors.lightBlue, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.t(blocks
                  ? 'viewOnceProtectionAndroid'
                  : 'viewOnceProtectionOther'),
              style: AppText.caption
                  .copyWith(color: palette.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style:
                    AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
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
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PressableScale(
                child: Material(
                  color: AppColors.primaryGreen,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  child: InkWell(
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                      child: Text(AppLocalizations.of(context).t('tryAgain'),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
