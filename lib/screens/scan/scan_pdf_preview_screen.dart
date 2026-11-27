import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/perf/image_decode.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/share_origin.dart';
import 'scan_theme.dart';

/// Screen showing the assembled high-quality PDF preview after multi-page scan.
///
/// Features:
/// - Swipeable page carousel with zoom capability
/// - Document metadata (page count, file size, name)
/// - "Open PDF" via native viewer
/// - Share action
/// - "Add / Retake Pages" to return to camera session
/// - "Done / Continue" to commit the PDF to the document workflow
class ScanPdfPreviewScreen extends StatefulWidget {
  const ScanPdfPreviewScreen({
    super.key,
    required this.pdfPath,
    required this.pages,
    required this.onContinue,
    this.onAddMorePages,
    this.onRetake,
  });

  final String pdfPath;
  final List<String> pages;
  final ValueChanged<String> onContinue;
  final VoidCallback? onAddMorePages;
  final VoidCallback? onRetake;

  @override
  State<ScanPdfPreviewScreen> createState() => _ScanPdfPreviewScreenState();
}

class _ScanPdfPreviewScreenState extends State<ScanPdfPreviewScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  int _fileSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadFileMeta();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadFileMeta() {
    try {
      final file = File(widget.pdfPath);
      if (file.existsSync()) {
        setState(() {
          _fileSizeBytes = file.lengthSync();
        });
      }
    } catch (_) {}
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _sharePdf(BuildContext context) async {
    final origin = shareOrigin(context);
    await Share.shareXFiles(
      [XFile(widget.pdfPath)],
      subject: 'Scanned Document',
      sharePositionOrigin: origin,
    );
  }

  Future<void> _openExternal() async {
    try {
      await OpenFilex.open(widget.pdfPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open PDF viewer: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fileName = widget.pdfPath.split(RegExp(r'[\\/]')).last;

    return Scaffold(
      backgroundColor: const Color(0xFF121820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Document Preview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            tooltip: l10n.t('share'),
            onPressed: () => _sharePdf(context),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            tooltip: 'Open in system viewer',
            onPressed: _openExternal,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Metadata banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ScanColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: ScanColors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.pages.length} ${widget.pages.length == 1 ? 'page' : 'pages'} • ${_formatSize(_fileSizeBytes)} • High Quality',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.visibility_rounded, size: 16, color: ScanColors.accentDeep),
                    label: const Text(
                      'Open',
                      style: TextStyle(color: ScanColors.accentDeep, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            // Page Carousel
            Expanded(
              child: widget.pages.isEmpty
                  ? const Center(
                      child: Text(
                        'No pages scanned',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: widget.pages.length,
                      onPageChanged: (i) => setState(() => _currentIndex = i),
                      itemBuilder: (context, index) {
                        final path = widget.pages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Center(
                            child: InteractiveViewer(
                              minScale: 1.0,
                              maxScale: 3.5,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image(
                                  image: zoomableFileImage(context, File(path)),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Page Indicator
            if (widget.pages.length > 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.pages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Bottom Actions Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1B232D),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  if (widget.onAddMorePages != null)
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onAddMorePages?.call();
                        },
                        icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                        label: const Text(
                          'Add Page',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ),
                  if (widget.onAddMorePages != null) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ScanColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        widget.onContinue(widget.pdfPath);
                      },
                      icon: const Icon(Icons.check_rounded, size: 22),
                      label: Text(
                        l10n.t('continue'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
