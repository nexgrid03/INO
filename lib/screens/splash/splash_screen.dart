import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ino_logo.dart';
import '../../widgets/soft_glow.dart';
import '../onboarding/onboarding_screen.dart';

/// Premium, fintech-style animated splash screen.
///
/// The whole on-screen sequence is driven by ONE [AnimationController]
/// (`_controller`, 3.5s long). Each visual element listens to a slice of that
/// controller's 0→1 timeline via an [Interval], so the phases stay perfectly
/// in sync and we only pay for a single ticker. When the controller finishes
/// (at 3.5s) we push the onboarding screen with a 0.5s fade — landing the
/// transition at the 4.0s mark described in the spec.
///
/// Timeline (controller value in brackets):
///   0.0s–0.3s  [0.00–0.086]  background gradient fades in
///   0.3s–1.0s  [0.086–0.286] logo scales 70%→100% + fades in (subtle spring)
///   1.0s–1.8s  [0.286–0.514] soft glow blooms once behind the logo
///   1.8s–2.4s  [0.514–0.686] app name fades in + slides up slightly
///   2.4s–3.0s  [0.686–0.857] tagline fades in + slides up slightly
///   3.0s–3.5s  [0.857–1.00]  hold the finished frame
///   3.5s–4.0s                fade out into the onboarding screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Single source of truth for the entire splash animation.
  late final AnimationController _controller;

  // Phase animations, each mapped to a slice of the controller timeline.
  late final Animation<double> _backgroundFade; // 0.0s–0.3s
  late final Animation<double> _logoScale; //      0.3s–1.0s
  late final Animation<double> _logoFade; //       0.3s–1.0s
  late final Animation<double> _glow; //           1.0s–1.8s
  late final Animation<double> _nameFade; //       1.8s–2.4s
  late final Animation<Offset> _nameSlide; //      1.8s–2.4s
  late final Animation<double> _taglineFade; //    2.4s–3.0s
  late final Animation<Offset> _taglineSlide; //   2.4s–3.0s

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..addStatusListener(_onStatusChanged);

    // --- Background: a gentle opacity ramp so the gradient never "snaps" in.
    _backgroundFade = _curved(0.0, 0.086, Curves.easeOut);

    // --- Logo: grow from 70% to 100% with easeOutBack for a *subtle* spring
    // (a tiny overshoot, not a cartoon bounce), fading in slightly faster.
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.086, 0.286, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = _curved(0.086, 0.20, Curves.easeIn);

    // --- Glow: bloom up then ease back to a soft residual — one elegant pulse.
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.4)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.286, 0.514),
      ),
    );

    // --- App name: fade + a small upward slide for a refined reveal.
    _nameFade = _curved(0.514, 0.686, Curves.easeIn);
    _nameSlide = _slideUp(0.514, 0.686);

    // --- Tagline: same treatment, starting just after the name.
    _taglineFade = _curved(0.686, 0.857, Curves.easeIn);
    _taglineSlide = _slideUp(0.686, 0.857);

    _controller.forward();
  }

  /// Convenience: an opacity (0→1) animation over a controller [Interval].
  Animation<double> _curved(double begin, double end, Curve curve) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: curve),
      ),
    );
  }

  /// Convenience: a slight bottom→center slide over a controller [Interval].
  Animation<Offset> _slideUp(double begin, double end) {
    return Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: Curves.easeOut),
      ),
    );
  }

  void _onStatusChanged(AnimationStatus status) {
    // Controller reaches the end at 3.5s → begin the transition to onboarding.
    if (status == AnimationStatus.completed) {
      _goToOnboarding();
    }
  }

  void _goToOnboarding() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // White base so the gradient can fade *in* over it during phase 1.
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Phase 1 — background gradient fades in.
          Positioned.fill(
            child: FadeTransition(
              opacity: _backgroundFade,
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.brandGradient),
              ),
            ),
          ),

          // Foreground content.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with its glow halo behind it.
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Phase 3 — soft glow (isolated repaint).
                    SoftGlow(animation: _glow, size: 230),
                    // Phase 2 — logo scale + fade.
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const InoLogo(size: 130),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // Phase 4 — app name.
                SlideTransition(
                  position: _nameSlide,
                  child: FadeTransition(
                    opacity: _nameFade,
                    child: const Text(
                      'INO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Phase 5 — subtitle (the full product name).
                SlideTransition(
                  position: _taglineSlide,
                  child: FadeTransition(
                    opacity: _taglineFade,
                    child: Text(
                      'Intelligent Network Organizer',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom tagline, anchored to the safe area (fades in with phase 5).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'Securely Organize Your Digital Life',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
