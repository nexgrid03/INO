import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/public_share.dart';
import '../../repositories/share_repository.dart';
import '../../services/share_codec_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import 'shared_documents_screen.dart';

enum _ScanStatus { scanning, resolving, error }

/// Receiving side: scan an INO share QR, validate it, and navigate to the
/// [SharedDocumentsScreen] recipient viewer.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  _ScanStatus _status = _ScanStatus.scanning;
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (raw == null) return;
    final token = ShareCodecService.parseToken(raw);
    if (token == null) return; // ignore non-INO codes and keep scanning

    _handling = true;
    await _scanner.stop();
    if (!mounted) return;
    setState(() => _status = _ScanStatus.resolving);
    
    try {
      final share = await ShareRepository.instance.fetchPublicShare(token);
      if (!mounted) return;
      
      if (share.status == PublicShareStatus.notFound || share.status == PublicShareStatus.error) {
        setState(() {
          _status = _ScanStatus.error;
          _error = 'This share could not be found.';
        });
        return;
      }
      if (share.status == PublicShareStatus.expired) {
        setState(() {
          _status = _ScanStatus.error;
          _error = 'This share has expired.';
        });
        return;
      }
      if (share.status == PublicShareStatus.revoked) {
        setState(() {
          _status = _ScanStatus.error;
          _error = 'This share has been revoked.';
        });
        return;
      }

      // Successfully validated. Let's push the SharedDocumentsScreen.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SharedDocumentsScreen(token: token),
        ),
      );
      
      // When recipient screen is closed, resume scanning.
      if (mounted) {
        await _rescan();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _ScanStatus.error;
          _error = 'Could not open the share. $e';
        });
      }
    }
  }

  Future<void> _rescan() async {
    setState(() {
      _status = _ScanStatus.scanning;
      _error = null;
    });
    _handling = false;
    await _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Scan share QR')),
      body: switch (_status) {
        _ScanStatus.scanning => _buildScanner(),
        _ScanStatus.resolving => Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.primaryGreen,
            ),
          ),
        _ScanStatus.error => _ErrorView(
            message: _error ?? 'Something went wrong.',
            onRetry: _rescan,
          ),
      },
    );
  }

  Widget _buildScanner() {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(controller: _scanner, onDetect: _onDetect),
        // Simple reticle to aim the QR.
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(AppRadius.large),
          ),
        ),
        Positioned(
          bottom: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text('Point at an INO share QR',
                style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 52, color: AppColors.critical),
            const SizedBox(height: AppSpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('Scan again')),
          ],
        ),
      ),
    );
  }
}
