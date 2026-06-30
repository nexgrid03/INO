import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scan/scan_fail_state.dart';
import '../documents/add_document_screen.dart';
import 'ocr_processing_screen.dart';
import 'ocr_result_screen.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';

/// The outcome handed back to whoever launched the scan flow.
class ScanFlowResult {
  const ScanFlowResult.completed(this.ocr) : manual = false;
  const ScanFlowResult.manual()
      : ocr = null,
        manual = true;

  /// The confirmed OCR data (null when the user chose manual entry).
  final OcrResult? ocr;

  /// True when the user opted to skip OCR and enter details by hand.
  final bool manual;
}

enum _Stage { scanner, review, processing, result, failed }

/// Orchestrates the Scan & OCR flow as a single focused task:
/// scan → review → process → confirm. Each stage is its own screen; this widget
/// owns the transitions and the captured state, then pops with a
/// [ScanFlowResult] so the caller can continue to Save.
///
/// Prefer [launchScanFlow] over pushing this directly — it wires the handoff to
/// Add Document.
class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({super.key});

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  _Stage _stage = _Stage.scanner;
  OcrResult? _result;
  String? _capturePath;

  void _go(_Stage stage) => setState(() => _stage = stage);

  void _exit(ScanFlowResult? result) => Navigator.of(context).pop(result);

  /// Maps the system back gesture to the previous stage (instead of exiting).
  void _back() {
    switch (_stage) {
      case _Stage.scanner:
        _exit(null);
      case _Stage.review:
      case _Stage.result:
        _go(_Stage.scanner);
      case _Stage.processing:
        _go(_Stage.review);
      case _Stage.failed:
        _go(_Stage.scanner);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.scanner,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey(_stage),
          child: _buildStage(),
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _Stage.scanner:
        return ScannerScreen(
          onClose: () => _exit(null),
          onCaptured: (path) {
            _capturePath = path;
            _go(_Stage.review);
          },
        );
      case _Stage.review:
        return ScanReviewScreen(
          imagePath: _capturePath,
          onClose: () => _go(_Stage.scanner),
          onRetake: () => _go(_Stage.scanner),
          onContinue: () => _go(_Stage.processing),
        );
      case _Stage.processing:
        return OcrProcessingScreen(
          imagePath: _capturePath,
          onResult: (r) {
            _result = r;
            _go(_Stage.result);
          },
          onFailed: () => _go(_Stage.failed),
        );
      case _Stage.result:
        return OcrResultScreen(
          result: _result!,
          onClose: () => _go(_Stage.review),
          onRetake: () => _go(_Stage.scanner),
          onContinue: (updated) =>
              _exit(ScanFlowResult.completed(updated)),
        );
      case _Stage.failed:
        return _FailedStage(
          onBack: () => _go(_Stage.scanner),
          onTryAgain: () => _go(_Stage.processing),
          onManualEntry: () => _exit(const ScanFlowResult.manual()),
        );
    }
  }
}

class _FailedStage extends StatelessWidget {
  const _FailedStage({
    required this.onBack,
    required this.onTryAgain,
    required this.onManualEntry,
  });

  final VoidCallback onBack;
  final VoidCallback onTryAgain;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        elevation: 0,
        leading: IconButton(
          onPressed: onBack,
          icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
        ),
      ),
      body: ScanFailState(
        message:
            'INO couldn’t read this document clearly. Try scanning again in better light, or enter the details manually.',
        onTryAgain: onTryAgain,
        onManualEntry: onManualEntry,
      ),
    );
  }
}

/// Launches the Scan & OCR flow and, on completion, continues to Add Document
/// (Save) — prefilled from OCR, or empty for manual entry. The single entry
/// point used by the shell, Home and Wallet Detail.
Future<void> launchScanFlow(
  BuildContext context, {
  String? initialWallet,
}) async {
  final result = await Navigator.of(context).push<ScanFlowResult>(
    MaterialPageRoute(builder: (_) => const ScanFlowScreen()),
  );
  if (result == null || !context.mounted) return;

  if (result.manual) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddDocumentScreen(initialWallet: initialWallet),
      ),
    );
  } else if (result.ocr != null) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddDocumentScreen(
          prefill: result.ocr,
          initialWallet: initialWallet,
        ),
      ),
    );
  }
}
