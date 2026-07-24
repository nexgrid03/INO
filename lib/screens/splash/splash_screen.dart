import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/soft_glow.dart';
import '../onboarding/onboarding_screen.dart';

/// Premium "Rama Blue" splash — the lowercase **ino** wordmark assembles
/// itself: the letters FALL in one after another from the top (the "i" stem,
/// then its dot bouncing into place, then the "n"). Then a spark detaches
/// from the **i's dot**, flies across the mark, and spins TWO full turns as a
/// rotating circular stroke that closes into the "o" — so the "o" is literally
/// born from the i's dot. The mark settles with a soft bounce, the tagline
/// fades in, and the screen dissolves into onboarding.
///
/// Behind the mark, a soft atmosphere keeps the screen from ever reading as
/// flat white: two large teal/cyan colour blooms and a scatter of gently
/// drifting, low-opacity brand icons (vault, docs, QR, wealth, health…).
///
/// The REVEAL is driven by ONE [AnimationController] (`_controller`, 5.2s) —
/// each element listens to a slice of its 0→1 timeline via an [Interval], so
/// the phases stay in sync on a single ticker. A second slow controller
/// (`_ambient`) loops the background drift, independent of the reveal. The
/// wordmark is a [CustomPainter] repainted via `super(repaint:)` — no widget
/// rebuilds during the animation — isolated behind a [RepaintBoundary].
///
/// Timeline (controller value in brackets, seconds at 5.2s):
///   0.21s–0.68s [0.04–0.13] the "i" stem falls in from the top
///   0.57s–1.09s [0.11–0.21] the dot drops onto the "i" with a little bounce
///   1.04s–1.77s [0.20–0.34] the "n" falls in from the top
///   1.77s–2.42s [0.34–0.465] a spark detaches from the i's dot and arcs over
///   2.39s–3.74s [0.46–0.72] the spark spins 2 turns and closes the "o"
///   3.95s–4.58s [0.76–0.88] the logo scales up slightly and settles (bounce)
///   3.95s–5.20s [0.76–1.00] the glow pulses once behind the mark
///   4.37s–5.20s [0.84–1.00] tagline fades in + drifts up (~800ms)
///   +0.8s hold, then a 600ms fade into [OnboardingScreen].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Single source of truth for the letter-reveal animation.
  late final AnimationController _controller;

  /// A separate slow loop for the perpetual background drift (decorative
  /// icons bobbing behind the mark) — kept off the reveal timeline.
  late final AnimationController _ambient;
  late final Animation<double> _atmosphereFade;

  // Wordmark phases (consumed by the painter, not by widgets).
  late final Animation<double> _iStemFall; // 0.04–0.13
  late final Animation<double> _iDotFall; //  0.11–0.21
  late final Animation<double> _nFall; //     0.20–0.34
  late final Animation<double> _cometFly; // 0.34–0.465
  late final Animation<double> _oSpin; //     0.46–0.72

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
      duration: const Duration(milliseconds: 5200),
    )..addStatusListener(_onStatusChanged);

    // --- Falling letters --------------------------------------------------
    // Stems land with a whisper of easeOutBack overshoot (a soft touch-down);
    // the "i" dot uses a real bounce for a small, playful landing.
    _iStemFall = _phase(0.04, 0.13, Curves.easeOutBack);
    _iDotFall = _phase(0.11, 0.21, Curves.bounceOut);
    _nFall = _phase(0.20, 0.34, Curves.easeOutBack);

    // --- The spark: leaves the i's dot and arcs over the "n" to the o's
    // starting point. (Ends a hair after the spin begins so there is never a
    // blank frame at the hand-off.)
    _cometFly = _phase(0.34, 0.465, Curves.easeInOutCubic);

    // --- The "o": the spark becomes a rotating stroke that spins TWO full
    // turns while its sweep grows, catching its own tail to close the letter.
    // easeOutCubic = spin starts quick, decelerates elegantly into the close.
    _oSpin = _phase(0.46, 0.72, Curves.easeOutCubic);

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
      CurvedAnimation(parent: _controller, curve: const Interval(0.76, 0.88)),
    );

    // --- Glow: rise softly while the letters land, one gentle pulse as the
    // mark settles, then ease back to a quiet residual. (SoftGlow caps
    // opacity internally, so even the pulse peak stays subtle.)
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 4),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 0.50,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 26,
      ),
      TweenSequenceItem(tween: Tween(begin: 0.50, end: 0.55), weight: 46),
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
        weight: 14,
      ),
    ]).animate(_controller);

    // --- Tagline: a fade + small upward drift once the mark is set.
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

    // Background atmosphere: fade in over the first ~0.9s, then hold.
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _atmosphereFade = _phase(0.0, 0.18, Curves.easeOut);

    // One painter instance for the whole life of the screen — repaints are
    // driven by the controller directly, never by widget rebuilds.
    _painter = _InoWordmarkPainter(
      repaint: _controller,
      iStemFall: _iStemFall,
      iDotFall: _iDotFall,
      nFall: _nFall,
      cometFly: _cometFly,
      oSpin: _oSpin,
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
    _ambient.dispose();
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
    final logoW = (size.shortestSide * 0.56).clamp(190.0, 280.0).toDouble();
    final logoH = logoW * _InoWordmarkPainter.aspect;
    final glowSize = logoW * 1.36;
    final taglineSize = (size.shortestSide * 0.036)
        .clamp(12.0, 16.0)
        .toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFF),
      body: DecoratedBox(
        decoration: _ramaBackground,
        child: Stack(
          children: [
            // Softly drifting brand-icon atmosphere + colour blooms, behind
            // everything, so the screen never reads as flat white.
            Positioned.fill(
              child: _SplashAtmosphere(
                drift: _ambient,
                fade: _atmosphereFade,
              ),
            ),

            SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Wordmark with its glow halo pinned behind it. The box is
                    // exactly the mark's size; the glow overflows it (unclipped)
                    // so layout — and the tagline gap — never shift. The letters
                    // fall in from above the box, also unclipped by design.
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
                    SizedBox(height: logoW * 0.14),

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
          ],
        ),
      ),
    );
  }
}

/// The soft background layer behind the wordmark: two large teal/cyan colour
/// blooms plus a scatter of low-opacity brand icons that gently bob. The whole
/// layer fades in with [fade] (tied to the reveal) and drifts on [drift] (the
/// perpetual ambient loop). Pointer-transparent and repaint-isolated.
class _SplashAtmosphere extends StatelessWidget {
  const _SplashAtmosphere({required this.drift, required this.fade});

  final Animation<double> drift;
  final Animation<double> fade;

  // (icon, position, size, bob-phase) — scattered around the edges so the
  // centred mark + tagline stay clear. Icons echo the app's domains.
  static const List<(IconData, Alignment, double, double)> _icons = [
    (Icons.shield_rounded, Alignment(-0.74, -0.58), 34, 0.0),
    (Icons.description_rounded, Alignment(0.76, -0.66), 30, 0.7),
    (Icons.qr_code_2_rounded, Alignment(-0.82, -0.04), 32, 1.4),
    (Icons.account_balance_wallet_rounded, Alignment(0.80, -0.20), 30, 2.1),
    (Icons.medical_services_rounded, Alignment(-0.62, 0.52), 27, 2.8),
    (Icons.verified_user_rounded, Alignment(0.66, 0.46), 29, 3.5),
    (Icons.lock_rounded, Alignment(0.05, -0.80), 25, 4.2),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: fade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Colour blooms — a warm teal top-right, a cyan bottom-left.
              const Positioned(
                top: -120,
                right: -90,
                child: _Bloom(color: AppColors.primaryGreen, size: 340),
              ),
              const Positioned(
                bottom: -140,
                left: -100,
                child: _Bloom(color: AppColors.skyBlue, size: 320),
              ),

              // Gently bobbing brand icons.
              AnimatedBuilder(
                animation: drift,
                builder: (context, _) {
                  final t = drift.value; // 0→1, repeating
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final (icon, align, size, phase) in _icons)
                        Align(
                          alignment: align,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              7 * math.sin(2 * math.pi * t + phase),
                            ),
                            child: Icon(
                              icon,
                              size: size,
                              color: AppColors.primaryGreen.withValues(
                                alpha: 0.09,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A large, soft radial colour bloom for the background wash.
class _Bloom extends StatelessWidget {
  const _Bloom({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Paints the lowercase **ino** wordmark in brand Rama Blue as it assembles:
/// the "i" stem, its dot and the "n" each FALL in from above the mark (with a
/// soft landing); then a spark detaches from the **i's dot**, arcs over the
/// "n", and spins TWO full turns as a rotating stroke whose sweep grows until
/// it catches its own tail — closing the "o".
///
/// Geometry lives in a fixed 182×110 design space (letter gaps optically
/// matched: the n→o whitespace equals the i→n whitespace) and is scaled to
/// the painted size, so the mark is resolution- and screen-size-independent.
///
/// Phases (each an external 0→1 animation):
///   • [iStemFall] — the "i" stem drops in (easeOutBack = soft touch-down)
///   • [iDotFall]  — the dot drops onto the stem (bounceOut = playful landing)
///   • [nFall]     — the "n" drops in
///   • [cometFly]  — the spark flies from the i's dot to the o's start point
///   • [oSpin]     — the rotating stroke sweeps 2 turns and closes the "o"
class _InoWordmarkPainter extends CustomPainter {
  _InoWordmarkPainter({
    required Listenable repaint,
    required this.iStemFall,
    required this.iDotFall,
    required this.nFall,
    required this.cometFly,
    required this.oSpin,
  }) : super(repaint: repaint);

  final Animation<double> iStemFall;
  final Animation<double> iDotFall;
  final Animation<double> nFall;
  final Animation<double> cometFly;
  final Animation<double> oSpin;

  // --- Design space ---------------------------------------------------------
  static const double _designW = 182;
  static const double _designH = 110;

  /// height / width — used by the widget layer for responsive sizing.
  static const double aspect = _designH / _designW;

  static const double _strokeW = 13;

  // Letterform anchors (baseline y=88, x-height top y=38). The o sits at
  // x=143 so the n→o whitespace optically matches the i→n whitespace.
  static const Offset _iDotCenter = Offset(16, 24);
  static const double _iDotRadius = 7;
  static const Offset _iStemTop = Offset(16, 42);
  static const Offset _iStemBase = Offset(16, 88);

  static const Offset _oCenter = Offset(143, 63);
  static const double _oRadius = 25;

  /// Where the o's stroke begins (its top point) — the comet's landing spot.
  static const Offset _oTop = Offset(143, 38);

  /// Control point of the comet's flight arc (soars above the letters).
  static const Offset _cometCtrl = Offset(80, -6);

  /// How far above their resting place the falling letters start (design px).
  static const double _dropStem = 60;
  static const double _dropDot = 72;
  static const double _dropN = 60;

  /// The o's tail rotates 2 full turns while the sweep grows to 2π — the
  /// head races ahead and catches the tail exactly as the circle closes.
  static const double _oSpinTurns = 2.0;

  /// "n": left stem up, arch over, right stem down — drawn as one full path
  /// (the letter falls in complete).
  static final Path _nPath = Path()
    ..moveTo(46, 88)
    ..lineTo(46, 59)
    ..arcToPoint(const Offset(88, 59), radius: const Radius.circular(21))
    ..lineTo(88, 88);

  static final Rect _oRect = Rect.fromCircle(
    center: _oCenter,
    radius: _oRadius,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _designW;
    canvas.save();
    canvas.scale(scale, scale);

    // 1. The "i" stem falls from above and touches down (easeOutBack lets it
    // sink a hair past its rest and lift back — a soft landing).
    final sv = iStemFall.value;
    if (sv > 0) {
      final paint = _strokePaint(_riseAlpha(sv));
      canvas.save();
      canvas.translate(0, -_dropStem * (1 - sv));
      canvas.drawLine(_iStemBase, _iStemTop, paint);
      canvas.restore();
    }

    // 2. The dot drops onto the "i" and bounces to rest.
    final dv = iDotFall.value;
    if (dv > 0) {
      final paint = Paint()
        ..color = AppColors.primaryGreen.withValues(alpha: _riseAlpha(dv));
      canvas.save();
      canvas.translate(0, -_dropDot * (1 - dv));
      canvas.drawCircle(_iDotCenter, _iDotRadius, paint);
      canvas.restore();
    }

    // 3. The "n" falls in as a complete letter.
    final nv = nFall.value;
    if (nv > 0) {
      final paint = _strokePaint(_riseAlpha(nv));
      canvas.save();
      canvas.translate(0, -_dropN * (1 - nv));
      canvas.drawPath(_nPath, paint);
      canvas.restore();
    }

    // 4. The spark: detaches from the i's dot and arcs over the letters to
    // the o's top point, trailing two fading echoes behind it.
    final cv = cometFly.value.clamp(0.0, 1.0);
    final ov = oSpin.value.clamp(0.0, 1.0);
    if (cv > 0 && cv < 1) {
      for (var k = 2; k >= 0; k--) {
        final t = cv - k * 0.07;
        if (t <= 0) continue;
        final p = _cometAt(t.clamp(0.0, 1.0));
        final r = (_strokeW / 2) * (1 - k * 0.28);
        final a = k == 0 ? 1.0 : (0.34 - k * 0.12);
        canvas.drawCircle(
          p,
          r,
          Paint()..color = AppColors.primaryGreen.withValues(alpha: a),
        );
      }
    }

    // 5. The "o": the spark becomes a rotating stroke. The tail keeps
    // spinning (2 turns) while the sweep grows, so the head races around the
    // ring and closes the circle — at ov == 1 the sweep is a full 2π.
    if (ov > 0.004) {
      final paint = _strokePaint(1.0);
      final tail = -math.pi / 2 + 2 * math.pi * _oSpinTurns * ov;
      final sweep = 2 * math.pi * ov;
      canvas.drawArc(_oRect, tail, sweep, false, paint);
    }

    canvas.restore();
  }

  /// Quadratic-bezier position of the comet: i-dot → high arc → o's top.
  static Offset _cometAt(double t) {
    final u = 1 - t;
    return Offset(
      u * u * _iDotCenter.dx + 2 * u * t * _cometCtrl.dx + t * t * _oTop.dx,
      u * u * _iDotCenter.dy + 2 * u * t * _cometCtrl.dy + t * t * _oTop.dy,
    );
  }

  /// Quick fade-in so letters materialise as they start moving, reaching full
  /// opacity within the first third of their phase. (Overshooting curves can
  /// push v past 1.0 — clamped.)
  static double _riseAlpha(double v) => (v * 3).clamp(0.0, 1.0);

  static Paint _strokePaint(double alpha) => Paint()
    ..color = AppColors.primaryGreen.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = _strokeW
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // Repaints are driven entirely by the `repaint` listenable.
  @override
  bool shouldRepaint(covariant _InoWordmarkPainter oldDelegate) => false;
}
