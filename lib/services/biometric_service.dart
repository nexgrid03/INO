import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb, debugPrint;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kind of biometric a device offers, used to label the UI.
enum BiometricKind { faceId, fingerprint, iris, generic, none }

extension BiometricKindX on BiometricKind {
  String get actionLabel => switch (this) {
        BiometricKind.faceId => 'Enable Face ID',
        BiometricKind.fingerprint => 'Enable Fingerprint',
        BiometricKind.iris => 'Enable Iris Unlock',
        BiometricKind.generic => 'Enable Biometric',
        BiometricKind.none => 'Enable Biometric',
      };

  String get noun => switch (this) {
        BiometricKind.faceId => 'Face ID',
        BiometricKind.fingerprint => 'fingerprint',
        BiometricKind.iris => 'iris unlock',
        BiometricKind.generic => 'biometric',
        BiometricKind.none => 'biometric',
      };
}

/// Device capability for biometrics.
enum BiometricSupport {
  /// Hardware present AND at least one fingerprint/face enrolled.
  ready,

  /// Hardware present but nothing enrolled — send the user to Settings.
  notEnrolled,

  /// No biometric hardware / platform (or web).
  unsupported,
}

/// Every failure mode the biometric prompt can produce, mapped to a friendly,
/// actionable message. [canceled] is intentionally "silent" (the user chose to
/// dismiss — don't nag).
enum BiometricError {
  notAvailable,
  notEnrolled,
  lockedOut,
  permanentlyLockedOut,
  passcodeNotSet,
  canceled,
  failed,
}

extension BiometricErrorX on BiometricError {
  bool get isSilent => this == BiometricError.canceled;

  String get message => switch (this) {
        BiometricError.notAvailable =>
          "Biometric authentication isn't available on this device.",
        BiometricError.notEnrolled =>
          'No biometrics are enrolled. Add a fingerprint or face in Settings.',
        BiometricError.lockedOut =>
          'Too many attempts. Try again in a few seconds.',
        BiometricError.permanentlyLockedOut =>
          'Biometrics are locked. Unlock with your device PIN or password, then try again.',
        BiometricError.passcodeNotSet =>
          'Set a screen lock (PIN, pattern or password) on your device first.',
        BiometricError.canceled => 'Authentication cancelled.',
        BiometricError.failed => "Couldn't verify your identity. Please try again.",
      };
}

/// The result of a biometric prompt: success, or a typed [error].
class BiometricAuthOutcome {
  const BiometricAuthOutcome.success()
      : ok = true,
        error = null;
  const BiometricAuthOutcome.failure(this.error) : ok = false;

  final bool ok;
  final BiometricError? error;
}

/// Real device biometrics for INO, backed by the `local_auth` plugin +
/// Android's official `BiometricPrompt`.
///
/// Responsibilities:
///   1. Report capability ([support] / [isAvailable] / [detectKind]).
///   2. Prompt the OS biometric sheet ([authenticate] / [authenticateDetailed]).
///   3. Open the OS biometric-enrollment screen ([openEnrollmentSettings]).
///   4. Own the **app-lock preference** — persisted via `shared_preferences` and
///      mirrored on [lockEnabled] so every surface stays in sync instantly.
///
/// It never stores or sees biometric data — only a boolean preference.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Platform channel to open the native biometric-enrollment settings.
  static const MethodChannel _channel = MethodChannel('ino/biometric');

  static const String _lockKey = 'biometric_lock_enabled';

  /// Whether the biometric app-lock is currently ON. Listenable so widgets
  /// react the instant it's toggled anywhere in the app.
  final ValueNotifier<bool> lockEnabled = ValueNotifier<bool>(false);

  // ---- Capability -----------------------------------------------------------

  /// Full capability check: hardware present + something enrolled.
  Future<BiometricSupport> support() async {
    if (kIsWeb) return BiometricSupport.unsupported;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricSupport.unsupported;
      final enrolled = (await _auth.getAvailableBiometrics()).isNotEmpty;
      return enrolled ? BiometricSupport.ready : BiometricSupport.notEnrolled;
    } catch (_) {
      return BiometricSupport.unsupported;
    }
  }

  /// Convenience: whether an auth prompt (biometric or device credential) can
  /// realistically be shown.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// The primary biometric to advertise, from what the device actually reports.
  Future<BiometricKind> detectKind() async {
    if (kIsWeb) return BiometricKind.none;
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return BiometricKind.faceId;
      if (types.contains(BiometricType.fingerprint)) {
        return BiometricKind.fingerprint;
      }
      if (types.contains(BiometricType.iris)) return BiometricKind.iris;
      if (types.isNotEmpty) return BiometricKind.generic;
      return await _auth.isDeviceSupported()
          ? BiometricKind.generic
          : BiometricKind.none;
    } catch (_) {
      return BiometricKind.none;
    }
  }

  // ---- Prompt ---------------------------------------------------------------

  /// Prompts the native biometric sheet and returns a typed [outcome].
  ///
  /// [title] is the BiometricPrompt title; [reason] its subtitle/description.
  /// [biometricOnly] false lets the OS offer the device PIN/pattern as a
  /// fallback, so a user is never permanently locked out.
  Future<BiometricAuthOutcome> authenticateDetailed({
    required String reason,
    String title = 'Verify your identity',
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) {
      return const BiometricAuthOutcome.failure(BiometricError.notAvailable);
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: title,
            biometricHint: '',
            cancelButton: 'Cancel',
          ),
          const IOSAuthMessages(cancelButton: 'Cancel'),
        ],
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return ok
          ? const BiometricAuthOutcome.success()
          : const BiometricAuthOutcome.failure(BiometricError.canceled);
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: ${e.code} ${e.message}');
      return BiometricAuthOutcome.failure(_mapError(e.code));
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return const BiometricAuthOutcome.failure(BiometricError.failed);
    }
  }

  /// Simple boolean prompt (used by the whole-app lock screen).
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    final outcome = await authenticateDetailed(
      reason: reason,
      title: 'Unlock INO',
      biometricOnly: biometricOnly,
    );
    return outcome.ok;
  }

  BiometricError _mapError(String code) {
    if (code == auth_error.notAvailable) return BiometricError.notAvailable;
    if (code == auth_error.notEnrolled) return BiometricError.notEnrolled;
    if (code == auth_error.lockedOut) return BiometricError.lockedOut;
    if (code == auth_error.permanentlyLockedOut) {
      return BiometricError.permanentlyLockedOut;
    }
    if (code == auth_error.passcodeNotSet) return BiometricError.passcodeNotSet;
    return BiometricError.failed;
  }

  /// Opens the device's native biometric-enrollment screen (Android
  /// `Settings.ACTION_BIOMETRIC_ENROLL`, with graceful fallbacks). We never
  /// build a custom enrollment UI.
  Future<void> openEnrollmentSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('openEnrollment');
    } catch (e) {
      debugPrint('openEnrollment failed: $e');
    }
  }

  // ---- App-lock preference (persisted) -------------------------------------

  /// Reads the persisted lock flag into [lockEnabled]. Call once at startup.
  Future<void> loadLockState() async {
    lockEnabled.value = await _readLockEnabled();
  }

  Future<bool> _readLockEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_lockKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Turns the biometric app-lock on/off and persists it. Updates [lockEnabled]
  /// synchronously so listeners react immediately.
  Future<void> setLockEnabled(bool value) async {
    lockEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lockKey, value);
    } catch (_) {
      // Best-effort; the in-memory notifier is still correct for this session.
    }
  }
}
