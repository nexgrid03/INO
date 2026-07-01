import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// The kind of biometric a device offers, used only to label the UI.
enum BiometricKind { faceId, fingerprint, generic, none }

extension BiometricKindX on BiometricKind {
  String get actionLabel => switch (this) {
        BiometricKind.faceId => 'Enable Face ID',
        BiometricKind.fingerprint => 'Enable Fingerprint',
        BiometricKind.generic => 'Enable Biometric',
        BiometricKind.none => 'Enable Biometric',
      };

  String get noun => switch (this) {
        BiometricKind.faceId => 'Face ID',
        BiometricKind.fingerprint => 'fingerprint',
        BiometricKind.generic => 'biometric',
        BiometricKind.none => 'biometric',
      };
}

/// Thin abstraction over device biometrics for the Biometric Setup screen.
///
/// This is intentionally a UI-ready STUB — no native dependency is added yet.
/// When you're ready to make it real, add the `local_auth` package and replace
/// the bodies below with `LocalAuthentication` calls (the screen already talks
/// to this interface, so no UI changes will be needed):
///
///   final _auth = LocalAuthentication();
///   isAvailable()  → _auth.isDeviceSupported() && _auth.canCheckBiometrics
///   detectKind()   → map _auth.getAvailableBiometrics()
///   authenticate() → _auth.authenticate(localizedReason: reason, options: …)
///
/// Until then it reports a sensible platform default and simulates a successful
/// prompt so the flow is fully navigable during development.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  /// Whether biometric hardware can be offered on this platform.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// The primary biometric to advertise (Face ID on iOS, fingerprint on
  /// Android by convention). Real detection arrives with `local_auth`.
  Future<BiometricKind> detectKind() async {
    if (!await isAvailable()) return BiometricKind.none;
    return defaultTargetPlatform == TargetPlatform.iOS
        ? BiometricKind.faceId
        : BiometricKind.fingerprint;
  }

  /// Prompts the OS biometric sheet. Returns true when the user authenticates.
  ///
  /// STUB: simulates a brief prompt then succeeds. Wire to `local_auth` for the
  /// real system sheet.
  Future<bool> authenticate({required String reason}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return true;
  }
}
