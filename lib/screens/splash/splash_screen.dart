import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/soft_glow.dart';
import '../onboarding/onboarding_screen.dart';

/// Premium "Rama Blue" splash — the lowercase **ino** wordmark draws itself
/// stroke by stroke on a soft teal-mist gradient, settles with a gentle
/// bounce, reveals the tagline, then fades into onboarding.
///
/// The whole sequence is driven by ONE [AnimationController] (3.8s). Each
/// element listens to a slice of the 0→1 timeline via an [Interval], so the
/// phases stay perfectly in sync and we only pay for a single ticker. The
/// wordmark itself is a [CustomPainter] repainted via `super(repaint:)` — no
/// widget rebuilds at all during the animation, and it's isolated behind a
/// [RepaintBoundary] for a steady 60fps.
///
/// Timeline (controller value in brackets):
///   0.15s–0.46s [0.04–0.12] the "i" dot pops in (soft easeOutBack)
///   0.42s–0.91s [0.11–0.24] the "i" stem grows upward from the baseline
///   0.91s–1.63s [0.24–0.43] the "n" is stroked left → right
///   1.63s–2.32s [0.43–0.61] the "o" draws as a ¾-open circle
///   2.32s–2.96s [0.61–0.78] the gap becomes three shrinking dots (staggered)
///   2.96s–3.42s [0.78–0.90] the logo scales up slightly and settles (bounce)
///   2.96s–3.80s [0.78–1.00] the glow pulses once behind the mark
///   3.19s–3.80s [0.84–1.00] tagline fades in + drifts up (~600ms)
///   +0.8s hold, then a 600ms fade into [OnboardingScreen].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Single source of truth for the entire splash animation.
  late final AnimationController _controller;

  // Wordmark phases (consumed by the painter, not by widgets).
  late final Animation<double> _iDot; //    0.04–0.12
  late final Animation<double> _iStem; //   0.11–0.24
  late final Animation<double> _n; //       0.24–0.43
  late final Animation<double> _o; //       0.43–0.61
  late final List<Animation<double>> _gapDots; // 0.61–0.78, staggered ×3

  // Whole-mark settle bounce + glow pulse + tagline reveal.
  late final Animation<double> _settle;
  late final Animation<double> _glow;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;

  late final _InoWordmarkPainter _painter;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..addStatusListener(_onStatusChanged);

    // --- Wordmark strokes -----------------------------------------------
    _iDot = _phase(0.04, 0.12, Curves.easeOutBack);
    _iStem = _phase(0.11, 0.24, Curves.easeInOutCubic);
    _n = _phase(0.24, 0.43, Curves.easeInOutCubic);
    _o = _phase(0.43, 0.61, Curves.easeInOutCubic);
    _gapDots = [
      _phase(0.61, 0.68, Curves.easeOutBack),
      _phase(0.66, 0.73, Curves.easeOutBack),
      _phase(0.71, 0.78, Curves.easeOutBack),
    ];

    // --- Settle: scale up slightly, dip a hair under, land at 1.0 — a soft
    // bounce, never a cartoon spring.
    _settle = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.05,
          end: 0.99,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 32,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.99,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 28,
      ),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.78, 0.90)),
    );

    // --- Glow: rise softly while the mark draws, one gentle pulse as it
    // settles, then ease back to a quiet residual. (SoftGlow caps opacity
    // internally, so even the pulse peak stays subtle.)
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 4),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 0.50,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 26,
      ),
      TweenSequenceItem(tween: Tween(begin: 0.50, end: 0.55), weight: 48),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.55,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.45,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
    ]).animate(_controller);

    // --- Tagline: a ~600ms fade + small upward drift once the mark is set.
    _taglineFade = _phase(0.84, 1.00, Curves.easeIn);
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.30),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.84, 1.00, curve: Curves.easeOut),
      ),
    );

    // One painter instance for the whole life of the screen — repaints are
    // driven by the controller directly, never by widget rebuilds.
    _painter = _InoWordmarkPainter(
      repaint: _controller,
      iDot: _iDot,
      iStem: _iStem,
      n: _n,
      o: _o,
      gapDots: _gapDots,
    );

    _controller.forward();
  }

  /// Convenience: a 0→1 animation over a slice of the controller timeline.
  Animation<double> _phase(double begin, double end, Curve curve) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: curve),
      ),
    );
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Hold the finished frame for 0.8s, then dissolve into onboarding.
      Future<void>.delayed(const Duration(milliseconds: 800), _goToOnboarding);
    }
  }

  void _goToOnboarding() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => const OnboardingScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Rama Blue backdrop — a soft top-lit teal mist, never plain white.
  static const BoxDecoration _ramaBackground = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFF8FFFF), // airy near-white sky
        Color(0xFFEAF9F9), // soft teal mist
        Color(0xFFDFF8F8), // gentle teal base
      ],
      stops: [0.0, 0.5, 1.0],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // Responsive mark: sized off the shortest side so phones, tablets and
    // foldables all get a comfortable, centred logo with no overflow.
    final logoW = (size.shortestSide * 0.52).clamp(180.0, 264.0).toDouble();
    final logoH = logoW * _InoWordmarkPainter.aspect;
    final glowSize = logoW * 1.42;
    final taglineSize = (size.shortestSide * 0.036)
        .clamp(12.0, 16.0)
        .toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFF),
      body: DecoratedBox(
        decoration: _ramaBackground,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wordmark with its glow halo pinned behind it. The box is
                // exactly the mark's size; the glow overflows it (unclipped)
                // so layout — and the tagline gap — never shift.
                SizedBox(
                  width: logoW,
                  height: logoH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: (logoW - glowSize) / 2,
                        top: (logoH - glowSize) / 2,
                        width: glowSize,
                        height: glowSize,
                        child: SoftGlow(animation: _glow, size: glowSize),
                      ),
                      Positioned.fill(
                        child: ScaleTransition(
                          scale: _settle,
                          child: RepaintBoundary(
                            child: CustomPaint(painter: _painter),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: logoW * 0.15),

                // Tagline — uppercase, tracked out, quiet charcoal.
                SlideTransition(
                  position: _taglineSlide,
                  child: FadeTransition(
                    opacity: _taglineFade,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'YOUR ASSISTANT. SIMPLE LIFE.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF303030),
                            fontSize: taglineSize,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 3.2,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the lowercase **ino** wordmark stroke by stroke in brand Rama Blue.
///
/// Geometry lives in a fixed 170×110 design space and is scaled to the
/// painted size, so the mark is resolution- and screen-size-independent.
///
/// Phases (each an external 0→1 animation):
///   • [iDot]    — the "i" dot pops in (easeOutBack overshoot = soft pop)
///   • [iStem]   — the "i" stem grows upward from the baseline
///   • [n]       — the "n" is revealed along its path, left → right
///   • [o]       — the "o" sweeps as a ¾ circle, leaving an upper-right gap
///   • [gapDots] — three staggered dots fill the gap, progressively smaller
///                 and lighter along the brand tint ladder
class _InoWordmarkPainter extends CustomPainter {
  _InoWordmarkPainter({
    required Listenable repaint,
    required this.iDot,
    required this.iStem,
    required this.n,
    required this.o,
    required this.gapDots,
  }) : super(repaint: repaint);

  final Animation<double> iDot;
  final Animation<double> iStem;
  final Animation<double> n;
  final Animation<double> o;
  final List<Animation<double>> gapDots;

  // --- Design space ---------------------------------------------------------
  static const double _designW = 170;
  static const double _designH = 110;

  /// height / width — used by the widget layer for responsive sizing.
  static const double aspect = _designH / _designW;

  static const double _strokeW = 13;

  // Letterform anchors (baseline y=88, x-height top y=38).
  static const Offset _iDotCenter = Offset(16, 24);
  static const double _iDotRadius = 7;
  static const Offset _iStemBase = Offset(16, 88);
  static const double _iStemRise = 46; // grows to y=42

  static const Offset _oCenter = Offset(126, 63);
  static const double _oRadius = 25;

  // The "o" gap sits in the upper-right quadrant (top → right). The three
  // trailing dots continue the stroke's clockwise motion through it,
  // shrinking and lightening as they go.
  static const List<double> _gapAngles = [-1.187, -0.785, -0.384]; // −68/−45/−22°
  static const List<double> _gapRadii = [25, 26, 27];
  static const List<double> _gapSizes = [6.5, 5.0, 3.5];
  static const List<Color> _gapColors = [
    AppColors.primaryGreen, // #30ACB3
    AppColors.secondaryGreen, // #55C2C8
    AppColors.skyBlue, // #7FD3D8
  ];

  /// "n": left stem up, arch over, right stem down — one continuous path so
  /// the left→right reveal follows the natural writing direction.
  static final Path _nPath = Path()
    ..moveTo(46, 88)
    ..lineTo(46, 59)
    ..arcToPoint(const Offset(88, 59), radius: const Radius.circular(21))
    ..lineTo(88, 88);

  /// "o": ¾ circle starting at the right (3 o'clock), sweeping clockwise
  /// through bottom → left → top, leaving the upper-right quarter open.
  static final Path _oPath = Path()
    ..addArc(
      Rect.fromCircle(center: _oCenter, radius: _oRadius),
      0,
      3 * math.pi / 2,
    );

  // Path metrics are computed once and reused every frame.
  PathMetric? _nMetric;
  PathMetric? _oMetric;

  static final Paint _stroke = Paint()
    ..color = AppColors.primaryGreen
    ..style = PaintingStyle.stroke
    ..strokeWidth = _strokeW
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _brandFill = Paint()..color = AppColors.primaryGreen;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _designW;
    canvas.save();
    canvas.scale(scale, scale);

    // 1. The "i" dot pops in (easeOutBack briefly overshoots 1.0 — a soft pop).
    final dv = iDot.value;
    if (dv > 0) {
      canvas.drawCircle(_iDotCenter, _iDotRadius * dv, _brandFill);
    }

    // 2. The "i" stem grows upward from the baseline.
    final sv = iStem.value.clamp(0.0, 1.0);
    if (sv > 0.004) {
      canvas.drawLine(
        _iStemBase,
        Offset(_iStemBase.dx, _iStemBase.dy - _iStemRise * sv),
        _stroke,
      );
    }

    // 3. The "n" strokes on, left → right.
    final nv = n.value.clamp(0.0, 1.0);
    if (nv > 0.004) {
      _nMetric ??= _nPath.computeMetrics().first;
      canvas.drawPath(
        _nMetric!.extractPath(0, _nMetric!.length * nv),
        _stroke,
      );
    }

    // 4. The "o" sweeps as a ¾-open circle.
    final ov = o.value.clamp(0.0, 1.0);
    if (ov > 0.004) {
      _oMetric ??= _oPath.computeMetrics().first;
      canvas.drawPath(
        _oMetric!.extractPath(0, _oMetric!.length * ov),
        _stroke,
      );
    }

    // 5. The gap becomes three staggered, shrinking, lightening dots.
    for (var i = 0; i < gapDots.length; i++) {
      final v = gapDots[i].value;
      if (v <= 0) continue;
      final center = Offset(
        _oCenter.dx + _gapRadii[i] * math.cos(_gapAngles[i]),
        _oCenter.dy + _gapRadii[i] * math.sin(_gapAngles[i]),
      );
      canvas.drawCircle(center, _gapSizes[i] * v, Paint()..color = _gapColors[i]);
    }

    canvas.restore();
  }

  // Repaints are driven entirely by the `repaint` listenable.
  @override
  bool shouldRepaint(covariant _InoWordmarkPainter oldDelegate) => false;
}
