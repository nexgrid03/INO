import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../dashboard/section_header.dart';
import '../pressable_scale.dart';
import 'qr_scan_frame.dart';

/// QR upload block at the bottom of the Home feed.
///
/// Matches other Home sections: section gap → header → glass card → CTA.
class HomeQrPanel extends StatefulWidget {
  const HomeQrPanel({super.key});

  @override
  State<HomeQrPanel> createState() => _HomeQrPanelState();
}

class _HomeQrPanelState extends State<HomeQrPanel> {
  Uint8List? _qrBytes;
  bool _picking = false;
  ImageProvider? _qrProvider;

  Future<void> _pickQr() async {
    if (_picking) return;
    _picking = true;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _qrBytes = bytes;
        _qrProvider = MemoryImage(bytes);
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Could not open the file picker. Try again or use another browser.'
                : 'Could not open gallery: $e',
          ),
        ),
      );
    } finally {
      _picking = false;
    }
  }

  void _clearQr() {
    setState(() {
      _qrBytes = null;
      _qrProvider = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasQr = _qrBytes != null;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 380;
    final flat = InoStyle.usesFlatBackdrop(context);
    final frameSize = (width * 0.38).clamp(128.0, 156.0);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: 'My QR',
            actionLabel: hasQr ? 'Remove' : null,
            onAction: hasQr ? _clearQr : null,
          ),
          LiquidGlass(
            borderRadius: BorderRadius.circular(AppRadius.card),
            enableBlur: flat,
            blur: flat ? 16 : 20,
            frost: flat ? 1.35 : (palette.isDark ? 1.1 : 0.78),
            shadow: true,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  hasQr
                      ? 'Your UPI QR is ready to share'
                      : 'Save your PhonePe, GPay, or UPI QR here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                PressableScale(
                  pressedScale: 0.98,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: _pickQr,
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: frameSize + 8,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (hasQr && _qrProvider != null)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Image(
                                  image: _qrProvider!,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.medium,
                                ),
                              )
                            else
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 40,
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.85),
                              ),
                            IgnorePointer(
                              child: QrScanFrame(
                                size: frameSize,
                                active: false,
                                accent: AppColors.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _pickQr,
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
                        Icon(
                          hasQr ? Icons.sync_rounded : Icons.upload_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            hasQr
                                ? (narrow ? 'Replace QR' : 'Replace QR image')
                                : (narrow ? 'Upload QR' : 'Upload UPI QR'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
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
            ),
          ),
        ],
      ),
    );
  }
}
