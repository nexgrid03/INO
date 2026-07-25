import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../../services/document_scanner_service.dart';
import '../../services/scan_pdf_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../documents/add_document_screen.dart';
import 'ocr_processing_screen.dart';
import 'ocr_result_screen.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';

/// The outcome handed back to whoever launched the scan flow.
class ScanFlowResult {
  const ScanFlowResult({this.imagePath, this.ocr});

  /// Local path of the captured/imported file, so the caller can upload the
  /// actual file (null when the flow produced no file). A multi-page scan
  /// yields a single assembled PDF here; a single page yields the JPEG.
  final String? imagePath;

  /// The confirmed OCR extraction, used to auto-fill Add Document (null when OCR
  /// produced nothing usable and the user chose to enter details manually).
  final OcrResult? ocr;
}

enum _Stage { mlkit, scanner, review, processing, result }

/// Orchestrates the Scan flow: capture → review → OCR → confirm → continue.
///
/// **Capture is WhatsApp-style by default**: on Android the flow opens Google
/// ML Kit's native document scanner ([DocumentScannerService]) — live document
/// boundary detection, edge highlighting, auto-capture, auto-crop, perspective
/// correction and multi-page scanning. The in-app camera ([ScannerScreen]) is
/// the fallback when the native scanner is unavailable (iOS / no Play
/// services / a scanner failure).
///
/// Multi-page scans are reviewed as a carousel (copy modes apply to every
/// page), OCR runs on the FIRST page, and the pages are assembled into a
/// single PDF that Add Document saves to the vault.
class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({super.key});

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  late _Stage _stage;
  String? _capturePath;
  List<String>? _pages;
  OcrResult? _ocr;

  /// True when the current capture came from the ML Kit scanner: its output is
  /// already upright, cropped and perspective-corrected, so OCR can skip its
  /// normalization bake ("assume clean") and Retake relaunches the native
  /// scanner rather than the in-app camera.
  bool _usedMlKit = false;

  bool _building = false; // assembling the multi-page PDF on final continue

  bool get _isMulti => (_pages?.length ?? 0) > 1;

  @override
  void initState() {
    super.initState();
    if (DocumentScannerService.instance.isSupported) {
      _stage = _Stage.mlkit;
      WidgetsBinding.instance.addPostFrameCallback((_) => _launchMlKit());
    } else {
      _stage = _Stage.scanner;
    }
  }

  void _go(_Stage stage) => setState(() => _stage = stage);

  void _exit(ScanFlowResult? result) => Navigator.of(context).pop(result);

  /// Opens the native ML Kit document scanner (auto edge detection, auto-crop,
  /// perspective correction, multi-page). Cancelling exits the flow; a genuine
  /// failure falls back to the in-app camera so scanning always works.
  Future<void> _launchMlKit() async {
    try {
      final pages = await DocumentScannerService.instance.scanPages();
      if (!mounted) return;
      if (pages == null || pages.isEmpty) {
        _exit(null); // user cancelled the scanner
        return;
      }
      setState(() {
        _usedMlKit = true;
        _pages = pages;
        _capturePath = pages.first;
        _stage = _Stage.review;
      });
    } catch (e) {
      developer.log(
          'ML Kit scanner failed, falling back to in-app camera: $e',
          name: 'scan');
      if (mounted) {
        setState(() {
          _usedMlKit = false;
          _stage = _Stage.scanner;
        });
      }
    }
  }

  /// Retake / review-back: return to whichever capture surface produced the
  /// current pages.
  void _recapture() {
    _pages = null;
    _capturePath = null;
    if (_usedMlKit) {
      _go(_Stage.mlkit);
      WidgetsBinding.instance.addPostFrameCallback((_) => _launchMlKit());
    } else {
      _go(_Stage.scanner);
    }
  }

  /// Maps the system back gesture to the previous stage (instead of exiting).
  void _back() {
    switch (_stage) {
      case _Stage.mlkit:
      case _Stage.scanner:
        _exit(null);
      case _Stage.review:
        _recapture();
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

  /// Final continue: multi-page scans are assembled into ONE PDF (falling back
  /// to the first page's JPEG if assembly fails); single pages pass through.
  Future<void> _finish(OcrResult confirmed) async {
    if (_building) return;
    var filePath = _capturePath;
    if (_isMulti) {
      setState(() => _building = true);
      try {
        filePath = await ScanPdfService.instance.buildPdf(_pages!);
      } catch (e) {
        developer.log('PDF assembly failed, saving first page: $e',
            name: 'scan');
        filePath = _pages!.first;
      }
      if (!mounted) return;
      setState(() => _building = false);
    }
    _exit(ScanFlowResult(imagePath: filePath, ocr: confirmed));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.scanner || _stage == _Stage.mlkit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey(_building ? 'building' : _stage),
          child: _building ? const _BuildingPdf() : _buildStage(),
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _Stage.mlkit:
        // The native scanner activity is in the foreground; behind it we show
        // a calm dark backdrop so returning transitions feel seamless.
        return const _NativeScannerBackdrop();
      case _Stage.scanner:
        return ScannerScreen(
          onClose: () => _exit(null),
          onCaptured: (path) {
            _usedMlKit = false;
            _capturePath = path;
            _pages = [path];
            _go(_Stage.review);
          },
        );
      case _Stage.review:
        return ScanReviewScreen(
          imagePath: _capturePath,
          pages: _pages,
          onClose: _recapture,
          onRetake: _recapture,
          onContinue: (editedPath) {
            // Use the edited image (crop / rotate / copy mode) for OCR + save.
            if (editedPath != null) {
              _capturePath = editedPath;
              _pages = [editedPath];
            }
            _go(_Stage.processing);
          },
          onContinueAll: (processedPages) {
            // Copy mode applied to every page; OCR reads the first page.
            _pages = processedPages;
            _capturePath = processedPages.first;
            _go(_Stage.processing);
          },
        );
      case _Stage.processing:
        return OcrProcessingScreen(
          imagePath: _capturePath,
          // ML Kit output is already upright + cropped + rectified → OCR can
          // skip its own orientation/resolution bake (the fast path).
          assumeClean: _usedMlKit,
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
          onRetake: _recapture,
          onContinue: _finish,
        );
    }
  }
}

/// Shown behind the native ML Kit scanner activity and during the brief
/// transition back — a calm dark surface matching the capture chrome.
class _NativeScannerBackdrop extends StatelessWidget {
  const _NativeScannerBackdrop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.dark.bg,
      body: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
        ),
      ),
    );
  }
}

/// Full-screen "assembling your PDF" state for multi-page saves.
class _BuildingPdf extends StatelessWidget {
  const _BuildingPdf();

  @override
  Widget build(BuildContext context) {
    final chrome = AppPalette.dark;
    return Scaffold(
      backgroundColor: chrome.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
            ),
            const SizedBox(height: 16),
            Text(
              'Preparing PDF…',
              style: AppText.subtitle.copyWith(color: chrome.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Launches the Scan flow and, on completion, continues to Add Document with the
/// captured file attached and the form **auto-filled** from the confirmed OCR
/// extraction.
Future<void> launchScanFlow(
  BuildContext context, {
  String? initialWallet,
}) async {
  final result = await Navigator.of(context).push<ScanFlowResult>(
    // Rises from the bottom like a camera opening — a full-screen sheet that
    // slides up on an easeOutCubic curve rather than the default push.
    PageRouteBuilder<ScanFlowResult>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => const ScanFlowScreen(),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
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
