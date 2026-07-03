import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../documents/add_document_screen.dart';
import 'ocr_processing_screen.dart';
import 'ocr_result_screen.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';

/// The outcome handed back to whoever launched the scan flow.
class ScanFlowResult {
  const ScanFlowResult({this.imagePath, this.ocr});

  /// Local path of the captured/imported image, so the caller can upload the
  /// actual file (null when the flow produced no image).
  final String? imagePath;

  /// The confirmed OCR extraction, used to auto-fill Add Document (null when OCR
  /// produced nothing usable and the user chose to enter details manually).
  final OcrResult? ocr;
}

enum _Stage { scanner, review, processing, result }

/// Orchestrates the Scan flow: capture → review image → OCR → confirm → continue.
///
/// Real on-device OCR (ML Kit) runs on the captured image, detects the document
/// type, extracts its fields, and hands a confirmed [OcrResult] to Add Document
/// so the form auto-fills. If OCR can't read the document, the flow falls back
/// to manual entry rather than failing.
class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({super.key});

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  _Stage _stage = _Stage.scanner;
  String? _capturePath;
  OcrResult? _ocr;

  void _go(_Stage stage) => setState(() => _stage = stage);

  void _exit(ScanFlowResult? result) => Navigator.of(context).pop(result);

  /// Maps the system back gesture to the previous stage (instead of exiting).
  void _back() {
    switch (_stage) {
      case _Stage.scanner:
        _exit(null);
      case _Stage.review:
        _go(_Stage.scanner);
      case _Stage.processing:
      case _Stage.result:
        _go(_Stage.review);
    }
  }

  /// A minimal, low-confidence result so the user can still file the document
  /// manually when OCR fails or the document is unsupported.
  OcrResult get _manualFallback => const OcrResult(
        documentName: '',
        detectedType: 'Document',
        suggestedWallet: 'Document Wallet',
        category: 'Other',
        confidence: DetectionConfidence.low,
      );

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
          onContinue: (editedPath) {
            // Use the edited image (crop / rotate / enhance) for OCR and save.
            if (editedPath != null) _capturePath = editedPath;
            _go(_Stage.processing);
          },
        );
      case _Stage.processing:
        return OcrProcessingScreen(
          imagePath: _capturePath,
          onResult: (result) {
            _ocr = result;
            _go(_Stage.result);
          },
          // OCR couldn't read it → fall back to manual entry (never a dead end).
          onFailed: () {
            _ocr = _manualFallback;
            _go(_Stage.result);
          },
        );
      case _Stage.result:
        return OcrResultScreen(
          result: _ocr ?? _manualFallback,
          onClose: () => _go(_Stage.review),
          onRetake: () => _go(_Stage.scanner),
          onContinue: (confirmed) => _exit(
            ScanFlowResult(imagePath: _capturePath, ocr: confirmed),
          ),
        );
    }
  }
}

/// Launches the Scan flow and, on completion, continues to Add Document with the
/// captured image attached and the form **auto-filled** from the confirmed OCR
/// extraction.
Future<void> launchScanFlow(
  BuildContext context, {
  String? initialWallet,
}) async {
  final result = await Navigator.of(context).push<ScanFlowResult>(
    MaterialPageRoute(builder: (_) => const ScanFlowScreen()),
  );
  if (result == null || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AddDocumentScreen(
        initialWallet: initialWallet,
        initialFilePath: result.imagePath,
        prefill: result.ocr,
      ),
    ),
  );
}
