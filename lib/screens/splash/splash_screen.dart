import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../repositories/user_repository.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../auth/auth_flow.dart';
import '../auth/login_screen.dart';
import '../onboarding/onboarding_screen.dart';

/// Clean cozy splash — theme-tinted sky, brand shield, then I → N → O.
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

  late final Animation<double> _shieldFade;
  late final Animation<double> _shieldScale;

  late final List<Animation<double>> _letterFade;
  late final List<Animation<double>> _letterScale;

  bool _navigated = false;

  static const _shieldAsset = 'assets/splash/splash_shield_blank.png';

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4600),
    )..addStatusListener(_onStatusChanged);

    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _shieldFade = _phase(0.00, 0.26, Curves.easeOut);
    _shieldScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.00, 0.30, curve: Curves.easeOutCubic),
      ),
    );

    const starts = [0.34, 0.46, 0.58];
    const ends = [0.50, 0.62, 0.74];
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
      Future<void>.delayed(const Duration(milliseconds: 1200), _continue);
    }
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
          goToShell(context, profile);
          return;
        }
      }
    } catch (_) {
      // Fall through to Login — never block cold start on network.
    }

    if (!mounted) return;
    _replace(const LoginScreen());
  }

  void _replace(Widget page) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final palette = AppPalette.of(context);
    final brand = AppColors.primaryGreen;
    final shieldSize =
        (size.shortestSide * 0.68).clamp(240.0, 340.0).toDouble();

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
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_c, _float]),
            builder: (context, _) {
              final bob = math.sin(_float.value * math.pi) * 3;
              return Center(
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
                            Transform.translate(
                              offset: Offset(0, shieldSize * 0.06),
                              child: Container(
                                width: shieldSize * 0.55,
                                height: shieldSize * 0.12,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.elliptical(
                                      shieldSize * 0.55,
                                      shieldSize * 0.12,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: brand.withValues(alpha: 0.22),
                                      blurRadius: 28,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            _GlassyShieldMark(
                              asset: _shieldAsset,
                              size: shieldSize,
                              accent: brand,
                              shine: InoStyle.of(context) == ThemeStyle.soft,
                            ),

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
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Brand-green shield with a soft glass gloss — solid green fill, white letters
/// sit on top in the splash.
class _GlassyShieldMark extends StatelessWidget {
  const _GlassyShieldMark({
    required this.asset,
    required this.size,
    required this.accent,
    required this.shine,
  });

  final String asset;
  final double size;
  final Color accent;
  final bool shine;

  Color _lift(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + amount * 0.5).clamp(0.0, 1.0))
        .toColor();
  }

  Widget _masked(Shader shader) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (_) => shader,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: Colors.white,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Icon(
          Icons.shield_rounded,
          size: size * 0.85,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rect = Rect.fromLTWH(0, 0, size, size);

    // Saturated green fill (same colour edge → centre), with a soft lift for depth.
    final bodyShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _lift(accent, 0.12),
        accent,
        _lift(accent, 0.02),
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(rect);

    final glossShader = RadialGradient(
      center: const Alignment(-0.55, -0.70),
      radius: 1.0,
      colors: [
        Colors.white.withValues(alpha: 0.42),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.85],
    ).createShader(rect);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _masked(bodyShader),
          _masked(glossShader),
          if (shine)
            Opacity(
              opacity: 0.35,
              child: _masked(
                SweepGradient(
                  transform: const GradientRotation(-math.pi),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.85),
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.12, 0.34, 0.62, 0.86],
                ).createShader(rect),
              ),
            ),
        ],
      ),
    );
  }
}
