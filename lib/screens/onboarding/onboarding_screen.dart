import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/floating_particles.dart';
import '../../widgets/pressable_scale.dart';
import '../auth/login_screen.dart';
import 'floating_satellites.dart';
import 'onboarding_icon.dart';

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
/// navigate to the [LoginScreen].
///
/// Visual language follows the Stitch onboarding set: a soft ambient gradient
/// wash behind everything, a rounded hero panel holding the animated
/// illustration, an uppercase step pill, a two-tone headline (first line in
/// the ambient text colour, second line in brand teal), left-aligned copy,
/// left-aligned progress dots and a full-bleed gradient pill CTA.
///
/// Animation ownership (important — this is what avoids the "blank then load"
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
          'Store Aadhaar, PAN, Passport, Licence, certificates and more — '
          'safely encrypted and always within reach.',
    ),
    _OnboardingPage(
      icon: Icons.insights_rounded,
      title: 'Track Wealth\n& Health',
      description:
          'Keep property, insurance, investments and medical records '
          'organised, with your net worth at a glance.',
    ),
    _OnboardingPage(
      icon: Icons.qr_code_2_rounded,
      title: 'Share Instantly\n& Safely',
      description:
          'Share documents in seconds with secure QR codes, protected by '
          'biometric authentication.',
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void initState() {
    super.initState();

    _particles = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _arrowSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic),
    );
    _arrowFade = CurvedAnimation(parent: _intro, curve: Curves.easeIn);
    _arrowScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
    );
    _intro.forward();

    _dotPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _dotPopScale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _dotPop, curve: Curves.easeInOut));
  }

  void _onPageChanged(int index) {
    HapticFeedback.lightImpact(); // light vibration on page change
    setState(() => _currentPage = index);
    _dotPop.forward(from: 0); // pop the newly-active dot
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _onNextPressed() {
    HapticFeedback.lightImpact(); // subtle feedback on Next / Get Started
    if (_isLastPage) {
      _goToLogin();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
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
    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Full-bleed soft gradient wash (Stitch "gradient mesh"): one warm
          // teal bloom top-right, one cyan bloom bottom-left.
          const Positioned(
            top: -120,
            right: -90,
            child: _AmbientBlob(color: AppColors.primaryGreen, size: 340),
          ),
          const Positioned(
            bottom: -140,
            left: -110,
            child: _AmbientBlob(color: AppColors.lightBlue, size: 320),
          ),

          // Subtle floating shapes behind everything.
          Positioned.fill(child: FloatingParticles(animation: _particles)),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Skip button (hidden on the last page).
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 12),
                    child: AnimatedOpacity(
                      opacity: _isLastPage ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: TextButton(
                        onPressed: _isLastPage
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                _goToLogin();
                              },
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Slides — each owns its own entrance animation.
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

                // Bottom bar (Stitch arrangement): left-aligned progress dots
                // above a full-width gradient pill CTA.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, 12, AppSpacing.screen, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Page indicator dots (active dot pops on change).
                      Row(
                        children: List.generate(_pages.length, (index) {
                          final dot = _Dot(isActive: index == _currentPage);
                          return index == _currentPage
                              ? ScaleTransition(scale: _dotPopScale, child: dot)
                              : dot;
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Gradient CTA — one-time fade + slide-up + scale, with
                      // a press "squish" (ripple comes from its InkWell).
                      SlideTransition(
                        position: _arrowSlide,
                        child: FadeTransition(
                          opacity: _arrowFade,
                          child: ScaleTransition(
                            scale: _arrowScale,
                            child: PressableScale(
                              child: _GradientNextButton(
                                onTap: _onNextPressed,
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
/// supporting copy — all left-aligned.
///
/// Each slide owns a short entrance controller that plays in [initState] — so
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

  // Staggered phases over a 1400ms controller. The order is deliberate so the
  // eye lands on the illustration first, then the content:
  //   circle  0.03–0.20   (appears first, completes early)
  //   inner   0.10–0.34   (folder pop / chart draw / QR scan + glow)
  //   chips   0.40–0.80   (satellites pop in one-by-one — see FloatingSatellites)
  //   title   0.81–0.90   (only after the chips have appeared)
  //   desc    0.91–1.00   (last)
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
      duration: const Duration(milliseconds: 1400),
    );

    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _contentSlide = _slide(0.0, 0.30, 0.05);
    // Circle appears first and finishes early (before the chips start).
    _iconScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.03, 0.20, curve: Curves.easeOutBack),
      ),
    );
    _iconFade = _fade(0.0, 0.14);
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween:
            Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.10, 0.34)),
    );
    _reveal = _fade(0.10, 0.34, Curves.easeInOutCubic);
    _folderPop = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.10, 0.32, curve: Curves.elasticOut),
      ),
    );
    // Title only after all the chips (which finish ~0.80).
    _titleSlide = _slide(0.81, 0.90, 0.5);
    _titleFade = _fade(0.81, 0.90);
    // Description last.
    _descSlide = _slide(0.91, 1.0, 0.5);
    _descFade = _fade(0.91, 1.0);

    _c.forward();
  }

  Animation<double> _fade(double begin, double end,
      [Curve curve = Curves.easeIn]) {
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

  /// The Stitch-style hero panel: a large rounded surface with a barely-there
  /// teal→cyan wash, hairline border and the standard floating-card shadow.
  /// The animated circle + floating satellite chips sit centred inside it —
  /// the chips echo the Stitch mock's floating glass cards.
  Widget _heroPanel(AppPalette palette) {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.large),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              AppColors.primaryGreen.withValues(alpha: 0.10),
              palette.surface,
            ),
            Color.alphaBlend(
              AppColors.lightBlue.withValues(alpha: 0.07),
              palette.surface,
            ),
          ],
        ),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Center(
        // The 160px SizedBox preserves the illustration's internal layout; the
        // satellites overflow it via Clip.none inside the panel.
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Contextual chips floating around the circle.
              FloatingSatellites(
                index: widget.index,
                pop: _c,
                float: _float,
              ),
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
        ),
      ),
    );
  }

  /// Small uppercase step pill above the headline — purely decorative, copied
  /// from the Stitch onboarding language ("STEP 3 OF 4").
  Widget _stepPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        'STEP ${widget.index + 1} OF ${widget.total}',
        style: AppText.label.copyWith(
          fontSize: 11,
          letterSpacing: 1.4,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }

  /// Two-tone headline (Stitch treatment): first line in the primary text
  /// colour, the rest in brand teal. The full original string is rendered.
  Widget _titleText(AppPalette palette) {
    final title = widget.page.title;
    final int nl = title.indexOf('\n');
    final style = AppText.display.copyWith(
      fontSize: 28,
      height: 1.18,
      color: palette.textPrimary,
    );
    if (nl == -1) return Text(title, style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: title.substring(0, nl)),
          TextSpan(
            text: title.substring(nl),
            style: const TextStyle(color: AppColors.primaryGreen),
          ),
        ],
      ),
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
          delta = (widget.controller.page ?? widget.index.toDouble()) -
              widget.index;
        }
        // Hero moves more than text (parallax depth); content scales down a
        // touch as the page slides away from centre.
        final double iconShift = -delta * 36;
        final double textShift = -delta * 14;
        final double swipeScale = (1 - delta.abs() * 0.08).clamp(0.0, 1.0);

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: SlideTransition(
            position: _contentSlide,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero panel (with parallax + swipe scale on top). Flexible so
                // it breathes on tall screens and shrinks on short ones.
                Expanded(
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(iconShift, 0),
                      child: Transform.scale(
                        scale: swipeScale,
                        child: _heroPanel(palette),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Step pill + title.
                Transform.translate(
                  offset: Offset(textShift, 0),
                  child: SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleFade,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stepPill(),
                          const SizedBox(height: 14),
                          _titleText(palette),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Description.
                Transform.translate(
                  offset: Offset(textShift * 0.8, 0),
                  child: SlideTransition(
                    position: _descSlide,
                    child: FadeTransition(
                      opacity: _descFade,
                      child: Text(
                        widget.page.description,
                        style: TextStyle(
                          fontSize: 15,
                          color: palette.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full-width gradient pill CTA (Stitch "Next" treatment, icon-only).
///
/// Brand-gradient fill, white arrow, soft brand glow + a faint glass highlight
/// border. Ripple comes from the [InkWell]; the press "squish" is applied by
/// the [PressableScale] that wraps it in the parent.
class _GradientNextButton extends StatelessWidget {
  const _GradientNextButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Container(
      height: AppSizes.button,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: radius,
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
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: const Center(
            child: Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 26,
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
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
