import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/soft_glow.dart';
import '../onboarding/onboarding_screen.dart';

/// The INO splash - the app icon (teal INO shield) pops in with a soft glow,
/// the tagline fades up beneath it, and the screen dissolves into onboarding.
///
/// Deliberately simple: ONE [AnimationController] (2.6s) drives every phase
/// through [Interval] slices, so the whole reveal stays on a single ticker.
///
/// Timeline (controller value in brackets, seconds at 2.6s):
///   0.00s–1.14s [0.00–0.44] icon fades in and scales 0.72 → 1.0 (easeOutBack)
///   0.52s–1.95s [0.20–0.75] the glow rises behind the icon and settles
///   1.43s–2.34s [0.55–0.90] tagline fades in + drifts up
///   +0.7s hold, then a 600ms fade into [OnboardingScreen].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _glow;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..addStatusListener(_onStatusChanged);

    // Icon entrance: a quick fade with a gentle overshoot pop - the icon
    // lands a hair past full size and eases back.
    _iconFade = _phase(0.00, 0.30, Curves.easeOut);
    _iconScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.00, 0.44, curve: Curves.easeOutBack),
      ),
    );

    // Glow: rises as the icon lands, one soft crest, then settles to a quiet
    // residual so the mark keeps a warm halo while the tagline appears.
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 20),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.5,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(0.5), weight: 25),
    ]).animate(_controller);

    // Tagline: fade + a small upward drift once the icon is set.
    _taglineFade = _phase(0.55, 0.90, Curves.easeIn);
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.30),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOut),
      ),
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
      // Hold the finished frame briefly, then dissolve into onboarding.
      Future<void>.delayed(const Duration(milliseconds: 700), _goToOnboarding);
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

  /// App-wide hero-sky backdrop (matches InoBackground): the full brand
  /// skyBlue at the top melting to the pale base past mid-screen.
  static const BoxDecoration _ramaBackground = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF7DD3FC), // brand skyBlue crown
        Color(0xFFB2E2FC), // deep melt through the hero
        Color(0xFFE3F3FD), // pale wash past mid-screen
        Color(0xFFEAF4FC), // brand base
      ],
      stops: [0.0, 0.28, 0.62, 1.0],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // Responsive mark: sized off the shortest side so phones, tablets and
    // foldables all get a comfortable, centred icon with no overflow.
    final iconSize = (size.shortestSide * 0.40).clamp(140.0, 220.0).toDouble();
    final glowSize = iconSize * 1.55;
    final taglineSize = (size.shortestSide * 0.036)
        .clamp(12.0, 16.0)
        .toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FCFF),
      body: DecoratedBox(
        decoration: _ramaBackground,
        child: Stack(
          children: [
            // Static colour blooms so the screen never reads as flat white.
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

            SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App icon with its glow halo pinned behind it. The box is
                    // exactly the icon's size; the glow overflows it
                    // (unclipped) so layout - and the tagline gap - never
                    // shift.
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: (iconSize - glowSize) / 2,
                            top: (iconSize - glowSize) / 2,
                            width: glowSize,
                            height: glowSize,
                            child: SoftGlow(animation: _glow, size: glowSize),
                          ),
                          Positioned.fill(
                            child: FadeTransition(
                              opacity: _iconFade,
                              child: ScaleTransition(
                                scale: _iconScale,
                                child: Image.asset(
                                  // Transparent, tightly-cropped shield - the
                                  // full launcher icon has an opaque white
                                  // background that read as a white box here.
                                  'assets/icon/ino_icon_splash.png',
                                  fit: BoxFit.contain,
                                  // Never let a missing asset blank the splash:
                                  // fall back to the brand shield glyph.
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.shield_rounded,
                                    size: 120,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: iconSize * 0.18),

                    // Tagline - uppercase, tracked out, quiet charcoal.
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
                                color: AppColors.textMuted,
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
