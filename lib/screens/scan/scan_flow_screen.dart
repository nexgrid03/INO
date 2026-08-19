import 'dart:async';
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
import 'scan_wallet_screen.dart';
import 'scanner_screen.dart';

/// The outcome handed back to whoever launched the scan flow.
class ScanFlowResult {
  const ScanFlowResult({this.imagePath, this.ocr, this.wallet});

  /// Local path of the captured/imported file, so the caller can upload the
  /// actual file (null when the flow produced no file). A multi-page scan
  /// yields a single assembled PDF here; a single page yields the JPEG.
  final String? imagePath;

  /// The confirmed OCR extraction, used to auto-fill Add Document (null when OCR
  /// produced nothing usable and the user chose to enter details manually).
  final OcrResult? ocr;

  /// The wallet the user picked in the "Choose Wallet" step (null when the flow
  /// was launched from a wallet that had already answered the question).
  final String? wallet;
}

enum _Stage { mlkit, scanner, review, processing, result, wallet }

/// Orchestrates the Scan flow: capture → review → OCR → confirm → wallet →
/// continue.
///
/// **Capture is WhatsApp-style by default**: on Android the flow opens Google
/// ML Kit's native document scanner ([DocumentScannerService]) - live document
/// boundary detection, edge highlighting, auto-capture, auto-crop, perspective
/// correction and multi-page scanning. The in-app camera ([ScannerScreen]) is
/// the fallback when the native scanner is unavailable (iOS / no Play
/// services / a scanner failure).
///
/// Multi-page scans are reviewed as a carousel (copy modes apply to every
/// page), OCR runs on the FIRST page, and the pages are assembled into a
/// single PDF that Add Document saves to the vault.
///
/// After the details are confirmed the flow asks **which wallet** the document
/// belongs in ([ScanWalletScreen]) - unless [initialWallet] already answers it
/// (a scan started from inside a wallet).
class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({super.key, this.initialWallet});

  /// The wallet this scan is already destined for (set when launched from a
  /// wallet's detail screen). When null the flow shows the wallet-choice step.
  final String? initialWallet;

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
    _stage = _Stage.scanner;
  }

  void _go(_Stage stage) => setState(() => _stage = stage);

  void _exit(ScanFlowResult? result) => Navigator.of(context).pop(result);

  /// Retake / review-back: return to the camera scanner surface.
  void _recapture() {
    _pages = null;
    _capturePath = null;
    _usedMlKit = false;
    _go(_Stage.scanner);
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
        _go(_Stage.review);
      case _Stage.wallet:
        _go(_Stage.review);
      case _Stage.result:
        if (widget.initialWallet != null) {
          _go(_Stage.review);
        } else {
          _go(_Stage.wallet);
        }
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

  /// Details confirmed. In the new flow, wallet has already been chosen (or
  /// pre-selected), so go straight to the finish.
  void _detailsConfirmed(OcrResult confirmed) {
    _ocr = confirmed;
    unawaited(_finish(confirmed, wallet: confirmed.suggestedWallet));
  }

  /// The user picked a wallet: it becomes the document's destination, overriding
  /// whatever OCR suggested. Then we go to the result details screen to fill
  /// the details.
  void _walletChosen(String wallet) {
    final confirmed = (_ocr ?? _manualFallback).copyWith(
      suggestedWallet: wallet,
    );
    setState(() {
      _ocr = confirmed;
    });
    _go(_Stage.result);
  }

  /// Final continue: multi-page scans are assembled into ONE PDF (falling back
  /// to the first page's JPEG if assembly fails); single pages pass through.
  Future<void> _finish(OcrResult confirmed, {String? wallet}) async {
    if (_building) return;
    var filePath = _capturePath;
    if (_isMulti) {
      setState(() => _building = true);
      try {
        filePath = await ScanPdfService.instance.buildPdf(_pages!);
      } catch (e) {
        developer.log(
          'PDF assembly failed, saving first page: $e',
          name: 'scan',
        );
        filePath = _pages!.first;
      }
      if (!mounted) return;
      setState(() => _building = false);
    }
    _exit(ScanFlowResult(imagePath: filePath, ocr: confirmed, wallet: wallet));
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
            if (widget.initialWallet != null) {
              _go(_Stage.result);
            } else {
              _go(_Stage.wallet);
            }
          },
          // OCR couldn't read it → fall back to manual entry (never a dead end).
          onFailed: () {
            _ocr = _manualFallback;
            if (widget.initialWallet != null) {
              _go(_Stage.result);
            } else {
              _go(_Stage.wallet);
            }
          },
        );
      case _Stage.result:
        return OcrResultScreen(
          result: _ocr ?? _manualFallback,
          destinationWallet: widget.initialWallet ?? (_ocr ?? _manualFallback).suggestedWallet,
          onClose: () => widget.initialWallet != null ? _go(_Stage.review) : _go(_Stage.wallet),
          onRetake: _recapture,
          onContinue: _detailsConfirmed,
        );
      case _Stage.wallet:
        return ScanWalletScreen(
          suggestedWallet: (_ocr ?? _manualFallback).suggestedWallet,
          onBack: () => _go(_Stage.review),
          onSelected: _walletChosen,
        );
    }
  }
}

/// Shown behind the native ML Kit scanner activity and during the brief
/// transition back - a calm dark surface matching the capture chrome.
class _NativeScannerBackdrop extends StatelessWidget {
  const _NativeScannerBackdrop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.dark.bg,
      body:  Center(
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
             CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
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
    // Rises from the bottom like a camera opening - a full-screen sheet that
    // slides up on an easeOutCubic curve rather than the default push.
    PageRouteBuilder<ScanFlowResult>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => ScanFlowScreen(initialWallet: initialWallet),
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
        // The wallet the user chose in the flow wins; otherwise the wallet the
        // scan was launched from.
        initialWallet: result.wallet ?? initialWallet,
        initialFilePath: result.imagePath,
        prefill: result.ocr,
      ),
    ),
  );
}
