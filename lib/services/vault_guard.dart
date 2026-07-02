import 'package:flutter/material.dart';

import '../widgets/security/biometric_ux.dart';
import 'biometric_service.dart';

/// Session-based biometric gate for sensitive actions and protected documents.
///
/// After a successful prompt the vault stays unlocked for [sessionWindow]
/// (2 minutes). Within that window, gated actions don't re-prompt. The session
/// is invalidated when the app is backgrounded, on a manual [lock], or once the
/// window elapses — so reopening / returning from the background always
/// re-authenticates.
///
/// This is independent of the whole-app [AppLock]: it gates *specific* actions
/// (opening a protected document, viewing secrets, exporting, changing security
/// settings) even when the app-lock is off.
class VaultGuard with WidgetsBindingObserver {
  VaultGuard._();
  static final VaultGuard instance = VaultGuard._();

  /// How long a single authentication keeps the vault unlocked.
  static const Duration sessionWindow = Duration(minutes: 2);

  DateTime? _unlockedAt;
  bool _observing = false;

  /// Registers lifecycle observation. Call once at startup.
  void init() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  /// Whether the vault is currently within its unlocked session window.
  bool get isUnlocked {
    final at = _unlockedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < sessionWindow;
  }

  void _stamp() => _unlockedAt = DateTime.now();

  /// Manually ends the session (e.g. a "Lock vault now" action).
  void lock() => _unlockedAt = null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the foreground ends the session — returning requires re-auth.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      lock();
    }
  }

  /// Ensures the vault is unlocked before a sensitive action.
  ///
  /// Returns true if already unlocked within the session, or after a successful
  /// biometric prompt. Shows a friendly error (except on a plain user-cancel)
  /// when it fails. Pass [force] to bypass the session cache and always prompt.
  Future<bool> ensureUnlocked(
    BuildContext context, {
    required String reason,
    String title = 'Verify your identity',
    bool force = false,
  }) async {
    if (!force && isUnlocked) return true;
    final outcome = await BiometricService.instance
        .authenticateDetailed(reason: reason, title: title);
    if (outcome.ok) {
      _stamp();
      return true;
    }
    final error = outcome.error;
    if (context.mounted && error != null && !error.isSilent) {
      BiometricUx.errorSnack(context, error.message);
    }
    return false;
  }
}
