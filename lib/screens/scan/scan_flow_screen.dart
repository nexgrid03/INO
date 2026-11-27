import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../../services/scan_pdf_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../documents/add_document_screen.dart';
import 'ocr_processing_screen.dart';
import 'ocr_result_screen.dart';
import 'scan_review_screen.dart';
import 'scan_wallet_screen.dart';
import 'scanner_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// The outcome handed back to whoever launched the scan flow.
class ScanFlowResult {
  const ScanFlowResult({this.imagePath, this.pages, this.ocr, this.wallet});

  /// Local path of the captured/imported file, so the caller can upload the
  /// actual file (null when the flow produced no file). A multi-page scan
  /// yields a single assembled PDF here; a single page yields the JPEG.
  final String? imagePath;

  /// The raw page image paths for multi-page captures.
  final List<String>? pages;

  /// The confirmed OCR extraction, used to auto-fill Add Document (null when OCR
  /// produced nothing usable and the user chose to enter details manually).
  final OcrResult? ocr;

  /// The wallet the user picked in the "Choose Wallet" step (null when the flow
  /// was launched from a wallet that had already answered the question).
  final String? wallet;
}

// NOTE: _Stage.crop is handled as a pushed route, not a top-level stage,
// so it does not appear in this enum.
enum _Stage { scanner, review, processing, result, wallet }

/// Orchestrates the Scan flow: capture → crop (manual) → review → OCR →
/// confirm → wallet → continue.
///
/// **Capture is always manual**: the in-app camera ([ScannerScreen]) opens
/// so the user frames and captures the document with a deliberate shutter
/// press. The [DocumentCropEditor] then opens immediately so the user can
/// drag the four corner handles to apply a perspective-correct crop.
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

  bool _building = false; // assembling the multi-page PDF on final continue

  bool get _isMulti => (_pages?.length ?? 0) > 1;

  @override
  void initState() {
    super.initState();
    // Always start with the in-app manual camera — no auto-detection / ML Kit.
    _stage = _Stage.scanner;
  }

  void _go(_Stage stage) => setState(() => _stage = stage);

  void _exit(ScanFlowResult? result) => Navigator.of(context).pop(result);

  /// Retake / review-back: return to the in-app camera.
  void _recapture() {
    _pages = null;
    _capturePath = null;
    _go(_Stage.scanner);
  }

  /// Maps the system back gesture to the previous stage (instead of exiting).
  void _back() {
    switch (_stage) {
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
    _exit(ScanFlowResult(imagePath: filePath, pages: _pages, ocr: confirmed, wallet: wallet));
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
          key: ValueKey(_building ? 'building' : _stage),
          child: _building ? const _BuildingPdf() : _buildStage(),
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
            setState(() {
              _capturePath = path;
              _pages = [path];
              _stage = _Stage.processing;
            });
          },
          onCompleted: (pdfPath, pages) {
            setState(() {
              _capturePath = pdfPath;
              _pages = pages;
              _stage = _Stage.processing;
            });
          },
        );
      case _Stage.review:
        return ScanReviewScreen(
          imagePath: _capturePath,
          pages: _pages,
          onClose: _recapture,
          onRetake: _recapture,
          onAddPage: () async {
            if (!mounted) return;
            String? newPage;
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => ScannerScreen(
                  onClose: () => Navigator.of(ctx).pop(),
                  onCaptured: (captured) {
                    newPage = captured;
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  onCompleted: (pdf, pages) {
                    newPage = pages.isNotEmpty ? pages.last : pdf;
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ),
            );
            if (newPage != null && mounted) {
              setState(() {
                _pages = [...?_pages, newPage!];
                _capturePath = newPage;
              });
            }
          },
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
          assumeClean: true, // manual crop; already cropped & rectified by editor
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
            InoLoader(color: AppColors.primaryGreen),
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
        initialPages: result.pages,
        prefill: result.ocr,
      ),
    ),
  );
}
