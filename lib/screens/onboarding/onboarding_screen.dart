import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_settings.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../widgets/floating_particles.dart';
import '../../widgets/pressable_scale.dart';
import 'floating_satellites.dart';
import 'onboarding_icon.dart';
import 'onboarding_layout.dart';
import 'secured_intro_screen.dart';

/// A single onboarding slide's content.
class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// Intro carousel shown after the splash on first launch.
///
/// Has 3 slides explaining the app, a Skip button, page indicator dots, and a
/// full-width gradient "next" CTA. Both Skip and the CTA on the last page
/// mark onboarding complete and navigate to [SecuredIntroScreen].
///
/// Visual language follows the Stitch onboarding set: a soft ambient gradient
/// wash behind everything, a rounded hero panel holding the animated
/// illustration, an uppercase step pill, a two-tone headline (first line in
/// the ambient text colour, second line in brand teal), left-aligned copy,
/// left-aligned progress dots and a full-bleed gradient pill CTA.
///
/// Animation ownership (important - this is what avoids the "blank then load"
/// flash): each [_OnboardingSlide] owns its OWN entrance controller and plays
/// it as the page is built / slides in. There is NO shared controller that
/// gets reset after a page settles, so a centred page is never blanked.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// Slow, perpetual loop for the floating background particles.
  late final AnimationController _particles;

  /// One-time entrance for the gradient CTA (played once; never reset, so it
  /// never blanks when changing pages).
  late final AnimationController _intro;
  late final Animation<Offset> _arrowSlide;
  late final Animation<double> _arrowFade;
  late final Animation<double> _arrowScale;

  /// Short pop played on the active indicator dot when the page changes.
  late final AnimationController _dotPop;
  late final Animation<double> _dotPopScale;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.folder_shared_rounded,
      title: 'All Your Documents,\nOne Secure Vault',
      description:
          'Aadhaar, PAN, Passport and more - encrypted and '
          'always within reach.',
    ),
    _OnboardingPage(
      icon: Icons.insights_rounded,
      title: 'Track Wealth\n& Health',
      description:
          'Property, investments and health records, '
          'organised at a glance.',
    ),
    _OnboardingPage(
      icon: Icons.qr_code_2_rounded,
      title: 'Share Instantly\n& Safely',
      description:
          'Send documents in seconds with secure QR codes, '
          'protected by biometrics.',
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void initState() {
    super.initState();

    _particles = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _arrowSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _arrowFade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _arrowScale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _intro.forward();

    _dotPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _dotPopScale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.14), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.14, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _dotPop, curve: Curves.easeOutCubic));
  }

  void _onPageChanged(int index) {
    HapticFeedback.lightImpact(); // light vibration on page change
    setState(() => _currentPage = index);
    _dotPop.forward(from: 0); // pop the newly-active dot
  }

  /// Mark onboarding done and hand off to the secured lock intro.
  Future<void> _finishOnboarding() async {
    await AppSettings.instance.setOnboardingSeen(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => const SecuredIntroScreen(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _onNextPressed() {
    HapticFeedback.lightImpact(); // subtle feedback on Next / Get Started
    if (_isLastPage) {
      _finishOnboarding();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _particles.dispose();
    _intro.dispose();
    _dotPop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final flat = InoStyle.usesFlatBackdrop(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Soft brand wash — skipped on Aqua Light (flat solid bg).
          if (!palette.isDark && !flat)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.tealMist,
                        AppColors.tealPale,
                        AppColors.tealFoam,
                        palette.bg,
                      ],
                      stops: const [0.0, 0.32, 0.68, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          if (!flat) ...[
            Positioned(
              top: -120,
              right: -90,
              child: _AmbientBlob(color: AppColors.primaryGreen, size: 340),
            ),
            Positioned(
              bottom: -140,
              left: -110,
              child: _AmbientBlob(color: AppColors.lightBlue, size: 320),
            ),
            Positioned.fill(child: FloatingParticles(animation: _particles)),
          ],

          SafeArea(
            minimum: const EdgeInsets.only(
              bottom: OnboardingLayout.safeBottomMinimum,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Slides use the same Spacer rhythm as SecuredIntroScreen.
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) => _OnboardingSlide(
                      key: ValueKey(index),
                      page: _pages[index],
                      index: index,
                      total: _pages.length,
                      controller: _pageController,
                    ),
                  ),
                ),

                // CTA band — same insets as SecuredIntroScreen Get Started.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OnboardingLayout.bottomHorizontal,
                    0,
                    OnboardingLayout.bottomHorizontal,
                    OnboardingLayout.bottomPadding,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pages.length, (index) {
                          final dot = _Dot(isActive: index == _currentPage);
                          return index == _currentPage
                              ? ScaleTransition(scale: _dotPopScale, child: dot)
                              : dot;
                        }),
                      ),
                      const SizedBox(height: 16),
                      SlideTransition(
                        position: _arrowSlide,
                        child: FadeTransition(
                          opacity: _arrowFade,
                          child: ScaleTransition(
                            scale: _arrowScale,
                            child: PressableScale(
                              child: _GradientNextButton(
                                onTap: _onNextPressed,
                                label:
                                    _isLastPage ? 'Get Started' : 'Continue',
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Skip under the CTA — keep a fixed slot so layout
                      // doesn't jump; hide on the last page.
                      const SizedBox(height: 4),
                      AnimatedOpacity(
                        opacity: _isLastPage ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: IgnorePointer(
                          ignoring: _isLastPage,
                          child: TextButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _finishOnboarding();
                            },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(64, 44),
                              tapTargetSize: MaterialTapTargetSize.padded,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The visual content of a single onboarding slide, in the Stitch onboarding
/// language: a soft gradient-washed hero panel holding the animated
/// illustration, then an uppercase step pill, a two-tone headline and the
/// supporting copy - all left-aligned.
///
/// Each slide owns a short entrance controller that plays in [initState] - so
/// the reveal happens *as the page slides in*, and a centred page is never
/// reset to blank. On top of the entrance, a [PageController]-driven parallax
/// shifts the hero more than the text and scales the content down slightly
/// while swiping.
class _OnboardingSlide extends StatefulWidget {
  const _OnboardingSlide({
    super.key,
    required this.page,
    required this.index,
    required this.total,
    required this.controller,
  });

  final _OnboardingPage page;
  final int index;
  final int total;
  final PageController controller;

  @override
  State<_OnboardingSlide> createState() => _OnboardingSlideState();
}

class _OnboardingSlideState extends State<_OnboardingSlide>
    with TickerProviderStateMixin {
  late final AnimationController _c;

  /// Perpetual loop that drives the gentle bobbing of the floating satellites.
  late final AnimationController _float;

  // Staggered phases over a ~900ms controller — fast but still readable:
  //   circle  0.00–0.22
  //   inner   0.10–0.36
  //   chips   0.34–0.72  (FloatingSatellites)
  //   title   0.68–0.86
  //   desc    0.80–1.00
  late final Animation<Offset> _contentSlide;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconFade;
  late final Animation<double> _glow;
  late final Animation<double> _reveal;
  late final Animation<double> _folderPop;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _descSlide;
  late final Animation<double> _descFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat(reverse: true);

    _contentSlide = _slide(0.0, 0.26, 0.03);
    _iconScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.00, 0.22, curve: Curves.easeOutCubic),
      ),
    );
    _iconFade = _fade(0.0, 0.16);
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(CurvedAnimation(parent: _c, curve: const Interval(0.08, 0.36)));
    _reveal = _fade(0.08, 0.36, Curves.easeInOutCubic);
    _folderPop = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.08, 0.32, curve: Curves.easeOutCubic),
      ),
    );
    _titleSlide = _slide(0.68, 0.86, 0.22);
    _titleFade = _fade(0.68, 0.86);
    _descSlide = _slide(0.80, 1.0, 0.18);
    _descFade = _fade(0.80, 1.0);

    _c.forward();
  }

  Animation<double> _fade(
    double begin,
    double end, [
    Curve curve = Curves.easeIn,
  ]) {
    return CurvedAnimation(
      parent: _c,
      curve: Interval(begin, end, curve: curve),
    );
  }

  Animation<Offset> _slide(double begin, double end, double from) {
    return Tween<Offset>(begin: Offset(0, from), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    _float.dispose();
    super.dispose();
  }

  /// The illustration itself - the animated circle + floating satellite chips,
  /// floating directly on the page background (no panel behind it). The 160px
  /// box preserves the internal layout; satellites overflow via Clip.none.
  Widget _illustration() {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Contextual chips floating around the circle.
          FloatingSatellites(index: widget.index, pop: _c, float: _float),
          // The main animated circle (unchanged).
          FadeTransition(
            opacity: _iconFade,
            child: ScaleTransition(
              scale: _iconScale,
              child: AnimatedOnboardingIcon(
                index: widget.index,
                icon: widget.page.icon,
                glow: _glow,
                reveal: _reveal,
                folderPop: _folderPop,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A tiny step indicator that replaces the old "STEP 1 OF 3" pill - same
  /// info, a fraction of the footprint (the progress dots carry the rest).
  Widget _stepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '${widget.index + 1} / ${widget.total}',
        style: AppText.label.copyWith(
          fontSize: 11,
          letterSpacing: 1.0,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }

  /// Two-tone headline — same size/height as SecuredIntroScreen title.
  Widget _titleText(AppPalette palette) {
    final title = widget.page.title;
    final int nl = title.indexOf('\n');
    final style = AppText.display.copyWith(
      fontSize: OnboardingLayout.titleSize,
      height: OnboardingLayout.titleHeight,
      color: palette.textPrimary,
    );
    if (nl == -1) {
      return Text(title, textAlign: TextAlign.center, style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: title.substring(0, nl)),
          TextSpan(
            text: title.substring(nl),
            style: TextStyle(color: AppColors.primaryGreen),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Rebuilds only while the PageView is scrolling (drives the parallax).
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        double delta = 0;
        if (widget.controller.hasClients &&
            widget.controller.position.haveDimensions) {
          delta =
              (widget.controller.page ?? widget.index.toDouble()) -
              widget.index;
        }
        final double iconShift = -delta * 36;
        final double textShift = -delta * 14;
        final double swipeScale = (1 - delta.abs() * 0.08).clamp(0.0, 1.0);

        // Mirror SecuredIntroScreen:
        //   Spacer(5) → 300 scene → Spacer(2) → copy → Spacer(2)
        // (CTA lives in the parent, matching secured's bottom padding band.)
        return LayoutBuilder(
          builder: (context, constraints) {
            // Leave room for copy (~150) so spacers never force a 300 overflow
            // on short phones — scene shrinks via FittedBox instead.
            final double sceneSide = (constraints.maxHeight - 150)
                .clamp(OnboardingLayout.sceneMin, OnboardingLayout.sceneSize);

            return SlideTransition(
              position: _contentSlide,
              child: Column(
                children: [
                  const Spacer(flex: OnboardingLayout.spacerTop),
                  SizedBox(
                    width: sceneSide,
                    height: sceneSide,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: OnboardingLayout.sceneSize,
                        height: OnboardingLayout.sceneSize,
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(iconShift, 0),
                            child: Transform.scale(
                              scale: swipeScale *
                                  OnboardingLayout.illustrationScale,
                              child: _illustration(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: OnboardingLayout.spacerMid),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnboardingLayout.textHorizontal,
                    ),
                    child: Column(
                      children: [
                        Transform.translate(
                          offset: Offset(textShift, 0),
                          child: SlideTransition(
                            position: _titleSlide,
                            child: FadeTransition(
                              opacity: _titleFade,
                              child: Column(
                                children: [
                                  _stepIndicator(),
                                  const SizedBox(height: 12),
                                  _titleText(palette),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Transform.translate(
                          offset: Offset(textShift * 0.8, 0),
                          child: SlideTransition(
                            position: _descSlide,
                            child: FadeTransition(
                              opacity: _descFade,
                              child: Text(
                                widget.page.description,
                                textAlign: TextAlign.center,
                                style: AppText.body.copyWith(
                                  color: palette.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: OnboardingLayout.spacerBottom),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Full-width gradient pill CTA (Divine Glass "Continue / Get Started"
/// treatment: label + trailing arrow).
///
/// Brand-gradient fill, soft brand glow + a faint glass highlight border.
/// Ripple comes from the [InkWell]; the press "squish" is applied by the
/// [PressableScale] that wraps it in the parent.
class _GradientNextButton extends StatelessWidget {
  const _GradientNextButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        // Subtle glass highlight.
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.40),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A large, soft radial colour bloom used for the full-bleed background wash.
class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.12),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// An animated page-indicator dot. The active dot is wider and brand-coloured;
/// width and colour transitions are smoothed by [AnimatedContainer].
class _Dot extends StatelessWidget {
  const _Dot({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: isActive ? 28 : 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primaryGreen : palette.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
