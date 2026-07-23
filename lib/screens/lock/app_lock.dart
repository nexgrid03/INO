import 'package:flutter/material.dart';

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
/// It locks on cold start and every time the app returns from the background —
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

  /// True while the OS biometric sheet is up — guards against the prompt's own
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
    // Turning it ON does not lock the current session immediately — it takes
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
    final ok = await _svc.authenticate(reason: 'Unlock INO');
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

/// The full-screen lock overlay, styled after the vault security-lock design:
/// a secure-link header, display headline, a tappable concentric biometric
/// hero (glass ring + gradient disc) and an "Unlock" [PrimaryButton] that
/// re-invokes the biometric prompt. The surface deliberately commits to the
/// dark palette in both themes — the standard banking-app lock treatment.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.authenticating, required this.onUnlock});

  final bool authenticating;
  final VoidCallback onUnlock;

  /// The lock surface is always dark, whatever the ambient theme.
  static const AppPalette _palette = AppPalette.dark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _palette.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_palette.bgElevated, _palette.bg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const FadeSlideIn(child: _SecureHeader()),
                const Spacer(),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: Column(
                    children: [
                      Text(
                        'INO is locked',
                        textAlign: TextAlign.center,
                        style: AppText.display.copyWith(
                          color: Colors.white,
                          fontSize: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Unlock with your fingerprint or Face ID to\naccess your vault.',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.66),
                          fontSize: 14.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 44),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child:
                      _BiometricHero(busy: authenticating, onTap: onUnlock),
                ),
                const SizedBox(height: 36),
                const FadeSlideIn(
                  delay: Duration(milliseconds: 220),
                  child: _EncryptionDivider(),
                ),
                const Spacer(),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: PrimaryButton(
                    label: 'Unlock',
                    icon: Icons.lock_open_rounded,
                    busy: authenticating,
                    onPressed: onUnlock,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top chrome: the brand mark with a verified shield, and a glassy
/// "SECURE LINK" status pill with a glowing green dot (decorative).
class _SecureHeader extends StatelessWidget {
  const _SecureHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'INO',
          style: AppText.headline.copyWith(
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.verified_user_rounded,
            color: AppColors.success, size: 18),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: _LockScreen._palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SECURE LINK',
                style: AppText.label.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The concentric biometric mark: an outer glass ring around a brand-gradient
/// disc with the fingerprint glyph. Tapping it re-invokes the same biometric
/// prompt as the Unlock button.
class _BiometricHero extends StatelessWidget {
  const _BiometricHero({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 176,
          height: 176,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: _LockScreen._palette.border),
          ),
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.45),
                    blurRadius: 34,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.fingerprint_rounded,
                  color: Colors.white, size: 56),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "— VERIFIED ENCRYPTION —" hairline divider row (decorative).
class _EncryptionDivider extends StatelessWidget {
  const _EncryptionDivider();

  @override
  Widget build(BuildContext context) {
    final line = Container(
      width: 44,
      height: 1,
      color: Colors.white.withValues(alpha: 0.18),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line,
        const SizedBox(width: 16),
        Text(
          'VERIFIED ENCRYPTION',
          style: AppText.label.copyWith(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 16),
        line,
      ],
    );
  }
}
