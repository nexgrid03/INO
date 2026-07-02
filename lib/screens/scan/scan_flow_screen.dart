import 'package:flutter/material.dart';

import '../documents/add_document_screen.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';

/// The outcome handed back to whoever launched the scan flow.
class ScanFlowResult {
  const ScanFlowResult({this.imagePath});

  /// Local path of the captured/imported image, so the caller can upload the
  /// actual file (null when the flow produced no image).
  final String? imagePath;
}

enum _Stage { scanner, review }

/// Orchestrates the Scan flow: capture → review → continue.
///
/// Auto-extraction (OCR) was removed — it only ever returned fake sample data,
/// and the user now fills in every detail themselves on Add Document. This flow
/// simply captures a clean image and hands its path off to Add Document.
class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({super.key});

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  _Stage _stage = _Stage.scanner;
  String? _capturePath;

  void _go(_Stage stage) => setState(() => _stage = stage);

  void _exit(ScanFlowResult? result) => Navigator.of(context).pop(result);

  /// Maps the system back gesture to the previous stage (instead of exiting).
  void _back() {
    switch (_stage) {
      case _Stage.scanner:
        _exit(null);
      case _Stage.review:
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
          onContinue: () =>
              _exit(ScanFlowResult(imagePath: _capturePath)),
        );
    }
  }
}

/// Launches the Scan flow and, on completion, continues to Add Document with the
/// captured image attached and a blank form for the user to fill in.
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
      ),
    ),
  );
}
