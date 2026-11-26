import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../core/perf/image_decode.dart';
import '../../services/document_crop_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_loader.dart';

/// A document crop editor with four draggable corner handles, four draggable
/// edge border lines, and live perspective preview.
///
/// The user can drag any of the 4 corner handles or any of the 4 border lines
/// to align with the document's edges; on Apply we run perspective correction
/// ([DocumentCropService.rectify]) that maps the quadrilateral onto a straight
/// rectangle. Returns the cropped file path via `Navigator.pop`, or null if cancelled.
class DocumentCropEditor extends StatefulWidget {
  const DocumentCropEditor({super.key, required this.imagePath});

  final String imagePath;

  /// Opens [DocumentCropEditor] for [imagePath] and returns the cropped path,
  /// or falls back to [imagePath] if the user cancels cropping.
  static Future<String> openOrKeep(
    BuildContext context,
    String imagePath,
  ) async {
    final cropped = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DocumentCropEditor(imagePath: imagePath),
      ),
    );
    return cropped ?? imagePath;
  }

  /// True when [path] is a raster image format supported by the crop editor.
  static bool isCropSupportedImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  @override
  State<DocumentCropEditor> createState() => _DocumentCropEditorState();
}

class _DocumentCropEditorState extends State<DocumentCropEditor> {
  /// Corners normalized to 0..1 in image space, ordered TL, TR, BR, BL.
  List<Offset> _corners = _defaultCorners();
  Size? _imageSize;
  bool _busy = false;

  static List<Offset> _defaultCorners() => const [
        Offset(0.0, 0.0), // 0: Top-Left (TL)
        Offset(1.0, 0.0), // 1: Top-Right (TR)
        Offset(1.0, 1.0), // 2: Bottom-Right (BR)
        Offset(0.0, 1.0), // 3: Bottom-Left (BL)
      ];

  static bool _isFullImage(List<Offset> c) =>
      c.length == 4 &&
      c[0] == const Offset(0.0, 0.0) &&
      c[1] == const Offset(1.0, 0.0) &&
      c[2] == const Offset(1.0, 1.0) &&
      c[3] == const Offset(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  /// Reads the capture's pixel dimensions without materializing the whole bitmap.
  Future<void> _loadSize() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(widget.imagePath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      if (!mounted) return;
      setState(() => _imageSize = size);
    } catch (_) {
      if (mounted) setState(() => _imageSize = const Size(1, 1.4));
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() => _corners = _defaultCorners());
  }

  Future<void> _apply() async {
    if (_busy) return;
    if (_isFullImage(_corners)) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(widget.imagePath);
      return;
    }
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

  /// The rect the image occupies inside [available] when fitted with `contain`,
  /// inset slightly so corner handles at (0,0)..(1,1) remain easy to grab.
  Rect _fittedRect(Size available) {
    const edgePad = 16.0;
    final maxW = math.max(1.0, available.width - edgePad * 2);
    final maxH = math.max(1.0, available.height - edgePad * 2);
    final img = _imageSize!;
    final ar = img.width / img.height;
    var w = maxW;
    var h = w / ar;
    if (h > maxH) {
      h = maxH;
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
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.t('crop')),
        actions: [
          IconButton(
            tooltip: l10n.t('reset'),
            icon: const Icon(Icons.crop_free_rounded, color: Colors.white),
            onPressed: _busy ? null : _reset,
          ),
        ],
      ),
      body: _imageSize == null
          ? Center(
              child: InoLoader(color: AppColors.primaryGreen))
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

                void dragEdge(int edgeIndex, Offset delta) {
                  // edgeIndex 0: Top (corners 0 [TL] and 1 [TR])
                  // edgeIndex 1: Right (corners 1 [TR] and 2 [BR])
                  // edgeIndex 2: Bottom (corners 3 [BL] and 2 [BR])
                  // edgeIndex 3: Left (corners 0 [TL] and 3 [BL])
                  final (i1, i2) = switch (edgeIndex) {
                    0 => (0, 1), // Top: TL, TR
                    1 => (1, 2), // Right: TR, BR
                    2 => (3, 2), // Bottom: BL, BR
                    _ => (0, 3), // Left: TL, BL
                  };

                  final p1 = toDisplay(_corners[i1]);
                  final p2 = toDisplay(_corners[i2]);
                  final ex = p2.dx - p1.dx;
                  final ey = p2.dy - p1.dy;
                  final len = math.sqrt(ex * ex + ey * ey);
                  if (len < 1.0) return;

                  // Unit normal perpendicular to the edge in screen space.
                  final double nx;
                  final double ny;
                  if (edgeIndex == 1 || edgeIndex == 3) {
                    // Vertical edges: normal points rightwards
                    nx = ey / len;
                    ny = -ex / len;
                  } else {
                    // Horizontal edges: normal points downwards
                    nx = -ey / len;
                    ny = ex / len;
                  }

                  // Project raw screen delta onto the edge normal vector.
                  final dot = delta.dx * nx + delta.dy * ny;
                  final moveNormX = (dot * nx) / rect.width;
                  final moveNormY = (dot * ny) / rect.height;

                  final c1 = _corners[i1];
                  final c2 = _corners[i2];

                  var n1x = (c1.dx + moveNormX).clamp(0.0, 1.0);
                  var n1y = (c1.dy + moveNormY).clamp(0.0, 1.0);
                  var n2x = (c2.dx + moveNormX).clamp(0.0, 1.0);
                  var n2y = (c2.dy + moveNormY).clamp(0.0, 1.0);

                  // Keep minimum spacing so opposite borders don't cross
                  const minGap = 0.05;
                  if (edgeIndex == 0) {
                    // Top edge
                    final maxTopY = math.min(_corners[3].dy, _corners[2].dy) - minGap;
                    n1y = n1y.clamp(0.0, math.max(0.0, maxTopY));
                    n2y = n2y.clamp(0.0, math.max(0.0, maxTopY));
                  } else if (edgeIndex == 2) {
                    // Bottom edge
                    final minBottomY = math.max(_corners[0].dy, _corners[1].dy) + minGap;
                    n1y = n1y.clamp(math.min(1.0, minBottomY), 1.0);
                    n2y = n2y.clamp(math.min(1.0, minBottomY), 1.0);
                  } else if (edgeIndex == 3) {
                    // Left edge
                    final maxLeftX = math.min(_corners[1].dx, _corners[2].dx) - minGap;
                    n1x = n1x.clamp(0.0, math.max(0.0, maxLeftX));
                    n2x = n2x.clamp(0.0, math.max(0.0, maxLeftX));
                  } else if (edgeIndex == 1) {
                    // Right edge
                    final minRightX = math.max(_corners[0].dx, _corners[3].dx) + minGap;
                    n1x = n1x.clamp(math.min(1.0, minRightX), 1.0);
                    n2x = n2x.clamp(math.min(1.0, minRightX), 1.0);
                  }

                  setState(() {
                    final next = [..._corners];
                    next[i1] = Offset(n1x, n1y);
                    next[i2] = Offset(n2x, n2y);
                    _corners = next;
                  });
                }

                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                        cacheWidth: zoomableDecodeCap(context),
                      ),
                    ),
                    // Dim mask + quadrilateral + grid.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CropOverlayPainter(
                          corners: [for (final c in _corners) toDisplay(c)],
                        ),
                      ),
                    ),
                    // Draggable border lines (Top, Right, Bottom, Left).
                    _EdgeLine(
                      p1: toDisplay(_corners[0]),
                      p2: toDisplay(_corners[1]),
                      onDrag: (delta) => dragEdge(0, delta),
                    ),
                    _EdgeLine(
                      p1: toDisplay(_corners[1]),
                      p2: toDisplay(_corners[2]),
                      onDrag: (delta) => dragEdge(1, delta),
                    ),
                    _EdgeLine(
                      p1: toDisplay(_corners[3]),
                      p2: toDisplay(_corners[2]),
                      onDrag: (delta) => dragEdge(2, delta),
                    ),
                    _EdgeLine(
                      p1: toDisplay(_corners[0]),
                      p2: toDisplay(_corners[3]),
                      onDrag: (delta) => dragEdge(3, delta),
                    ),
                    // Draggable corner handles (rendered on top for priority).
                    for (var i = 0; i < 4; i++)
                      _Handle(
                        center: toDisplay(_corners[i]),
                        onDrag: (delta) => dragCorner(i, delta),
                      ),
                    if (_busy)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: Center(
                            child: InoLoader(color: AppColors.primaryGreen),
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
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          side: BorderSide(
                              color:
                                   AppColors.tealPale.withValues(alpha: 0.45)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
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
                          shape: const StadiumBorder(),
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

/// A draggable border line connecting two corners, with a visible grip handle pill in
/// the center and a generous touch breadth along the entire segment.
class _EdgeLine extends StatefulWidget {
  const _EdgeLine({
    required this.p1,
    required this.p2,
    required this.onDrag,
  });

  final Offset p1;
  final Offset p2;
  final ValueChanged<Offset> onDrag;

  @override
  State<_EdgeLine> createState() => _EdgeLineState();
}

class _EdgeLineState extends State<_EdgeLine> {
  Offset? _lastPanPos;

  static const double _touchBreadth = 52.0;

  @override
  Widget build(BuildContext context) {
    final dx = widget.p2.dx - widget.p1.dx;
    final dy = widget.p2.dy - widget.p1.dy;
    final length = math.max(math.sqrt(dx * dx + dy * dy), 32.0);
    final angle = math.atan2(dy, dx);
    final mid = Offset((widget.p1.dx + widget.p2.dx) / 2, (widget.p1.dy + widget.p2.dy) / 2);

    return Positioned(
      left: mid.dx - length / 2,
      top: mid.dy - _touchBreadth / 2,
      child: Transform.rotate(
        angle: angle,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _lastPanPos = d.globalPosition,
          onPanUpdate: (d) {
            if (_lastPanPos == null) {
              _lastPanPos = d.globalPosition;
              return;
            }
            final screenDelta = d.globalPosition - _lastPanPos!;
            _lastPanPos = d.globalPosition;
            widget.onDrag(screenDelta);
          },
          onPanEnd: (_) => _lastPanPos = null,
          onPanCancel: () => _lastPanPos = null,
          child: Container(
            width: length,
            height: _touchBreadth,
            color: Colors.transparent,
            alignment: Alignment.center,
            child: Container(
              width: 38,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.primaryGreen,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
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

  static const double _touch = 48;

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
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
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
