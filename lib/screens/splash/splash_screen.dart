import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/app_settings.dart';
import '../../services/guest_mode.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_style.dart';
import '../auth/login_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../shell/main_shell.dart';

/// Splash — oversized clay shield settles, shine sweeps, then I → N → O.
///
/// After the reveal:
///   • first launch → [OnboardingScreen]
///   • returning + signed-in → shell
///   • returning + signed-out → [LoginScreen]
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _c;
  late final AnimationController _float;
  late final AnimationController _exit;

  late final Animation<double> _shieldFade;
  late final Animation<double> _shieldScale;
  late final Animation<double> _shine;
  late final Animation<double> _exitFade;
  late final Animation<double> _exitScale;

  late final List<Animation<double>> _letterFade;
  late final List<Animation<double>> _letterScale;

  bool _navigated = false;
  bool _exiting = false;

  /// Flat silhouette used as the clay-3D mask (same shape as before).
  static const _shieldMask = 'assets/splash/splash_shield_blank.png';

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..addStatusListener(_onStatusChanged);

    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
    );

    // 1) Oversized shield fades in while scaling down to rest size.
    _shieldFade = _phase(0.00, 0.32, Curves.easeOut);
    _shieldScale = Tween<double>(begin: 1.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.00, 0.42, curve: Curves.easeOutCubic),
      ),
    );

    // 2) Diagonal glass shine once the shield is nearly settled.
    _shine = _phase(0.32, 0.55, Curves.easeInOut);

    // 3) I → N → O after the shine finishes.
    const starts = [0.58, 0.66, 0.74];
    const ends = [0.70, 0.78, 0.86];
    _letterFade = [
      for (var i = 0; i < 3; i++) _phase(starts[i], ends[i], Curves.easeOut),
    ];
    _letterScale = [
      for (var i = 0; i < 3; i++)
        Tween<double>(begin: 0.7, end: 1.0).animate(
          CurvedAnimation(
            parent: _c,
            curve: Interval(starts[i], ends[i], curve: Curves.easeOutCubic),
          ),
        ),
    ];

    _c.forward();
  }

  Animation<double> _phase(double begin, double end, Curve curve) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(begin, end, curve: curve),
      ),
    );
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      Future<void>.delayed(const Duration(milliseconds: 1200), _beginExit);
    }
  }

  Future<void> _beginExit() async {
    if (_exiting || _navigated || !mounted) return;
    _exiting = true;
    await _exit.forward();
    if (!mounted) return;
    await _continue();
  }

  Future<void> _continue() async {
    if (_navigated || !mounted) return;
    _navigated = true;

    if (!AppSettings.instance.onboardingSeen.value) {
      _replace(const OnboardingScreen());
      return;
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        var profile = await UserRepository.instance.getProfileByAuthId(
          session.user.id,
        );
        profile ??= await UserRepository.instance.getCachedProfile(
          session.user.id,
        );
        if (profile != null && mounted) {
          _goToShellFade(profile);
          return;
        }
      }
    } catch (_) {
      // Fall through to Login — never block cold start on network.
    }

    if (!mounted) return;
    _replace(const LoginScreen());
  }

  Route<void> _fadeRoute(Widget page) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 900),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          ),
          child: child,
        );
      },
    );
  }

  void _replace(Widget page) {
    Navigator.of(context).pushReplacement(_fadeRoute(page));
  }

  /// Soft fade into shell (avoids [goToShell]'s abrupt MaterialPageRoute slide).
  void _goToShellFade(UserProfile profile) {
    GuestMode.active = false;
    Navigator.of(context).pushAndRemoveUntil(
      _fadeRoute(
        MainShell(
          profile: profile,
          themeMode: ThemeController.mode.value,
          onToggleTheme: () => ThemeController.toggle(context),
        ),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    _float.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final palette = AppPalette.of(context);
    final brand = AppColors.primaryGreen;
    final shieldSize =
        (size.shortestSide * 0.68).clamp(240.0, 340.0).toDouble();

    final flat = InoStyle.usesFlatBackdrop(context);
    final gradient = palette.isDark
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.bg,
              Color.lerp(palette.bg, brand, 0.12)!,
              palette.bgElevated,
            ],
          )
        : flat
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.tealFoam,
                  AppColors.tealMist,
                  Color.lerp(AppColors.tealMist, brand, 0.08)!,
                ],
              );

    return Scaffold(
      backgroundColor: palette.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: flat && !palette.isDark ? palette.bg : null,
          gradient: gradient,
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_c, _float, _exit]),
            builder: (context, _) {
              final bob = math.sin(_float.value * math.pi) * 3;
              return Center(
                child: FadeTransition(
                  opacity: _exitFade,
                  child: ScaleTransition(
                    scale: _exitScale,
                    child: Transform.translate(
                      offset: Offset(0, bob),
                      child: FadeTransition(
                        opacity: _shieldFade,
                        child: ScaleTransition(
                          scale: _shieldScale,
                          child: SizedBox(
                            width: shieldSize,
                            height: shieldSize,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Soft floor shadow (clay icon style).
                                Transform.translate(
                                  offset: Offset(0, shieldSize * 0.08),
                                  child: Container(
                                    width: shieldSize * 0.52,
                                    height: shieldSize * 0.12,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.all(
                                        Radius.elliptical(
                                          shieldSize * 0.52,
                                          shieldSize * 0.12,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.22),
                                          blurRadius: 26,
                                          spreadRadius: 1,
                                        ),
                                        BoxShadow(
                                          color: brand.withValues(alpha: 0.20),
                                          blurRadius: 32,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Clay soft-3D shield (same silhouette as before).
                                _ClayShield3d(
                                  maskAsset: _shieldMask,
                                  size: shieldSize,
                                  accent: brand,
                                ),

                                // One-shot diagonal shine clipped to the shield.
                                _ShieldShineSweep(
                                  maskAsset: _shieldMask,
                                  size: shieldSize,
                                  progress: _shine.value,
                                ),

                                // INO reveal on the shield face.
                                Transform.translate(
                                  offset: Offset(0, -shieldSize * 0.02),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < 3; i++) ...[
                                        if (i > 0)
                                          SizedBox(width: shieldSize * 0.014),
                                        FadeTransition(
                                          opacity: _letterFade[i],
                                          child: ScaleTransition(
                                            scale: _letterScale[i],
                                            child: Text(
                                              const ['I', 'N', 'O'][i],
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: shieldSize * 0.23,
                                                fontWeight: FontWeight.w800,
                                                height: 1.0,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.28),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One-shot diagonal glass shine, masked to the shield silhouette.
class _ShieldShineSweep extends StatelessWidget {
  const _ShieldShineSweep({
    required this.maskAsset,
    required this.size,
    required this.progress,
  });

  final String maskAsset;
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) {
      return const SizedBox.shrink();
    }

    // Soft envelope so the streak fades in/out at the ends of the sweep.
    final envelope = math.sin(progress * math.pi).clamp(0.0, 1.0);

    return IgnorePointer(
      child: Opacity(
        opacity: envelope,
        child: SizedBox(
          width: size,
          height: size,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              // Progress 0→1 slides the band from above-left to below-right.
              final slide = progress * 2.4 - 0.7;
              return LinearGradient(
                begin: const Alignment(-1.0, -1.0),
                end: const Alignment(1.0, 1.0),
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
                transform: _DiagonalSlide(slide),
              ).createShader(bounds);
            },
            child: Image.asset(
              maskAsset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => Icon(
                Icons.shield_rounded,
                size: size * 0.88,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides a diagonal gradient along the TL→BR axis.
class _DiagonalSlide extends GradientTransform {
  const _DiagonalSlide(this.slide);
  final double slide;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * slide;
    final dy = bounds.height * slide;
    return Matrix4.translationValues(dx, dy, 0);
  }
}

/// Soft-3D clay shield — same blank silhouette, layered like Home clay icons
/// (thick lit rim, deeper face, specular kiss). Letters sit on the face.
class _ClayShield3d extends StatelessWidget {
  const _ClayShield3d({
    required this.maskAsset,
    required this.size,
    required this.accent,
  });

  final String maskAsset;
  final double size;
  final Color accent;

  Color _tone(Color c, {double light = 0, double sat = 0}) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + light).clamp(0.05, 0.92))
        .withSaturation((hsl.saturation + sat).clamp(0.0, 1.0))
        .toColor();
  }

  Widget _masked({
    required double scale,
    required Shader Function(Rect) shader,
    double opacity = 1,
  }) {
    final side = size * scale;
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => shader(
              Rect.fromLTWH(0, 0, bounds.width, bounds.height),
            ),
            child: Image.asset(
              maskAsset,
              width: side,
              height: side,
              fit: BoxFit.contain,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => Icon(
                Icons.shield_rounded,
                size: side * 0.88,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rimHi = _tone(accent, light: 0.28, sat: 0.05);
    final rimMid = _tone(accent, light: 0.10);
    final rimLo = _tone(accent, light: -0.12, sat: 0.08);
    final faceHi = _tone(accent, light: 0.14);
    final faceMid = accent;
    final faceLo = _tone(accent, light: -0.10, sat: 0.06);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer rim (slightly larger) — clay bevel edge.
          _masked(
            scale: 1.0,
            shader: (rect) => LinearGradient(
              begin: const Alignment(-0.9, -1.0),
              end: const Alignment(0.85, 1.0),
              colors: [rimHi, rimMid, rimLo],
              stops: const [0.0, 0.42, 1.0],
            ).createShader(rect),
          ),
          // Recessed face (inset) — deeper body like clay icons.
          _masked(
            scale: 0.86,
            shader: (rect) => LinearGradient(
              begin: const Alignment(-0.6, -0.95),
              end: const Alignment(0.7, 0.95),
              colors: [faceHi, faceMid, faceLo],
              stops: const [0.0, 0.48, 1.0],
            ).createShader(rect),
          ),
          // Soft inner bowl shade on face.
          _masked(
            scale: 0.86,
            opacity: 0.55,
            shader: (rect) => RadialGradient(
              center: const Alignment(0.05, 0.15),
              radius: 0.95,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.18),
              ],
              stops: const [0.45, 1.0],
            ).createShader(rect),
          ),
          // Specular kiss — top-left gloss like clay PNGs.
          _masked(
            scale: 0.86,
            opacity: 0.9,
            shader: (rect) => RadialGradient(
              center: const Alignment(-0.45, -0.62),
              radius: 0.72,
              colors: [
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.35, 0.75],
            ).createShader(rect),
          ),
          // Thin lit rim highlight along the outer edge.
          IgnorePointer(
            child: CustomPaint(
              size: Size(size, size),
              painter: _ClayRimSheenPainter(accent: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClayRimSheenPainter extends CustomPainter {
  _ClayRimSheenPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width * 0.15, size.height * 0.12),
        Offset(size.width * 0.55, size.height * 0.45),
        [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
      )
      ..blendMode = BlendMode.softLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035;
    final path = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5, size.height * 0.48),
          width: size.width * 0.72,
          height: size.height * 0.78,
        ),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ClayRimSheenPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
