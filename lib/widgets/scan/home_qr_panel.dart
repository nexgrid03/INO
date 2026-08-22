import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../repositories/qr_code_repository.dart';
import '../../screens/scan/qr_scanner_screen.dart';
import '../../services/qr_crop_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../common/scroll_zoom_in.dart';
import '../dashboard/section_header.dart';
import '../pressable_scale.dart';
import 'qr_scan_frame.dart';

/// "My QR" block at the bottom of the Home feed.
///
/// Holds the user's own payment QR and the entry point to the scanner:
///
///  * **Uploading** runs the picked photo through [QrCropService], which finds
///    the QR with ML Kit and crops the image down to it - so a screenshot of a
///    whole payment app becomes just the code. The crop (not the original) is
///    what gets stored and shown.
///  * **Storage** is `public.user_qr_codes`, one row per user, via
///    [QrCodeRepository]. The card renders from local state either way, so an
///    offline or signed-out user still sees their upload.
///  * **The saved QR zooms** as it scrolls into view ([ScrollZoomIn]).
///  * **Scanning** sits directly below, where a payment QR opens the
///    payment-app picker.
class HomeQrPanel extends StatefulWidget {
  const HomeQrPanel({super.key});

  @override
  State<HomeQrPanel> createState() => _HomeQrPanelState();
}

class _HomeQrPanelState extends State<HomeQrPanel> {
  /// The cropped QR currently on show. Local state is the source of truth for
  /// rendering so the card never blanks out on a failed round trip.
  Uint8List? _qrBytes;
  ImageProvider? _qrProvider;
  String? _subtitle;

  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Home's sliver list disposes off-screen children, so scrolling to the top
    // and back re-creates this widget. If the QR was already fetched this
    // session, adopt it synchronously - showing a loader again where a code was
    // already on screen is the flicker this avoids.
    final repo = QrCodeRepository.instance;
    if (repo.isLoaded) {
      _loading = false;
      _adopt(repo.cached);
    } else {
      _load();
    }
  }

  /// Applies [saved] to local state. Reuses the cached [Uint8List] instance so
  /// the [MemoryImage] hits Flutter's image cache and the picture appears on
  /// the first frame rather than decoding again.
  void _adopt(UserQr? saved) {
    if (saved == null) {
      _qrBytes = null;
      _qrProvider = null;
      _subtitle = null;
      return;
    }
    _qrBytes = saved.bytes;
    _qrProvider = MemoryImage(saved.bytes);
    _subtitle = saved.subtitle;
  }

  Future<void> _load() async {
    final saved = await QrCodeRepository.instance.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _adopt(saved);
    });
  }

  Future<void> _pickQr() async {
    if (_busy) return;
    // Resolved up front — every toast below sits after an async gap.
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Generous limits on purpose: the QR has to survive detection before it
        // is cropped, and an over-compressed source is the main reason a
        // perfectly good code fails to decode.
        imageQuality: 95,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final cropped = await QrCropService.instance.cropFromFile(file.path);
      if (!mounted) return;
      if (cropped == null) {
        setState(() => _busy = false);
        _toast(l10n.t('qrImageUnreadable'));
        return;
      }

      setState(() {
        _qrBytes = cropped.bytes;
        _qrProvider = MemoryImage(cropped.bytes);
        _busy = false;
      });
      HapticFeedback.mediumImpact();

      if (!cropped.isCropped) {
        // Saved, but say so plainly rather than implying we found a code.
        _toast(l10n.t('qrSavedNoCodeDetected'));
      }

      final saved = await QrCodeRepository.instance.save(
        bytes: cropped.bytes,
        payload: cropped.payload,
        width: cropped.width,
        height: cropped.height,
      );
      if (!mounted) return;
      if (saved == null) {
        _toast(l10n.t('qrSavedLocallyOnly'));
      } else {
        setState(() => _subtitle = saved.subtitle);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(kIsWeb
          ? l10n.t('couldNotOpenFilePicker')
          : l10n.t('galleryOpenFailed'));
    }
  }

  Future<void> _clearQr() async {
    setState(() {
      _qrBytes = null;
      _qrProvider = null;
      _subtitle = null;
    });
    await QrCodeRepository.instance.remove();
  }

  /// Opens the live QR scanner. A scanned payment (UPI / BharatQR) code offers
  /// the payment apps installed on this device.
  void _scanQr() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _openQrPreview() {
    final provider = _qrProvider;
    if (provider == null) return;
    HapticFeedback.selectionClick();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image(
                      image: provider,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.close_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final hasQr = _qrBytes != null;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 380;
    final flat = InoStyle.usesFlatBackdrop(context);

    // The saved QR gets real estate - it is the point of the card. The empty
    // state stays compact so it doesn't leave a hole above the nav bar.
    final qrSize = hasQr
        ? (width * 0.52).clamp(170.0, 230.0)
        : (width * 0.28).clamp(96.0, 120.0);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: l10n.t('myQr'),
            actionLabel: hasQr ? l10n.t('remove') : null,
            onAction: hasQr ? _clearQr : null,
          ),
          LiquidGlass(
            borderRadius: BorderRadius.circular(AppRadius.card),
            enableBlur: flat,
            blur: flat ? 16 : 20,
            frost: flat ? 1.35 : (palette.isDark ? 1.1 : 0.78),
            shadow: true,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasQr) ...[
                  Text(
                    l10n.t('saveYourUpiQrHere'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _qrArea(qrSize, hasQr),
                if (hasQr) ...[
                  // Rises a beat behind the code itself - a gentler ramp on the
                  // same scroll gives a staggered settle rather than everything
                  // moving as one block.
                  ScrollZoomIn(
                    minScale: 0.94,
                    lift: 10,
                    travelFraction: 0.30,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_subtitle != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _subtitle!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        // The big upload button is gone once a QR exists -
                        // replacing is a rare action, so it gets a quiet inline
                        // control instead of competing with Scan for attention.
                        _ReplaceLink(busy: _busy, onTap: _pickQr),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _pickQr,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_rounded, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              narrow
                                  ? l10n.t('uploadQr')
                                  : l10n.t('uploadUpiQr'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _scanQr,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                side: BorderSide(
                    color: AppColors.primaryGreen.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.t('scanAQr'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('scanPaymentQrHint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary.withValues(alpha: 0.75),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// The QR itself (or the empty-state frame). Sized by [size] in BOTH states so
  /// the zoom below only ever scales what is painted - the layout box never
  /// changes while scrolling.
  Widget _qrArea(double size, bool hasQr) {
    if (_loading) {
      return SizedBox(
        height: size,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (!hasQr) {
      return PressableScale(
        pressedScale: 0.98,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _busy ? null : _pickQr,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_busy)
                    const CircularProgressIndicator(strokeWidth: 2.4)
                  else
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 36,
                      color: AppColors.primaryGreen.withValues(alpha: 0.85),
                    ),
                  IgnorePointer(
                    child: QrScanFrame(
                      size: size,
                      active: false,
                      accent: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: size,
      child: Center(
        child: ScrollZoomIn(
          // The shadow deepens as it settles, so the code reads as lifting off
          // the card rather than just inflating in place.
          glowColor: AppColors.primaryGreen,
          borderRadius: 18,
          child: PressableScale(
            pressedScale: 0.98,
            child: GestureDetector(
              // Tap opens the code full-screen and pinch-zoomable. The card
              // shows it at a browsing size; this is the size that matters when
              // someone is actually scanning it off your phone.
              onTap: _busy ? null : _openQrPreview,
              child: Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // A QR needs a light quiet zone to scan reliably off a screen
                  // - never paint it straight onto a dark surface.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.tealPale),
                ),
                child: _busy
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Image(
                        image: _qrProvider!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet "swap this QR" control shown once one is saved.
class _ReplaceLink extends StatelessWidget {
  const _ReplaceLink({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded,
                    size: 17, color: palette.textSecondary),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).t('replaceQr'),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
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
