import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/perf/image_decode.dart';
import '../../l10n/app_localizations.dart';
import '../../services/image_enhancer.dart';
import '../../services/scan_pdf_service.dart';
import '../../utils/share_origin.dart';
import 'document_crop_editor.dart';
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
    this.onDiscardScans,
    this.onPagesChanged,
    this.initialFilter = ScanColorMode.original,
  });

  final String pdfPath;
  final List<String> pages;
  final ValueChanged<String> onContinue;
  final VoidCallback? onAddMorePages;
  final VoidCallback? onRetake;
  final VoidCallback? onDiscardScans;
  final ValueChanged<List<String>>? onPagesChanged;
  final ScanColorMode initialFilter;

  @override
  State<ScanPdfPreviewScreen> createState() => _ScanPdfPreviewScreenState();
}

class _ScanPdfPreviewScreenState extends State<ScanPdfPreviewScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  late String _pdfPath;
  late List<String> _sourcePages;
  late List<String> _displayPages;
  late ScanColorMode _activeFilter;
  final Map<String, String> _filterCache = {};
  int _fileSizeBytes = 0;
  bool _continuing = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _pdfPath = widget.pdfPath;
    _sourcePages = List<String>.from(widget.pages);
    _displayPages = List<String>.from(widget.pages);
    _activeFilter = widget.initialFilter;
    _loadFileMeta();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadFileMeta() {
    try {
      final file = File(_pdfPath);
      if (file.existsSync()) {
        setState(() {
          _fileSizeBytes = file.lengthSync();
        });
      }
    } catch (_) {}
  }

  Future<void> _rebuildPdf() async {
    if (_displayPages.isEmpty) return;
    final newPdf = await ScanPdfService.instance.buildPdf(_displayPages);
    if (!mounted) return;
    setState(() {
      _pdfPath = newPdf;
    });
    _loadFileMeta();
    widget.onPagesChanged?.call(List<String>.from(_displayPages));
  }

  Future<void> _cropCurrentPage() async {
    if (_editing || _displayPages.isEmpty) return;
    final idx = _currentIndex.clamp(0, _displayPages.length - 1);
    final original = _sourcePages[idx];
    final edited = await DocumentCropEditor.openOrKeep(context, original);
    if (!mounted || edited == original) return;
    setState(() => _editing = true);
    try {
      _sourcePages[idx] = edited;
      final rendered = _activeFilter == ScanColorMode.original
          ? edited
          : await ImageEnhancer.applyColorMode(edited, _activeFilter);
      if (!mounted) return;
      setState(() => _displayPages[idx] = rendered);
      await _rebuildPdf();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _rotateCurrentPage() async {
    if (_editing || _displayPages.isEmpty) return;
    final idx = _currentIndex.clamp(0, _displayPages.length - 1);
    setState(() => _editing = true);
    try {
      final rotatedSource = await ImageEnhancer.rotate90(_sourcePages[idx]);
      _sourcePages[idx] = rotatedSource;
      final rendered = _activeFilter == ScanColorMode.original
          ? rotatedSource
          : await ImageEnhancer.applyColorMode(rotatedSource, _activeFilter);
      if (!mounted) return;
      setState(() => _displayPages[idx] = rendered);
      await _rebuildPdf();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _selectFilter(ScanColorMode mode) async {
    if (_editing || _activeFilter == mode || _sourcePages.isEmpty) return;
    setState(() {
      _editing = true;
      _activeFilter = mode;
    });
    try {
      final updated = <String>[];
      for (final src in _sourcePages) {
        if (mode == ScanColorMode.original) {
          updated.add(src);
        } else {
          final key = '$src|${mode.name}';
          final cached = _filterCache[key];
          if (cached != null && File(cached).existsSync()) {
            updated.add(cached);
          } else {
            final rendered = await ImageEnhancer.applyColorMode(src, mode);
            _filterCache[key] = rendered;
            updated.add(rendered);
          }
        }
      }
      if (!mounted) return;
      setState(() => _displayPages = updated);
      await _rebuildPdf();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _sharePdf(BuildContext context) async {
    final origin = shareOrigin(context);
    await Share.shareXFiles(
      [XFile(_pdfPath)],
      subject: 'Scanned Document',
      sharePositionOrigin: origin,
    );
  }

  Future<void> _openExternal() async {
    try {
      await OpenFilex.open(_pdfPath);
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
    final fileName = _pdfPath.split(RegExp(r'[\\/]')).last;

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
                          '${_displayPages.length} ${_displayPages.length == 1 ? 'page' : 'pages'} • ${_formatSize(_fileSizeBytes)} • High Quality',
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
              child: _displayPages.isEmpty
                  ? const Center(
                      child: Text(
                        'No pages scanned',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: _displayPages.length,
                      onPageChanged: (i) => setState(() => _currentIndex = i),
                      itemBuilder: (context, index) {
                        final path = _displayPages[index];
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
                                  key: ValueKey(path),
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
            if (_displayPages.length > 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
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
                        '${_currentIndex + 1} / ${_displayPages.length}',
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

            // Crop, Rotate & Filter Controls (Android parity on iOS)
            if (_displayPages.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PreviewToolChip(
                        icon: Icons.crop_rounded,
                        label: 'Crop',
                        enabled: !_editing,
                        onTap: _cropCurrentPage,
                      ),
                      const SizedBox(width: 8),
                      _PreviewToolChip(
                        icon: Icons.rotate_right_rounded,
                        label: 'Rotate',
                        enabled: !_editing,
                        onTap: _rotateCurrentPage,
                      ),
                      if (widget.onDiscardScans != null) ...[
                        const SizedBox(width: 8),
                        _PreviewToolChip(
                          icon: Icons.delete_outline_rounded,
                          label: 'Discard',
                          enabled: !_editing,
                          destructive: true,
                          onTap: widget.onDiscardScans!,
                        ),
                      ],
                      const SizedBox(width: 12),
                      for (final entry in const [
                        (ScanColorMode.original, 'Original'),
                        (ScanColorMode.enhanced, 'Enhance'),
                        (ScanColorMode.blackWhite, 'B&W'),
                        (ScanColorMode.grayscale, 'Grayscale'),
                      ]) ...[
                        _FilterModePill(
                          label: entry.$2,
                          active: _activeFilter == entry.$1,
                          enabled: !_editing,
                          onTap: () => _selectFilter(entry.$1),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
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
                      onPressed: (_continuing || _editing)
                          ? null
                          : () {
                              setState(() => _continuing = true);
                              widget.onContinue(_pdfPath);
                            },
                      icon: _continuing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 22),
                      label: Text(
                        l10n.t('continue'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
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

class _PreviewToolChip extends StatelessWidget {
  const _PreviewToolChip({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? Colors.redAccent : Colors.white;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: destructive
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterModePill extends StatelessWidget {
  const _FilterModePill({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? ScanColors.accent
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active
                  ? ScanColors.accentDeep
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
