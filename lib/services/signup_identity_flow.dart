import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_security_service.dart';

/// Whether a signed-in signup still needs the other identifier confirmed.
///
/// True only when one side is already confirmed and the other was collected.
/// A finished account, or an older account with only one identifier, is false.
bool secondFactorStillNeeded({
  required bool emailConfirmed,
  required bool phoneConfirmed,
  required String email,
  required String phone,
}) {
  if (emailConfirmed && phoneConfirmed) return false;
  if (emailConfirmed && !phoneConfirmed && phone.trim().isNotEmpty) return true;
  if (phoneConfirmed && !emailConfirmed && email.trim().isNotEmpty) return true;
  return false;
}

/// Phone to store when finishing a profile.
///
/// A confirmed Auth phone is kept. A different typed number is rejected
/// (`null`) so an unverified value cannot replace it.
String? profilePhoneToSave({
  required String? confirmedPhone,
  required String typedPhone,
}) {
  if (confirmedPhone == null || confirmedPhone.trim().isEmpty) {
    return DualSignupCoordinator.phoneTarget(typedPhone);
  }
  final confirmed = DualSignupCoordinator.phoneTarget(confirmedPhone);
  final typed = DualSignupCoordinator.phoneTarget(typedPhone);
  if (typed != confirmed) return null;
  return confirmed;
}

/// Result of asking Supabase to attach the not-yet-confirmed identifier.
class SecondLinkStart {
  const SecondLinkStart.ready(this.target) : blocked = false;

  const SecondLinkStart.blocked()
      : target = null,
        blocked = true;

  final String? target;
  final bool blocked;
}

/// Attaches and confirms the second signup identifier on an existing user.
///
/// Callers inject the Auth and profile operations so tests never touch
/// Supabase. [linkPhone] and [linkEmail] must update the current session.
/// They must not call sign-up or sign-in-with-OTP.
class DualSignupCoordinator {
  DualSignupCoordinator({
    required this.identifierTaken,
    required this.linkPhone,
    required this.linkEmail,
    required this.verifyPhoneUserId,
    required this.verifyEmailUserId,
    required this.createProfile,
  });

  final Future<bool> Function(String identifier) identifierTaken;
  final Future<void> Function(String phone) linkPhone;
  final Future<void> Function(String email) linkEmail;
  final Future<String?> Function(String phone, String code) verifyPhoneUserId;
  final Future<String?> Function(String email, String code) verifyEmailUserId;
  final Future<void> Function({
    required String authUserId,
    required String fullName,
    required String email,
    required String phone,
  }) createProfile;

  static String phoneTarget(String phone) {
    final canonical = AccountSecurityService.canonicalPhone(phone);
    return canonical.isEmpty ? phone.trim() : canonical;
  }

  /// Sends the second OTP. Returns [SecondLinkStart.blocked] when that
  /// identifier is already confirmed on another account. Does not link then.
  Future<SecondLinkStart> beginSecond({
    required bool firstWasEmail,
    required String email,
    required String phone,
  }) async {
    final target = firstWasEmail ? phoneTarget(phone) : email.trim();
    if (await identifierTaken(target)) return const SecondLinkStart.blocked();
    if (firstWasEmail) {
      await linkPhone(target);
    } else {
      await linkEmail(target);
    }
    return SecondLinkStart.ready(target);
  }

  /// Resends the second code through the link API. Never creates a user.
  Future<void> resend({
    required bool firstWasEmail,
    required String target,
  }) async {
    if (await identifierTaken(target)) {
      throw const AuthException(
        'That email or mobile number is already on another INO account. '
        'Sign out and log in with that account.',
      );
    }
    if (firstWasEmail) {
      await linkPhone(target);
    } else {
      await linkEmail(target);
    }
  }

  /// Confirms the second code. Creates a profile only when the verified user
  /// id is [expectedUserId]. Returns false when the id does not match.
  Future<bool> confirmSecond({
    required String expectedUserId,
    required bool firstWasEmail,
    required String target,
    required String code,
    required String fullName,
    required String email,
    required String phone,
  }) async {
    final userId = firstWasEmail
        ? await verifyPhoneUserId(target, code)
        : await verifyEmailUserId(target, code);
    if (userId == null || userId != expectedUserId) return false;
    await createProfile(
      authUserId: userId,
      fullName: fullName,
      email: email.trim(),
      phone: phoneTarget(phone),
    );
    return true;
  }
}
