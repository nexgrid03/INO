import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/guest_mode.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/common/ino_background.dart';
import '../auth/auth_flow.dart';
import '../shell/main_shell.dart';

/// The "your documents are secured" moment between onboarding and the app.
///
/// A padlock assembles itself inside a glowing brand ring - the ring draws
/// around, the shackle drops shut with a satisfying click (haptic), and four
/// little document chips settle into orbit around it, each in its own accent
/// from the app family. Then the title, reassurance line and **Get Started**
/// rise in.
///
/// Get Started routes by session: an already-signed-in user goes straight to
/// their shell; everyone else enters guest explore mode (see [GuestMode]) and
/// lands on Home, where every real action asks them to sign in.
///
/// One 3.2s [AnimationController] drives the whole build-up via [Interval]s; a
/// second slow repeating controller keeps the orbit chips gently breathing
/// afterwards, so the screen stays alive while the user reads.
class SecuredIntroScreen extends StatefulWidget {
  const SecuredIntroScreen({super.key});

  @override
  State<SecuredIntroScreen> createState() => _SecuredIntroScreenState();
}

class _SecuredIntroScreenState extends State<SecuredIntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  /// Perpetual gentle float for the orbit chips once they've landed.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  bool _clicked = false; // haptic fired once when the shackle shuts
  bool _busy = false; // Get Started routing in flight

  @override
  void initState() {
    super.initState();
    _c.addListener(_maybeClick);
    _c.forward();
  }

  void _maybeClick() {
    if (!_clicked && _c.value >= 0.52) {
      _clicked = true;
      HapticFeedback.mediumImpact(); // the shackle "click"
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _float.dispose();
    super.dispose();
  }

  // ---- Routing ---------------------------------------------------------------

  Future<void> _getStarted() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      // A returning signed-in user (persisted Supabase session) skips guest
      // mode entirely and gets their real shell.
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        UserProfile? profile;
        try {
          profile = await UserRepository.instance.getProfileByAuthId(
            session.user.id,
          );
        } catch (_) {
          // Network down. The session is still valid, so fall back to the
          // profile this device last fetched - a signed-in user must reach
          // their shell offline (that's what Offline documents exist for),
          // never the sign-in screen.
          profile =
              await UserRepository.instance.getCachedProfile(session.user.id);
        }
        if (profile != null && mounted) {
          GuestMode.active = false;
          goToShell(context, profile);
          return;
        }
      }
    } catch (_) {
      // Fall through to guest - exploring must never be blocked by a network
      // hiccup.
    }
    if (!mounted) return;
    GuestMode.active = true;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => MainShell(
          profile: GuestMode.guestProfile(),
          themeMode: ThemeController.mode.value,
          onToggleTheme: () =>
              ThemeController.toggle(InoApp.navigatorKey.currentContext!),
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (route) => false,
    );
  }

  // ---- Build -----------------------------------------------------------------

  /// Eased sub-progress of the master timeline between [a] and [b].
  double _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) {
    final raw = ((_c.value - a) / (b - a)).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        child: Stack(
        children: [
          // Soft ambient colour washes - teal top-right, cyan bottom-left, a
          // whisper of purple behind the lock so the scene isn't monochrome.
           Positioned(
            top: -120,
            right: -100,
            child: _AmbientBlob(color: AppColors.primaryGreen, size: 340),
          ),
           Positioned(
            bottom: -110,
            left: -90,
            child: _AmbientBlob(color: AppColors.lightBlue, size: 320),
          ),
          const Positioned(
            top: 190,
            left: -60,
            child: _AmbientBlob(color: Color(0xFF9B6DE0), size: 220),
          ),

          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([_c, _float]),
              builder: (context, _) {
                final floatT = math.sin(
                  _float.value * math.pi,
                ); // 0→1→0 gentle wave
                return Column(
                  children: [
                    const Spacer(flex: 5),
                    // ---- The lock scene ---------------------------------
                    SizedBox(
                      width: 300,
                      height: 300,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Drawing ring + settled gradient ring.
                          CustomPaint(
                            size: const Size(210, 210),
                            painter: _RingPainter(
                              sweep: _seg(0.06, 0.42, Curves.easeInOutCubic),
                              settle: _seg(0.42, 0.62),
                            ),
                          ),
                          // Glass disc the padlock sits on.
                          Transform.scale(
                            scale:
                                0.7 + 0.3 * _seg(0.0, 0.30, Curves.easeOutBack),
                            child: Opacity(
                              opacity: _seg(0.0, 0.18),
                              child: Container(
                                width: 168,
                                height: 168,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: palette.isDark
                                        ? [
                                            const Color(0xFF173347),
                                            const Color(0xFF13293A),
                                          ]
                                        : [
                                            Colors.white,
                                            AppColors.tealMist,
                                          ],
                                  ),
                                  border: Border.all(
                                    color: AppColors.primaryGreen.withValues(
                                      alpha: 0.35,
                                    ),
                                    width: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // The padlock itself (shackle drops shut).
                          Opacity(
                            opacity: _seg(0.16, 0.30),
                            child: CustomPaint(
                              size: const Size(92, 100),
                              painter: _PadlockPainter(
                                close: _seg(0.34, 0.52, Curves.bounceOut),
                              ),
                            ),
                          ),
                          // Orbiting document chips, one per accent.
                          for (var i = 0; i < _chips.length; i++)
                            _OrbitChip(
                              spec: _chips[i],
                              appear: _seg(
                                0.50 + i * 0.05,
                                0.66 + i * 0.05,
                                Curves.easeOutBack,
                              ),
                              float: floatT,
                              phase: i,
                            ),
                          // A couple of sparkles as the scene completes.
                          Positioned(
                            top: 46,
                            right: 58,
                            child: _Sparkle(
                              t: _seg(0.55, 0.85),
                              size: 20,
                              color: AppColors.secondaryGreen,
                            ),
                          ),
                          Positioned(
                            bottom: 60,
                            left: 52,
                            child: _Sparkle(
                              t: _seg(0.66, 0.96),
                              size: 15,
                              color: const Color(0xFFF2B33D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    // ---- Copy -------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: Column(
                        children: [
                          Opacity(
                            opacity: _seg(0.60, 0.78),
                            child: Transform.translate(
                              offset: Offset(0, 16 * (1 - _seg(0.60, 0.78))),
                              child: ShaderMask(
                                shaderCallback: (b) =>
                                    AppColors.brandGradient.createShader(b),
                                blendMode: BlendMode.srcIn,
                                child: Text(
                                  'Your Documents Are Secured',
                                  textAlign: TextAlign.center,
                                  style: AppText.display.copyWith(
                                    color: Colors.white,
                                    fontSize: 27,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: _seg(0.70, 0.86),
                            child: Transform.translate(
                              offset: Offset(0, 14 * (1 - _seg(0.70, 0.86))),
                              child: Text(
                                'Everything you keep in INO stays encrypted '
                                'and private - only you can unlock it.',
                                textAlign: TextAlign.center,
                                style: AppText.body.copyWith(
                                  color: palette.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    // ---- Get Started ------------------------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
                      child: Opacity(
                        opacity: _seg(0.80, 0.97),
                        child: Transform.translate(
                          offset: Offset(0, 22 * (1 - _seg(0.80, 0.97))),
                          child: _GetStartedButton(
                            busy: _busy,
                            onTap: _getStarted,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene pieces
// ---------------------------------------------------------------------------

class _ChipSpec {
  const _ChipSpec(this.icon, this.color, this.dx, this.dy);
  final IconData icon;
  final Color color;
  final double dx, dy; // resting offset from the scene centre
}

/// Four "document" chips, each in its own accent so the scene carries the
/// whole palette family rather than a single teal.
const _chips = [
  _ChipSpec(Icons.description_rounded, Color(0xFF4383EA), -108, -66),
  _ChipSpec(Icons.badge_rounded, Color(0xFF9B6DE0), 108, -58),
  _ChipSpec(Icons.home_work_rounded, Color(0xFFF2B33D), -100, 72),
  _ChipSpec(Icons.favorite_rounded, Color(0xFFF5704A), 104, 78),
];

class _OrbitChip extends StatelessWidget {
  const _OrbitChip({
    required this.spec,
    required this.appear,
    required this.float,
    required this.phase,
  });

  final _ChipSpec spec;
  final double appear; // 0→1 entrance
  final double float; // 0→1→0 shared bob wave
  final int phase;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (appear == 0) return const SizedBox.shrink();
    // Each chip bobs slightly out of step with its neighbours.
    final bob = math.sin(float * math.pi + phase * 1.6) * 5;
    return Transform.translate(
      // Flies in from further out along its own axis, then floats.
      offset: Offset(spec.dx * (0.55 + 0.45 * appear), spec.dy * appear + bob),
      child: Opacity(
        opacity: appear.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.7 + 0.3 * appear,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                spec.color.withValues(alpha: palette.isDark ? 0.22 : 0.10),
                palette.surface,
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: spec.color.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: spec.color.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(spec.icon, color: spec.color, size: 22),
          ),
        ),
      ),
    );
  }
}

/// The brand ring: while [sweep] runs it draws itself around the disc as a
/// gradient arc with a bright head; [settle] then fades in the completed ring.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.sweep, required this.settle});

  final double sweep;
  final double settle;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep <= 0) return;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 4;
    const start = -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: const GradientRotation(start),
        colors:  [
          AppColors.primaryGreen,
          AppColors.secondaryGreen,
          AppColors.skyBlue,
          AppColors.primaryGreen,
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(rect);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      math.pi * 2 * sweep,
      false,
      paint,
    );

    // Bright head on the drawing arc - reads as the "pen" tracing the ring.
    if (sweep < 1) {
      final a = start + math.pi * 2 * sweep;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * radius,
        6,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * radius,
        10,
        Paint()
          ..color = AppColors.secondaryGreen.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Once drawn, a soft settled glow hugs the ring.
    if (settle > 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = AppColors.secondaryGreen.withValues(alpha: 0.22 * settle)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.sweep != sweep || old.settle != settle;
}

/// A padlock drawn in canvas: brand-gradient body with a keyhole, and a
/// shackle that starts lifted open and drops shut as [close] runs 0→1
/// (pair with a bounce curve for the "click").
class _PadlockPainter extends CustomPainter {
  _PadlockPainter({required this.close});

  final double close;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ---- Body ----------------------------------------------------------
    final bodyTop = h * 0.42;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.10, bodyTop, w * 0.90, h * 0.96),
      Radius.circular(w * 0.16),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      Paint()
        ..color = AppColors.primaryGreen.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader =  LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.secondaryGreen, AppColors.primaryGreen],
        ).createShader(body.outerRect),
    );
    // Top-left sheen on the body.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.6, -0.7),
          radius: 1.1,
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(body.outerRect),
    );

    // ---- Shackle -------------------------------------------------------
    // Starts lifted (open) and slides down into the body as [close] runs.
    final lift = (1 - close) * h * 0.16;
    final shackle = Path()
      ..moveTo(w * 0.28, bodyTop - lift)
      ..lineTo(w * 0.28, h * 0.26 - lift)
      ..arcTo(
        Rect.fromLTRB(w * 0.28, h * 0.06 - lift, w * 0.72, h * 0.46 - lift),
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(w * 0.72, bodyTop - lift);
    canvas.drawPath(
      shackle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.11
        ..strokeCap = StrokeCap.round
        ..shader =  LinearGradient(
          colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.5)),
    );

    // ---- Keyhole -------------------------------------------------------
    final kc = Offset(w / 2, h * 0.64);
    canvas.drawCircle(kc, w * 0.085, Paint()..color = Colors.white);
    final stem = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.76),
        width: w * 0.075,
        height: h * 0.14,
      ),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(stem, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PadlockPainter old) => old.close != close;
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.t, required this.size, required this.color});

  final double t; // 0→1 lifecycle
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (t == 0) return const SizedBox.shrink();
    final pulse = math.sin(t * math.pi); // in and out
    return Opacity(
      opacity: pulse,
      child: Transform.rotate(
        angle: t * 0.8,
        child: Icon(Icons.auto_awesome_rounded, size: size, color: color),
      ),
    );
  }
}

/// Full-width brand-gradient CTA with a soft glow and a busy spinner state.
class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        // Divine Glass: primary CTAs are full pills.
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
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

/// A large, soft radial colour bloom for the background wash.
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
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
