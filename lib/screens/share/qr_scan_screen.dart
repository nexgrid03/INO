import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/document_share.dart';
import '../../repositories/share_repository.dart';
import '../../services/share_codec_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

enum _ScanStatus { scanning, resolving, result, error }

/// Receiving side: scan an INO share QR, resolve the token, and list the shared
/// documents with a copyable download link for each.
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
  DocumentShare? _share;

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
    setState(() => _status = _ScanStatus.resolving);
    try {
      final share = await ShareRepository.instance.fetchByToken(token);
      if (!mounted) return;
      if (share == null || share.isExpired) {
        setState(() {
          _status = _ScanStatus.error;
          _error = share == null
              ? 'This share could not be found.'
              : 'This share has expired.';
        });
        return;
      }
      setState(() {
        _share = share;
        _status = _ScanStatus.result;
      });
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
      _share = null;
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
        _ScanStatus.resolving => const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2.6, color: AppColors.primaryGreen),
          ),
        _ScanStatus.result => _ResultView(share: _share!, onRescan: _rescan),
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

class _ResultView extends StatelessWidget {
  const _ResultView({required this.share, required this.onRescan});
  final DocumentShare share;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded,
                  color: AppColors.primaryGreen),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(share.title,
                        style: AppText.title
                            .copyWith(color: palette.textPrimary)),
                    Text(
                      '${share.fileCount} document'
                      '${share.fileCount == 1 ? '' : 's'} available',
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: share.files.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) {
              final file = share.files[i];
              final url = ShareRepository.instance.publicUrl(file.path);
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_rounded,
                        color: AppColors.lightBlue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body
                              .copyWith(color: palette.textPrimary)),
                    ),
                    IconButton(
                      tooltip: 'Copy download link',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Link for ${file.name} copied.'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.primaryGreen,
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: OutlinedButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Scan another'),
            ),
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
