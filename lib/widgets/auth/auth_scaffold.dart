import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_back_button.dart';
import '../floating_particles.dart';

/// Shared premium backdrop + layout for every authentication screen.
///
/// One place owns the auth "chrome" so Splash → Onboarding → Login → Signup →
/// OTP → Forgot → Biometric all share the exact same ambient teal-cyan
/// backdrop, the subtle drifting particles, safe-area handling and an optional
/// back button. Screens only supply their [child] content - keeping each
/// screen file focused on its single purpose.
class AuthScaffold extends StatefulWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showBack = false,
    this.onBack,
    this.scrollable = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.trailing,
  });

  /// The screen's body (already laid out; this widget adds background + safe
  /// area + optional back row and scrolling).
  final Widget child;

  /// Shows a top-left back button (for pushed screens like Signup / OTP).
  final bool showBack;
  final VoidCallback? onBack;

  /// Whether the content scrolls (keeps forms usable when the keyboard opens).
  final bool scrollable;

  /// Horizontal/vertical insets applied to [child].
  final EdgeInsets padding;

  /// Optional widget shown at the top-right of the back row (e.g. a Skip link).
  final Widget? trailing;

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

/// Launcher-aware auth headline (larger / heavier under Divine Glass).
class AuthPageTitle extends StatelessWidget {
  const AuthPageTitle(this.text, {super.key, this.color = AppColors.textDark});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final launcher = InoStyle.usesDivineGlass(context);
    final width = MediaQuery.sizeOf(context).width;
    final baseSize = launcher ? 30.0 : 26.0;
    final fontSize = width < 360 ? baseSize - 2 : baseSize;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: launcher ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: launcher ? -0.5 : 0,
        height: 1.15,
        color: color,
      ),
    );
  }
}

class _AuthScaffoldState extends State<AuthScaffold>
    with SingleTickerProviderStateMixin {
  /// Slow, perpetual loop for the floating background particles - matches the
  /// splash / onboarding cadence so the transition between them feels seamless.
  late final AnimationController _particles = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _particles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final showTopRow = widget.showBack || widget.trailing != null;

    Widget content = widget.child;
    // Solid surface card under Divine Glass themes — avoids translucent
    // LiquidGlass nesting that made field labels clash with borders.
    if (InoStyle.usesDivineGlass(context)) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border),
          boxShadow: palette.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: content,
        ),
      );
    }

    Widget body = widget.scrollable
        ? SingleChildScrollView(
            padding: widget.padding,
            physics: const BouncingScrollPhysics(),
            child: content,
          )
        : Padding(padding: widget.padding, child: content);

    return Scaffold(
      // Let the backdrop sit behind the keyboard rather than resizing abruptly.
      resizeToAvoidBottomInset: true,
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // App-wide hero-sky wash (matches InoBackground): the full brand
          // skyBlue at the top melting to the pale base past mid-screen
          // (light mode only; dark keeps its deep palette bg).
          if (!palette.isDark)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.skyBlue,
                        AppColors.tealPale,
                        AppColors.tealMist,
                        AppColors.tealFoam,
                      ],
                      stops: const [0.0, 0.28, 0.62, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          // Ambient corner glows - a cyan wash bleeding in from the top-left
          // and a teal wash from the bottom-right, both fading into the
          // scaffold background. Works over the light AND dark palettes.
           Positioned(
            top: -170,
            left: -130,
            child: _AmbientBlob(color: AppColors.lightBlue, size: 400),
          ),
           Positioned(
            bottom: -190,
            right: -150,
            child: _AmbientBlob(color: AppColors.primaryGreen, size: 460),
          ),
          Positioned.fill(child: FloatingParticles(animation: _particles)),

          SafeArea(
            minimum: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                if (showTopRow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        if (widget.showBack)
                          // The canonical glass back circle; renders nothing
                          // when the route can't pop, so it is safe even when
                          // this screen is a stack-cleared root.
                          InoBackButton(onTap: widget.onBack)
                        else
                          const SizedBox(width: 44),
                        const Spacer(),
                        if (widget.trailing != null) widget.trailing!,
                      ],
                    ),
                  ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft radial brand glow anchored just off-screen - the ambient "blob"
/// backdrop element that gives the auth flow its premium depth.
class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: palette.isDark ? 0.14 : 0.12),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
