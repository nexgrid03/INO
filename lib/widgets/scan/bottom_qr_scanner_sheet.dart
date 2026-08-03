import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import 'qr_scan_frame.dart';

/// PhonePe-style QR reveal on Home.
///
/// Scroll the home feed as usual. A trailing runway lets you drag up to slide
/// the QR panel in on the same background; drag / scroll back and it leaves.
///
/// Performance: reveal is driven by [ValueNotifier]s so scroll frames only
/// repaint the panel transform — not the whole Home feed.
class HomeQrReveal extends StatefulWidget {
  const HomeQrReveal({
    super.key,
    required this.builder,
    this.heightFactor = 0.72,
  });

  /// Builds the [CustomScrollView]. Append [qrScrollRunway] as the last sliver.
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    Widget qrScrollRunway,
  ) builder;

  final double heightFactor;

  @override
  State<HomeQrReveal> createState() => _HomeQrRevealState();
}

class _HomeQrRevealState extends State<HomeQrReveal> {
  final ScrollController _scroll = ScrollController();

  /// 0 = hidden, 1 = fully open. Scroll listener updates this — never setState.
  final ValueNotifier<double> _revealT = ValueNotifier<double>(0);

  bool _hapticPeek = false;
  bool _snapping = false;
  double _sheetH = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _revealT.dispose();
    super.dispose();
  }

  void _syncSheetHeight() {
    _sheetH = MediaQuery.sizeOf(context).height * widget.heightFactor;
  }

  double get _contentEnd {
    if (!_scroll.hasClients) return 0;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return 0;
    return (pos.maxScrollExtent - _sheetH).clamp(0.0, double.infinity);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions || _sheetH <= 0) return;

    final contentEnd =
        (pos.maxScrollExtent - _sheetH).clamp(0.0, double.infinity);
    final revealPx = (pos.pixels - contentEnd).clamp(0.0, _sheetH);
    final t = (revealPx / _sheetH).clamp(0.0, 1.0);

    // Skip tiny changes to cut notifier churn on web.
    if ((t - _revealT.value).abs() < 0.003) return;
    _revealT.value = t;

    if (t > 0.04 && !_hapticPeek) {
      _hapticPeek = true;
      HapticFeedback.selectionClick();
    } else if (t < 0.02) {
      _hapticPeek = false;
    }
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final next = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((next - pos.pixels).abs() < 0.5) return;
    _scroll.jumpTo(next);
  }

  Future<void> _animateTo(double offset) async {
    if (!_scroll.hasClients || _snapping) return;
    _snapping = true;
    try {
      await _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _snapping = false;
      _onScroll();
    }
  }

  Future<void> _snap() async {
    if (!_scroll.hasClients || _snapping) return;
    final t = _revealT.value;
    if (t <= 0.02 || t >= 0.98) return;
    await _animateTo(t < 0.4 ? _contentEnd : _contentEnd + _sheetH);
  }

  Future<void> _dismiss() => _animateTo(_contentEnd);

  Future<void> _expand() async {
    if (!_scroll.hasClients) return;
    await _animateTo(_scroll.position.maxScrollExtent);
  }

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollEndNotification && !_snapping) _snap();
    return false;
  }

  void _onPanelPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    var dy = e.scrollDelta.dy;
    if (dy > 0 && pos.pixels >= pos.maxScrollExtent - 1) {
      dy = -dy; // further scroll-down dismisses when fully open
    }
    _scrollBy(dy);
  }

  void _onPanelDragUpdate(DragUpdateDetails d) => _scrollBy(-d.delta.dy);

  void _onPanelDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > 700) {
      _dismiss();
    } else if (v < -700) {
      _expand();
    } else {
      _snap();
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncSheetHeight();
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 72;

    // Runway height is fixed; cue listens to reveal without rebuilding the feed.
    final runway = SliverToBoxAdapter(
      child: SizedBox(
        height: _sheetH,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ValueListenableBuilder<double>(
              valueListenable: _revealT,
              builder: (_, t, _) => _PullCue(progress: t),
            ),
          ),
        ),
      ),
    );

    // Feed is built here only when THIS widget rebuilds (data/theme) — not
    // on every scroll tick.
    final feed = RepaintBoundary(
      child: widget.builder(context, _scroll, runway),
    );

    final panel = RepaintBoundary(
      child: Listener(
        onPointerSignal: _onPanelPointerSignal,
        child: Material(
          type: MaterialType.transparency,
          child: HomeQrPanel(
            bottomClearance: bottomClearance,
            onRequestClose: _dismiss,
            onDragUpdate: _onPanelDragUpdate,
            onDragEnd: _onPanelDragEnd,
          ),
        ),
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          feed,
          ValueListenableBuilder<double>(
            valueListenable: _revealT,
            child: panel,
            builder: (context, t, child) {
              final dy = _sheetH * (1.0 - t);
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _sheetH,
                child: IgnorePointer(
                  ignoring: t < 0.05,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    // Transform-only updates stay on the compositor when possible.
                    filterQuality: FilterQuality.none,
                    child: child,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PullCue extends StatelessWidget {
  const _PullCue({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress > 0.12) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final opacity = (1 - progress / 0.12).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Pull up for QR',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transparent QR content (upload PhonePe / UPI image) — no separate surface.
class HomeQrPanel extends StatefulWidget {
  const HomeQrPanel({
    super.key,
    this.bottomClearance = 80,
    this.onRequestClose,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final double bottomClearance;
  final VoidCallback? onRequestClose;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  @override
  State<HomeQrPanel> createState() => _HomeQrPanelState();
}

class _HomeQrPanelState extends State<HomeQrPanel> {
  Uint8List? _qrBytes;
  bool _picking = false;
  ImageProvider? _qrProvider;

  Future<void> _pickQr() async {
    if (_picking) return;
    _picking = true;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _qrBytes = bytes;
        _qrProvider = MemoryImage(bytes);
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Could not open the file picker. Try again or use another browser.'
                : 'Could not open gallery: $e',
          ),
        ),
      );
    } finally {
      _picking = false;
    }
  }

  void _clearQr() {
    setState(() {
      _qrBytes = null;
      _qrProvider = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasQr = _qrBytes != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, widget.bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: widget.onDragUpdate,
                  onVerticalDragEnd: widget.onDragEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: palette.border.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        hasQr ? 'Your QR Code' : 'Add your QR',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasQr
                            ? 'Drag down or scroll to hide · tap to replace'
                            : 'Upload your PhonePe, GPay, or UPI QR.',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasQr)
                IconButton(
                  onPressed: _clearQr,
                  tooltip: 'Remove QR',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: palette.textSecondary,
                  ),
                ),
              if (widget.onRequestClose != null)
                IconButton(
                  onPressed: widget.onRequestClose,
                  tooltip: 'Close',
                  icon: Icon(
                    Icons.close_rounded,
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: widget.onDragUpdate,
              onVerticalDragEnd: widget.onDragEnd,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _pickQr,
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasQr && _qrProvider != null)
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Image(
                            image: _qrProvider!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        )
                      else
                        const _UploadPlaceholder(),
                       IgnorePointer(
                        child: Center(
                          child: QrScanFrame(
                            size: 210,
                            active: false,
                            accent: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _pickQr,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                hasQr ? Icons.sync_rounded : Icons.upload_rounded,
                size: 20,
              ),
              label: Text(
                hasQr ? 'Replace QR image' : 'Upload PhonePe / UPI QR',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadPlaceholder extends StatelessWidget {
  const _UploadPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    final brand = AppColors.primaryGreen;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: dark ? 0.10 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.qr_code_2_rounded,
                size: 32,
                color: brand,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tap to upload QR',
              style: TextStyle(
                color: dark ? palette.textPrimary : brand,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'PhonePe · GPay · any UPI QR',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
