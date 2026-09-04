import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/app_preload.dart';
import '../../services/app_settings.dart';
import '../../services/connectivity_service.dart';
import '../../services/guest_mode.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_style.dart';
import '../auth/login_screen.dart';
import '../auth/mfa_challenge_screen.dart';
import '../documents/offline_documents_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../shell/main_shell.dart';
import '../../services/two_factor_service.dart';
import '../../services/vault_guard.dart';

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
  late final List<Animation<Offset>> _letterSlide;

  bool _navigated = false;
  bool _exiting = false;

  /// Flat silhouette used as the clay-3D mask (same shape as before).
  static const _shieldMask = 'assets/splash/splash_shield_blank.png';

  @override
  void initState() {
    super.initState();

    // Premium brand beat: settle → shine → INO cascade → brief hold → exit.
    // Calm pacing (~1.5s) so the mark reads clearly without feeling slow.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener(_onStatusChanged);

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat(reverse: true);

    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
    );

    // 1) Shield settles in.
    _shieldFade = _phase(0.00, 0.30, Curves.easeOut);
    _shieldScale = Tween<double>(begin: 1.42, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.00, 0.40, curve: Curves.easeOutCubic),
      ),
    );

    // 2) Diagonal glass shine once the shield is nearly settled.
    _shine = _phase(0.30, 0.52, Curves.easeInOutCubic);

    // 3) I → N → O cascade with a soft rise.
    const starts = [0.50, 0.58, 0.66];
    const ends = [0.68, 0.76, 0.84];
    _letterFade = [
      for (var i = 0; i < 3; i++) _phase(starts[i], ends[i], Curves.easeOut),
    ];
    _letterScale = [
      for (var i = 0; i < 3; i++)
        Tween<double>(begin: 0.72, end: 1.0).animate(
          CurvedAnimation(
            parent: _c,
            curve: Interval(starts[i], ends[i], curve: Curves.easeOutCubic),
          ),
        ),
    ];
    _letterSlide = [
      for (var i = 0; i < 3; i++)
        Tween<Offset>(
          begin: const Offset(0, 0.22),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _c,
            curve: Interval(starts[i], ends[i], curve: Curves.easeOutCubic),
          ),
        ),
    ];

    _c.forward();

    // Is there internet? Started here, in parallel with everything else, so
    // that by the time [_continue] needs the answer it is already in hand.
    // Asking at the end instead would stack a DNS timeout on top of the
    // warm-up's own timeouts - the offline launch this decides would be the
    // slowest launch in the app.
    _online = ConnectivityService.instance
        .checkOnline(timeout: const Duration(milliseconds: 2000))
        .catchError((Object _) => false);

    // Load the user's whole working set behind the animation. Deferred one
    // frame because `createLocalImageConfiguration` (inside [AppPreload]) reads
    // inherited widgets, which are not resolvable from initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startup = _prepare();
    });
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
      _beginExit();
    }
  }

  /// Resolving who is signed in AND warming their data — started the moment
  /// the splash mounts so it runs *underneath* the brand animation instead of
  /// after it. See [_prepare].
  Future<void>? _startup;

  /// The signed-in profile, resolved by [_prepare]. Null means "show Login".
  UserProfile? _profile;

  /// Whether the device has internet, started in `initState` so the answer is
  /// ready by the time [_continue] picks a destination.
  Future<bool>? _online;

  /// Everything the app needs before the first real screen can paint:
  /// the user's profile, and — via [AppPreload] — every store, read model and
  /// piece of Home art the shell reads from.
  ///
  /// Never throws. Anything that fails here degrades to the old behaviour:
  /// the destination screen loads it itself.
  Future<void> _prepare() async {
    // Kicked off first so the asset decodes and the document fetch overlap the
    // profile round-trip below rather than queueing behind it. Swallowing
    // errors here, rather than at the `await` below, matters twice over: the
    // early return for first-run onboarding would otherwise leave an unhandled
    // error on a future nobody awaits, and a warm-up that failed must never be
    // able to throw out of [_beginExit] and strand the app on the splash.
    final warm = AppPreload.instance
        .warmUp(context: context)
        .catchError((Object _) {});

    // First run goes to onboarding, where there is no user data to show — no
    // reason to make the intro wait on a warm-up nobody will see.
    if (!AppSettings.instance.onboardingSeen.value) return;

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        var profile = await UserRepository.instance.getCachedProfile(
          session.user.id,
        );
        if (profile == null) {
          profile = await UserRepository.instance.getProfileByAuthId(
            session.user.id,
          );
        } else {
          // Cached profile is good enough to open with; refresh behind it.
          unawaited(
            UserRepository.instance.getProfileByAuthId(session.user.id),
          );
        }
        _profile = profile;
      }
    } catch (_) {
      // Fall through to Login — never block cold start on network.
    }

    await warm;
  }

  Future<void> _beginExit() async {
    if (_exiting || _navigated || !mounted) return;
    _exiting = true;

    // Hold the finished mark on screen until the user's data is warm, so the
    // shell opens fully populated instead of opening onto skeletons. Capped:
    // a slow network must never turn into a stuck splash, and everything
    // still in flight keeps going and lands in the caches anyway.
    await (_startup ?? Future<void>.value())
        .timeout(AppPreload.splashBudget, onTimeout: () {});
    if (!mounted) return;

    await _exit.forward();
    if (!mounted) return;
    await _continue();
  }

  Future<void> _continue() async {
    if (_navigated || !mounted) return;
    _navigated = true;

    // Onboarding is entirely local and is the only correct first screen on a
    // first run, so it is decided before connectivity.
    if (!AppSettings.instance.onboardingSeen.value) {
      _replace(const OnboardingScreen());
      return;
    }

    final isOnline = await (_online ?? Future<bool>.value(true));
    if (!mounted) return;

    final profile = _profile;
    final hasSession = Supabase.instance.client.auth.currentSession != null;

    // SECURITY FIX: Never open offline library if user is signed out or no valid session exists.
    if (!isOnline) {
      if (!hasSession || profile == null) {
        _replace(const LoginScreen());
        return;
      }
      // Require biometric / device credentials before opening offline documents
      final ok = await VaultGuard.instance.ensureUnlocked(
        context,
        reason: 'Authenticate to access offline documents',
        title: 'Verify Identity',
      );
      if (!mounted) return;
      if (ok) {
        _replace(const OfflineDocumentsScreen(isRootOffline: true));
      } else {
        _replace(const LoginScreen());
      }
      return;
    }

    if (profile != null) {
      // SECURITY FIX: Enforce MFA check on cold start to prevent AAL1 bypass via force-close.
      if (await TwoFactorService.instance.needsMfaChallenge()) {
        _replace(
          MfaChallengeScreen(
            authUserId: profile.authUserId,
            fullName: profile.fullName,
            email: profile.email,
          ),
        );
        return;
      }
      _goToShellFade(profile);
      return;
    }

    _replace(const LoginScreen());
  }

  Route<void> _fadeRoute(Widget page) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
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
              final bob = math.sin(_float.value * math.pi) * 2.2;
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

                                // Premium INO wordmark on the shield face.
                                Transform.translate(
                                  offset: Offset(0, -shieldSize * 0.015),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < 3; i++) ...[
                                        if (i > 0)
                                          SizedBox(width: shieldSize * 0.028),
                                        FadeTransition(
                                          opacity: _letterFade[i],
                                          child: SlideTransition(
                                            position: _letterSlide[i],
                                            child: ScaleTransition(
                                              scale: _letterScale[i],
                                              child: _InoLetter(
                                                letter: const ['I', 'N', 'O'][i],
                                                size: shieldSize,
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

/// One letter of the splash wordmark — Plus Jakarta Sans, carved white face
/// with depth + a soft brand glow so it reads as premium type on the clay shield.
class _InoLetter extends StatelessWidget {
  const _InoLetter({required this.letter, required this.size});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.225;
    final base = GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.0,
      letterSpacing: fontSize * 0.05,
    );

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Soft brand halo.
        Text(
          letter,
          style: base.copyWith(
            color: Colors.white.withValues(alpha: 0.01),
            shadows: [
              Shadow(
                color: Colors.white.withValues(alpha: 0.40),
                blurRadius: fontSize * 0.42,
              ),
              Shadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.40),
                blurRadius: fontSize * 0.70,
              ),
            ],
          ),
        ),
        // Depth plate.
        Transform.translate(
          offset: Offset(0, fontSize * 0.04),
          child: Text(
            letter,
            style: base.copyWith(
              color: Colors.black.withValues(alpha: 0.30),
            ),
          ),
        ),
        // Lit face — soft vertical sheen.
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF5FCFB),
              Color(0xFFE6F4F3),
            ],
            stops: [0.0, 0.48, 1.0],
          ).createShader(bounds),
          child: Text(
            letter,
            style: base.copyWith(color: Colors.white),
          ),
        ),
      ],
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
