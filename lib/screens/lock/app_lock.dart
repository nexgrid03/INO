import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_buttons.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';

/// Wraps the whole app (via `MaterialApp.builder`) and, when the user has
/// enabled the biometric app-lock, covers everything with a lock screen that
/// requires a fingerprint / Face ID (or the device PIN fallback) to dismiss.
///
/// It locks on cold start and every time the app returns from the background -
/// the standard banking-app behaviour. When the lock is off it is completely
/// inert (zero overhead, never shown).
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child});

  final Widget child;

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  BiometricService get _svc => BiometricService.instance;

  bool _initialized = false;
  bool _locked = false;

  /// True while the OS biometric sheet is up - guards against the prompt's own
  /// pause/resume re-triggering a second prompt (no loops, no double sheets).
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc.lockEnabled.addListener(_onEnabledChanged);
    // Seed from the flag main() already loaded, so the lock is up on frame 1
    // (no flash of app content). Defaults to false when unset (e.g. in tests).
    _initialized = true;
    _locked = _svc.lockEnabled.value;
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _authenticate();
      });
    }
    // Safety net for hosts that didn't preload (re-reads storage, then locks).
    _init();
  }

  Future<void> _init() async {
    await _svc.loadLockState();
    if (!mounted) return;
    if (_svc.lockEnabled.value && !_locked) {
      setState(() => _locked = true);
      _authenticate();
    }
  }

  void _onEnabledChanged() {
    // Turning the lock OFF (e.g. from Settings, or on sign-out) must never
    // leave the user stranded behind the lock screen.
    if (!_svc.lockEnabled.value && _locked) {
      setState(() => _locked = false);
    }
    // Turning it ON does not lock the current session immediately - it takes
    // effect on the next background→foreground, like every other app-lock.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _svc.lockEnabled.removeListener(_onEnabledChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_svc.lockEnabled.value) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Re-arm the lock as soon as we leave the foreground so the app-switcher
        // snapshot and the next resume are both covered.
        if (!_authenticating && !_locked) {
          setState(() => _locked = true);
        }
      case AppLifecycleState.resumed:
        if (_locked && !_authenticating) _authenticate();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final reason = AppLocalizations.of(context).t('unlockIno');
    final ok = await _svc.authenticate(reason: reason);
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      if (ok) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_initialized && _locked)
          _LockScreen(
            authenticating: _authenticating,
            onUnlock: _authenticate,
          ),
      ],
    );
  }
}

/// The full-screen lock overlay: brand header, "Digital Wallet" headline, a
/// tappable concentric biometric hero and an Unlock CTA. The surface commits
/// to the Divine Glass light sky wash in both themes so the lock reads as
/// part of the brand.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.authenticating, required this.onUnlock});

  final bool authenticating;
  final VoidCallback onUnlock;

  /// The lock surface always uses the light Divine Glass palette.
  static const AppPalette _palette = AppPalette.light;

  /// Keeps the unlock column phone-width on tablets / desktop (e.g. Chrome).
  static const double _contentMaxWidth = 400;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _palette.bg,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FCFF), AppColors.background],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.only(bottom: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padH = constraints.maxWidth < 360 ? 20.0 : 28.0;
              final contentWidth =
                  (constraints.maxWidth - padH * 2).clamp(0.0, _contentMaxWidth);
              final short = constraints.maxHeight < 640;
              final veryShort = constraints.maxHeight < 520;
              // Scale hero from available column width + height so it never
              // overflows short Chrome windows or tiny phones.
              final heroSize = (contentWidth * 0.44)
                  .clamp(112.0, veryShort ? 128.0 : (short ? 148.0 : 176.0))
                  .toDouble();
              final titleSize = veryShort ? 24.0 : (short ? 26.0 : 32.0);
              final gapTitleHero = veryShort ? 16.0 : (short ? 24.0 : 36.0);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: padH),
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        const FadeSlideIn(child: _SecureHeader()),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, mid) {
                              final body = Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FadeSlideIn(
                                    delay: const Duration(milliseconds: 60),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Padding(
                                        // Leave room for descenders ("g" in Digital).
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                          top: 2,
                                        ),
                                        child: Text(
                                          AppLocalizations.of(context)
                                              .t('digitalWallet'),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          style: AppText.display.copyWith(
                                            color: _palette.textPrimary,
                                            fontSize: titleSize,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: gapTitleHero),
                                  FadeSlideIn(
                                    delay: const Duration(milliseconds: 140),
                                    child: _BiometricHero(
                                      busy: authenticating,
                                      onTap: onUnlock,
                                      size: heroSize,
                                    ),
                                  ),
                                ],
                              );
                              // Scroll only when the mid section is too short
                              // for the hero + title (avoids RenderFlex overflow).
                              if (mid.maxHeight < heroSize + gapTitleHero + 48) {
                                return SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: mid.maxHeight,
                                    ),
                                    child: Center(child: body),
                                  ),
                                );
                              }
                              return Center(child: body);
                            },
                          ),
                        ),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 300),
                          child: SizedBox(
                            width: double.infinity,
                            child: PrimaryButton(
                              label: AppLocalizations.of(context)
                                  .t('sharePasswordUnlock'),
                              icon: Icons.lock_open_rounded,
                              busy: authenticating,
                              onPressed: onUnlock,
                            ),
                          ),
                        ),
                        SizedBox(height: veryShort ? 12 : 20),
                      ],
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

/// Top chrome: brand mark with a verified shield.
class _SecureHeader extends StatelessWidget {
  const _SecureHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'INO',
          style: AppText.headline.copyWith(
            color: _LockScreen._palette.textPrimary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.verified_user_rounded,
            color: AppColors.success, size: 18),
      ],
    );
  }
}

/// The concentric biometric mark: an outer glass ring around a brand-gradient
/// disc with the fingerprint glyph. Tapping it re-invokes the same biometric
/// prompt as the Unlock button.
class _BiometricHero extends StatelessWidget {
  const _BiometricHero({
    required this.busy,
    required this.onTap,
    this.size = 176,
  });

  final bool busy;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inner = size * 0.545;
    final iconSize = size * 0.318;
    return PressableScale(
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.tealPale),
            boxShadow: AppShadows.card,
          ),
          child: Center(
            child: Container(
              width: inner,
              height: inner,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.45),
                    blurRadius: 34,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(Icons.fingerprint_rounded,
                  color: Colors.white, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
