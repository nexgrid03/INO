import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../floating_particles.dart';

/// Shared premium backdrop + layout for every authentication screen.
///
/// One place owns the auth "chrome" so Splash → Onboarding → Login → Signup →
/// OTP → Forgot → Biometric all share the exact same ambient teal-cyan
/// backdrop, the subtle drifting particles, safe-area handling and an optional
/// back button. Screens only supply their [child] content — keeping each
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

class _AuthScaffoldState extends State<AuthScaffold>
    with SingleTickerProviderStateMixin {
  /// Slow, perpetual loop for the floating background particles — matches the
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

    Widget body = widget.scrollable
        ? SingleChildScrollView(
            padding: widget.padding,
            physics: const BouncingScrollPhysics(),
            child: widget.child,
          )
        : Padding(padding: widget.padding, child: widget.child);

    return Scaffold(
      // Let the backdrop sit behind the keyboard rather than resizing abruptly.
      resizeToAvoidBottomInset: true,
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Ambient corner glows — a cyan wash bleeding in from the top-left
          // and a teal wash from the bottom-right, both fading into the
          // scaffold background. Works over the light AND dark palettes.
          const Positioned(
            top: -170,
            left: -130,
            child: _AmbientBlob(color: AppColors.lightBlue, size: 400),
          ),
          const Positioned(
            bottom: -190,
            right: -150,
            child: _AmbientBlob(color: AppColors.primaryGreen, size: 460),
          ),
          Positioned.fill(child: FloatingParticles(animation: _particles)),

          SafeArea(
            child: Column(
              children: [
                if (showTopRow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        if (widget.showBack)
                          _CircleIconButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: widget.onBack ??
                                () => Navigator.of(context).maybePop(),
                          )
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

/// A soft radial brand glow anchored just off-screen — the ambient "blob"
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

/// A soft, glassy circular icon button used for the back affordance.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface.withValues(alpha: 0.75),
      shape: CircleBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: palette.textPrimary, size: 22),
        ),
      ),
    );
  }
}
