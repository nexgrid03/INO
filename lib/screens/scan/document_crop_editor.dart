import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/document_crop_service.dart';
import '../../theme/app_theme.dart';

/// A document crop editor with four draggable corner handles and live
/// perspective preview — the Adobe Scan / Microsoft Lens interaction.
///
/// The user drags the corners to the document's edges; on Apply we run a real
/// perspective correction ([DocumentCropService.rectify]) that maps the
/// quadrilateral onto a straight rectangle. Returns the cropped file path via
/// `Navigator.pop`, or null if cancelled.
class DocumentCropEditor extends StatefulWidget {
  const DocumentCropEditor({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<DocumentCropEditor> createState() => _DocumentCropEditorState();
}

class _DocumentCropEditorState extends State<DocumentCropEditor> {
  /// Corners normalized to 0..1 in image space, ordered TL, TR, BR, BL.
  List<Offset> _corners = _defaultCorners();
  Size? _imageSize;
  bool _busy = false;

  static List<Offset> _defaultCorners() => const [
        Offset(0.06, 0.06),
        Offset(0.94, 0.06),
        Offset(0.94, 0.94),
        Offset(0.06, 0.94),
      ];

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _imageSize = Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          ));
    } catch (_) {
      if (mounted) setState(() => _imageSize = const Size(1, 1.4));
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() => _corners = _defaultCorners());
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final cropped =
        await DocumentCropService.rectify(widget.imagePath, _corners);
    if (!mounted) return;
    if (cropped == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.critical,
          content: Text(AppLocalizations.of(context).t('cropFailed')),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(cropped);
  }

  /// The rect the image occupies inside [available] when fitted with `contain`.
  Rect _fittedRect(Size available) {
    final img = _imageSize!;
    final ar = img.width / img.height;
    var w = available.width;
    var h = w / ar;
    if (h > available.height) {
      h = available.height;
      w = h * ar;
    }
    final dx = (available.width - w) / 2;
    final dy = (available.height - h) / 2;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.t('crop'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: l10n.t('reset'),
            icon: const Icon(Icons.crop_free_rounded),
            onPressed: _busy ? null : _reset,
          ),
        ],
      ),
      body: _imageSize == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : LayoutBuilder(
              builder: (context, constraints) {
                final available =
                    Size(constraints.maxWidth, constraints.maxHeight);
                final rect = _fittedRect(available);

                Offset toDisplay(Offset norm) => Offset(
                      rect.left + norm.dx * rect.width,
                      rect.top + norm.dy * rect.height,
                    );

                void dragCorner(int i, Offset delta) {
                  final current = _corners[i];
                  final nx =
                      (current.dx + delta.dx / rect.width).clamp(0.0, 1.0);
                  final ny =
                      (current.dy + delta.dy / rect.height).clamp(0.0, 1.0);
                  setState(() {
                    _corners = [..._corners]..[i] = Offset(nx, ny);
                  });
                }

                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: Image.file(File(widget.imagePath),
                          fit: BoxFit.fill),
                    ),
                    // Dim mask + quadrilateral + grid.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CropOverlayPainter(
                          corners: [for (final c in _corners) toDisplay(c)],
                        ),
                      ),
                    ),
                    // Draggable corner handles.
                    for (var i = 0; i < 4; i++)
                      _Handle(
                        center: toDisplay(_corners[i]),
                        onDrag: (delta) => dragCorner(i, delta),
                      ),
                    if (_busy)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primaryGreen),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
      bottomNavigationBar: _imageSize == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(l10n.t('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l10n.t('applyCrop'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A single draggable corner handle (a ring with a solid centre and a generous
/// invisible touch target).
class _Handle extends StatelessWidget {
  const _Handle({required this.center, required this.onDrag});

  final Offset center;
  final ValueChanged<Offset> onDrag;

  static const double _touch = 44;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - _touch / 2,
      top: center.dy - _touch / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onDrag(d.delta),
        child: SizedBox(
          width: _touch,
          height: _touch,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the dark mask outside the selection, the quadrilateral outline and a
/// rule-of-thirds grid.
class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.corners});

  /// Display-space corners, ordered TL, TR, BR, BL.
  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    // Dim everything outside the quad.
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      quad,
    );
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.55));

    // Quad outline.
    canvas.drawPath(
      quad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.primaryGreen,
    );

    // Rule-of-thirds guides (interpolated across the quad edges).
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.5);
    Offset lerp(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;
    for (final t in const [1 / 3, 2 / 3]) {
      // vertical-ish lines: between top edge and bottom edge
      canvas.drawLine(
        lerp(corners[0], corners[1], t),
        lerp(corners[3], corners[2], t),
        guide,
      );
      // horizontal-ish lines: between left edge and right edge
      canvas.drawLine(
        lerp(corners[0], corners[3], t),
        lerp(corners[1], corners[2], t),
        guide,
      );
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) => old.corners != corners;
}
