import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';

/// The setup material for a pending TOTP enrollment: the factor id plus the
/// secret / provisioning URI the user adds to their authenticator app.
class TotpSetup {
  const TotpSetup({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  final String factorId;
  final String secret;
  final String uri;
}

/// Two-Factor Authentication backed by **Supabase MFA (TOTP)** — a genuine,
/// server-verified second factor, not a local flag.
///
/// Flow: [startEnrollment] registers a TOTP factor and returns the secret/URI →
/// the user scans it into Google Authenticator / Authy → [confirm] verifies a
/// 6-digit code (promoting the session to `aal2`). [disable] unenrolls every
/// verified factor. [isEnabled] reflects the real backend state, and the result
/// is mirrored into [AppSettings.twoFactor] so the Profile row is instant.
class TwoFactorService {
  TwoFactorService._();
  static final TwoFactorService instance = TwoFactorService._();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Whether the user has at least one *verified* TOTP factor on the backend.
  Future<bool> isEnabled() async {
    try {
      final factors = await _auth.mfa.listFactors();
      final enabled =
          factors.totp.any((f) => f.status == FactorStatus.verified);
      await AppSettings.instance.setTwoFactor(enabled);
      developer.log('2FA isEnabled=$enabled', name: '2fa');
      return enabled;
    } catch (e) {
      developer.log('2FA isEnabled check failed: $e', name: '2fa');
      return AppSettings.instance.twoFactor.value;
    }
  }

  /// Begins TOTP enrollment. Clears any stale *unverified* factors first so a
  /// retried setup doesn't collide on friendly-name uniqueness.
  Future<TotpSetup> startEnrollment() async {
    await _clearUnverifiedFactors();
    developer.log('2FA enroll: creating TOTP factor', name: '2fa');
    final res = await _auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'INO',
      friendlyName: 'INO ${DateTime.now().millisecondsSinceEpoch}',
    );
    final totp = res.totp;
    if (totp == null) {
      throw const AuthException('TOTP enrollment did not return a secret.');
    }
    return TotpSetup(factorId: res.id, secret: totp.secret, uri: totp.uri);
  }

  /// Verifies the 6-digit [code] against the pending [factorId]. On success the
  /// factor becomes verified and 2FA is active.
  Future<void> confirm({
    required String factorId,
    required String code,
  }) async {
    developer.log('2FA confirm: verifying code', name: '2fa');
    await _auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim());
    await AppSettings.instance.setTwoFactor(true);
    developer.log('2FA confirm: verified', name: '2fa');
  }

  /// Disables 2FA by unenrolling every TOTP factor (verified or not).
  Future<void> disable() async {
    developer.log('2FA disable: unenrolling factors', name: '2fa');
    final factors = await _auth.mfa.listFactors();
    for (final f in factors.totp) {
      try {
        await _auth.mfa.unenroll(f.id);
      } catch (e) {
        developer.log('2FA disable: unenroll ${f.id} failed: $e', name: '2fa');
      }
    }
    await AppSettings.instance.setTwoFactor(false);
    developer.log('2FA disable: done', name: '2fa');
  }

  Future<void> _clearUnverifiedFactors() async {
    try {
      final factors = await _auth.mfa.listFactors();
      for (final f in factors.all) {
        if (f.status == FactorStatus.unverified) {
          await _auth.mfa.unenroll(f.id);
        }
      }
    } catch (e) {
      developer.log('2FA: clearing stale factors failed: $e', name: '2fa');
    }
  }
}
