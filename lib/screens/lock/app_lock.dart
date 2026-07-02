import 'package:flutter/material.dart';

import '../../services/biometric_service.dart';
import '../../theme/app_theme.dart';

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

/// The full-screen lock overlay: brand gradient, a shield/lock mark, and an
/// "Unlock" button that re-invokes the biometric prompt.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.authenticating, required this.onUnlock});

  final bool authenticating;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF07141A),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1F27), Color(0xFF07141A)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // Biometric mark.
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.45),
                        blurRadius: 34,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.fingerprint_rounded,
                      color: Colors.white, size: 64),
                ),
                const SizedBox(height: 32),
                const Text(
                  'INO is locked',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Unlock with your fingerprint or Face ID to\naccess your vault.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 14.5,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                _UnlockButton(busy: authenticating, onTap: onUnlock),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockButton extends StatelessWidget {
  const _UnlockButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_open_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Unlock',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
