import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' show ClientException;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../core/net/net_guard.dart';
import '../utils/secure_logger.dart';
import 'account_switcher.dart';
import 'biometric_service.dart';
import 'push_service.dart';
import 'session_reset.dart';

/// Single place that talks to Supabase auth.
///
/// Supports:
///   • Email + password sign-up and sign-in
///   • Native "Continue with Google" (on-device account picker)
///   • Sign out, current session/user, and an auth-state stream
///
/// Keep all auth logic here so screens stay UI-only.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Resolved lazily so the app can build (and tests can run) without Supabase
  /// being initialised - it's only touched when a method is actually called.
  SupabaseClient get _client => Supabase.instance.client;

  // --- Session helpers ------------------------------------------------------

  Session? get currentSession {
    try {
      return _client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser {
    try {
      return _client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  bool get isSignedIn {
    try {
      return currentSession != null;
    } catch (_) {
      return false;
    }
  }

  /// Whether the currently signed-in user has accepted the Terms of Service & Privacy Policy.
  bool get hasAcceptedTerms {
    try {
      final user = currentUser;
      if (user == null) return false;
      final metadata = user.userMetadata ?? {};
      return metadata['accepted_terms'] == true || metadata['terms_accepted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Records terms acceptance in user metadata and the user_consents audit table.
  Future<void> recordTermsConsent({
    String version = '1.0',
    bool attest18Plus = true,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // 1. Update user metadata if not already recorded
    final meta = user.userMetadata ?? {};
    if (meta['accepted_terms'] != true || meta['attestation_18_plus'] != attest18Plus) {
      await _client.auth.updateUser(
        UserAttributes(
          data: {
            'accepted_terms': true,
            'accepted_at': nowIso,
            'terms_version': version,
            'attestation_18_plus': attest18Plus,
            'attestation_18_at': nowIso,
          },
        ),
      );
    }

    // 2. Ensure audit row is recorded in user_consents table
    await _client.from('user_consents').insert({
      'user_id': user.id,
      'consent_type': 'terms_and_privacy',
      'version': version,
      'accepted_at': nowIso,
    });
  }

  /// Records notification consent in the user_consents audit table.
  Future<void> recordPushNotificationConsent({String version = '1.0'}) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await _client.from('user_consents').insert({
        'user_id': user.id,
        'consent_type': 'push_notifications',
        'version': version,
        'accepted_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      developer.log('recordPushNotificationConsent audit log failed: $e', name: 'auth');
    }
  }

  /// Emits on sign-in, sign-out, token refresh, etc. Useful for an "AuthGate".
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // --- Email + password -----------------------------------------------------

  /// Creates a new account. If email confirmation is enabled in Supabase,
  /// [AuthResponse.session] will be null until the user confirms via email.
  ///
  /// [fullName] is also stored in the auth user's metadata. That's handy later
  /// (e.g. so a database trigger or Google flow can read the name), separate
  /// from the profile row we insert into `public.users`.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
    bool acceptedTerms = true,
    bool attest18Plus = true,
  }) {
    // Every auth round-trip is time-capped: an un-timed call on a dead link
    // used to hang the login screen forever instead of surfacing an error.
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return _client.auth
        .signUp(
          email: email.trim(),
          password: password,
          data: {
            if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
            if (acceptedTerms) ...{
              'accepted_terms': true,
              'accepted_at': nowIso,
              'terms_version': '1.0',
              'attestation_18_plus': attest18Plus,
              'attestation_18_at': nowIso,
            },
          },
        )
        .timeout(NetGuard.auth);
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth
        .signInWithPassword(email: email.trim(), password: password)
        .timeout(NetGuard.auth);
  }

  /// Sends a password-reset email.
  Future<void> sendPasswordReset(String email) {
    return _client.auth
        .resetPasswordForEmail(email.trim())
        .timeout(NetGuard.auth);
  }

  /// Verifies the 6-digit recovery code. On success the returned
  /// [AuthResponse] carries an authenticated session.
  Future<AuthResponse> verifyRecoveryOtp({
    required String email,
    required String token,
  }) {
    return _client.auth
        .verifyOTP(
          type: OtpType.recovery,
          email: email.trim(),
          token: token.trim(),
        )
        .timeout(NetGuard.auth);
  }

  /// Updates the user's password once an authenticated/recovery session is active.
  Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth
        .updateUser(UserAttributes(password: newPassword.trim()))
        .timeout(NetGuard.auth);
  }

  // --- Email OTP (passwordless sign-in / verification) ----------------------

  /// Sends a 6-digit code to [email] via Supabase Auth.
  ///
  /// [shouldCreateUser] must be false on the login path. Leaving it true is
  /// what used to mint a second account whenever someone signed in with an
  /// identifier their auth user did not carry - see [accountExists].
  Future<void> sendEmailOtp(
    String email, {
    Map<String, dynamic>? data,
    bool shouldCreateUser = true,
  }) {
    return _client.auth
        .signInWithOtp(
          email: email.trim(),
          data: data,
          shouldCreateUser: shouldCreateUser,
        )
        .timeout(NetGuard.auth);
  }

  /// Verifies the 6-digit email OTP [token] for [email]. On success the returned
  /// [AuthResponse] carries an authenticated session.
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return _client.auth
        .verifyOTP(
          type: OtpType.email,
          email: email.trim(),
          token: token.trim(),
        )
        .timeout(NetGuard.auth);
  }

  /// Re-sends the 6-digit sign-up confirmation code to [email].
  Future<void> resendSignupOtp(String email) {
    return _client.auth
        .resend(type: OtpType.signup, email: email.trim())
        .timeout(NetGuard.auth);
  }

  /// Verifies the 6-digit sign-up code. On success the returned
  /// [AuthResponse] carries an authenticated session.
  Future<AuthResponse> verifySignupOtp({
    required String email,
    required String token,
  }) {
    return _client.auth
        .verifyOTP(
          type: OtpType.signup,
          email: email.trim(),
          token: token.trim(),
        )
        .timeout(NetGuard.auth);
  }

  // --- Phone OTP (SMS) ------------------------------------------------------
  //
  // Passwordless phone sign-in. Requires an SMS provider (Twilio / MessageBird /
  // Vonage …) enabled under Authentication → Providers → Phone in the Supabase
  // dashboard; the client code below is provider-agnostic. Supabase creates the
  // auth user on first successful verify, so a phone login yields the SAME
  // account system + session as email / Google - routing, SessionReset and
  // logout all work identically.

  /// Sends a 6-digit SMS code to [phone] (E.164 format, e.g. `+919876543210`).
  ///
  /// [shouldCreateUser] must be false on the login path - see [sendEmailOtp].
  Future<void> sendPhoneOtp(
    String phone, {
    Map<String, dynamic>? data,
    bool shouldCreateUser = true,
  }) {
    return _client.auth
        .signInWithOtp(
          phone: phone.trim(),
          data: data,
          shouldCreateUser: shouldCreateUser,
        )
        .timeout(NetGuard.auth);
  }

  /// Verifies the SMS [token] for [phone]. On success the returned
  /// [AuthResponse] carries an authenticated session (same shape as the Google
  /// and email paths), so callers route through [routeAfterAuth].
  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) {
    return _client.auth
        .verifyOTP(
          type: OtpType.sms,
          phone: phone.trim(),
          token: token.trim(),
        )
        .timeout(NetGuard.auth);
  }

  // --- One account, two identifiers ----------------------------------------
  //
  // Supabase keys an account by email OR phone, so an account is only reachable
  // by an identifier that is actually attached to its auth user. Signup
  // therefore confirms BOTH: the first channel mints the user, then [linkPhone]
  // / [verifyPhoneLink] (or [linkEmail] / [verifyEmailLink]) attach and confirm
  // the second. After that either one signs the same person in.

  /// Whether a confirmed account already owns [identifier] (email or phone).
  ///
  /// Backed by the `account_exists` SECURITY DEFINER function, because anon
  /// cannot read `auth.users` directly. The login screen calls this BEFORE
  /// asking for a code, so an unknown identifier is told to sign up instead of
  /// silently getting an account created for it.
  ///
  /// Fails closed: if the lookup itself errors (offline, function missing) it
  /// rethrows, because treating "we could not check" as "no account" would send
  /// an existing user to the signup form.
  Future<bool> accountExists(String identifier) async {
    final result = await _client
        .rpc<dynamic>('account_exists', params: {'p_identifier': identifier.trim()})
        .timeout(NetGuard.auth);
    return result == true;
  }

  /// Whether [identifier] is already on ANY account - as a login credential in
  /// `auth.users`, or merely as contact detail on a `public.users` profile.
  ///
  /// This is the SIGNUP check. [accountExists] is the LOGIN check and asks a
  /// narrower question ("can Supabase send a code here?"); using that one here
  /// would let a second person claim an email that is already sitting on
  /// someone's profile, and the duplicate would only surface as a failed
  /// profile INSERT after the code was verified.
  ///
  /// Fails closed, like [accountExists].
  Future<bool> identifierTaken(String identifier) async {
    final result = await _client
        .rpc<dynamic>('identifier_taken',
            params: {'p_identifier': identifier.trim()})
        .timeout(NetGuard.auth);
    return result == true;
  }

  /// Attaches [phone] to the CURRENT signed-in user and sends a confirmation
  /// SMS. The number is not usable for sign-in until [verifyPhoneLink] passes.
  Future<void> linkPhone(String phone) {
    return _client.auth
        .updateUser(UserAttributes(phone: phone.trim()))
        .timeout(NetGuard.auth);
  }

  /// Confirms the code from [linkPhone], completing the attachment.
  Future<AuthResponse> verifyPhoneLink({
    required String phone,
    required String token,
  }) {
    return _client.auth
        .verifyOTP(
          type: OtpType.phoneChange,
          phone: phone.trim(),
          token: token.trim(),
        )
        .timeout(NetGuard.auth);
  }

  /// Attaches [email] to the CURRENT signed-in user and sends a confirmation
  /// code. Mirror of [linkPhone] for accounts that started from a phone.
  Future<void> linkEmail(String email) {
    return _client.auth
        .updateUser(UserAttributes(email: email.trim()))
        .timeout(NetGuard.auth);
  }

  /// Confirms the code from [linkEmail], completing the attachment.
  Future<AuthResponse> verifyEmailLink({
    required String email,
    required String token,
  }) {
    return _client.auth
        .verifyOTP(
          type: OtpType.emailChange,
          email: email.trim(),
          token: token.trim(),
        )
        .timeout(NetGuard.auth);
  }

  /// Helper to convert authentication / Supabase errors into human-readable friendly messages.
  static String formatAuthError(Object error) {
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid') && (msg.contains('token') || msg.contains('otp') || msg.contains('code'))) {
        return 'The verification code entered is incorrect. Please check and try again.';
      }
      if (msg.contains('expired')) {
        return 'The verification code has expired. Please tap "Resend Code" to request a new one.';
      }
      if (msg.contains('rate limit') || msg.contains('too many requests') || msg.contains('over_email_send_rate_limit')) {
        return 'Too many attempts. Please wait a moment before requesting another code.';
      }
      if (msg.contains('user not found') ||
          msg.contains('signups not allowed') ||
          msg.contains('signup_disabled')) {
        return 'No account found with these details. Please create an account first.';
      }
      if (msg.contains('already been registered') ||
          msg.contains('already registered') ||
          msg.contains('already exists')) {
        return 'That email or mobile number is already on another INO account.';
      }
      if (msg.contains('network') || msg.contains('connection')) {
        return 'Unable to connect. Please check your internet connection and try again.';
      }
      return error.message;
    }
    if (error is TimeoutException) {
      return 'The connection timed out. Please check your internet connection and try again.';
    }
    // Database-side failures reach the login screen too, because the flow calls
    // the `account_exists` RPC before it asks for a code. These used to fall
    // through to the generic message below, which made a missing migration
    // indistinguishable from a real outage - so name them.
    if (error is PostgrestException) {
      final code = error.code ?? '';
      final msg = error.message.toLowerCase();
      if (code == 'PGRST202' ||
          code == '42883' ||
          msg.contains('could not find the function') ||
          msg.contains('does not exist')) {
        return 'Login is not set up on the server yet: the account_exists '
            'function is missing. Run the single_account_identity migration in '
            'Supabase, then try again.';
      }
      if (code == '42501' || msg.contains('permission denied')) {
        return 'The server refused the account lookup. Grant execute on '
            'account_exists to anon and authenticated, then try again.';
      }
      developer.log(
        'Postgrest failure during auth: code=$code message=${error.message} '
        'hint=${error.hint}',
        name: 'auth',
      );
      return 'The server rejected that request (${code.isEmpty ? 'no code' : code}). '
          'Please try again.';
    }
    // Transport failures. Matched without importing dart:io, so this file stays
    // compilable for web.
    final text = error.toString().toLowerCase();
    if (error is ClientException ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable')) {
      return 'Unable to connect. Please check your internet connection and try again.';
    }
    developer.log('Unhandled auth error: ${error.runtimeType} - $error',
        name: 'auth');
    return 'An unexpected error occurred. Please try again.';
  }

  // --- Apple (placeholder) --------------------------------------------------

  /// Whether "Continue with Apple" should be offered. Apple requires iOS +
  /// the `sign_in_with_apple` package, which isn't wired yet - so this returns
  /// false for now and the UI hides the button outside iOS.
  bool get isAppleSignInAvailable => false;

  // --- Google (native account picker) --------------------------------------

  bool _googleReady = false;
  String? _lastNonce;

  Future<void> _ensureGoogleInitialized({String? nonce}) async {
    if (_googleReady && nonce == _lastNonce) return;
    await GoogleSignIn.instance.initialize(
      // clientId is needed on iOS/web; on Android it's null (the SHA-1 +
      // serverClientId combination is what authenticates the app there).
      clientId: _platformClientId,
      serverClientId: SupabaseConfig.googleWebClientId,
      nonce: nonce,
    );
    _googleReady = true;
    _lastNonce = nonce;
  }

  String? get _platformClientId {
    if (kIsWeb) return SupabaseConfig.googleWebClientId;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return SupabaseConfig.googleIosClientId;
    }
    return null; // Android
  }

  /// Triggers the native Google account picker and exchanges the resulting
  /// ID token for a Supabase session.
  ///
  /// Returns `null` if the user cancels the picker; throws on real errors
  /// (surfaced to the caller for a snackbar). Emits step-by-step logs under the
  /// `auth` name so an on-device run is diagnosable.
  Future<AuthResponse?> signInWithGoogle() async {
    developer.log('Google sign-in started', name: 'auth');

    // Fail loudly (not silently) when the Google Web client ID is still the
    // placeholder - otherwise Credential Manager can't mint a valid token and
    // the failure is cryptic.
    if (!SupabaseConfig.isGoogleConfigured) {
      developer.log('Google sign-in aborted: web client ID not configured',
          name: 'auth');
      throw const AuthException(
        'Google Sign-In is not configured yet. Add your Google Web client ID '
        'in SupabaseConfig.',
      );
    }

    final rawNonce = _client.auth.generateRawNonce();
    final bytes = utf8.encode(rawNonce);
    final hashedNonce = sha256.convert(bytes).toString();

    await _ensureGoogleInitialized(nonce: hashedNonce);

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );
    } on GoogleSignInException catch (e) {
      developer.log(
        'Google sign-in picker result: code=${e.code} description=${e.description} details=${e.details}',
        name: 'auth',
        error: e,
      );
      if (e.code == GoogleSignInExceptionCode.canceled && (e.description == null || e.description!.isEmpty)) {
        return null;
      }
      rethrow;
    }
    SecureLogger.sensitive('Google account selected', googleUser.email, name: 'auth');

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      developer.log('Google sign-in returned no ID token', name: 'auth');
      throw const AuthException('Google sign-in did not return an ID token.');
    }

    // An access token is optional for Supabase but lets it call Google APIs
    // on the user's behalf if you ever need to.
    String? accessToken;
    try {
      final authorization = await googleUser.authorizationClient
          .authorizationForScopes(const ['email', 'profile']);
      accessToken = authorization?.accessToken;
    } catch (_) {
      // Non-fatal: proceed with just the ID token.
    }

    developer.log('Exchanging Google ID token for a Supabase session with nonce',
        name: 'auth');
    // Time-capped: the token exchange is a plain server round-trip, and a hang
    // here left the user staring at the picker's afterglow with no error.
    // (The Google picker itself is user-driven UI and is deliberately NOT
    // timed - people legitimately take minutes to choose an account.)
    final res = await _client.auth
        .signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
          nonce: rawNonce,
        )
        .timeout(NetGuard.auth);
    developer.log(
      'Supabase session received: user=${res.user?.id} '
      'session=${res.session != null}',
      name: 'auth',
    );
    return res;
  }

  // --- Sign out -------------------------------------------------------------

  Future<void> signOut() async {
    // Drop the biometric app-lock so the login screen isn't gated behind it.
    try {
      await BiometricService.instance
          .setLockEnabled(false)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    try {
      await GoogleSignIn.instance
          .signOut()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Ignore if Google wasn't used / not initialised.
    }

    // Release this device's push token BEFORE the session ends. The DELETE is
    // authorised by an RLS policy on auth.uid(), so once signOut() has run the
    // row can no longer be removed - and this phone would keep receiving THIS
    // account's reminder pushes after the next account signs in. Ordering here
    // is the whole point; do not move this below the signOut.
    try {
      await PushService.instance
          .unregisterToken()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    // An explicit logout removes this account from the device's saved-accounts
    // list too - its refresh token is revoked by the signOut below, so the
    // entry could never re-open a session anyway.
    try {
      await AccountSwitcher.instance
          .forgetCurrent()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    try {
      await _client.auth.signOut().timeout(const Duration(seconds: 3));
    } catch (e) {
      developer.log('Supabase signOut error: $e', name: 'auth');
    }

    // Wipe every user-scoped in-memory / local cache so the NEXT account can't
    // see this account's reminders, notifications, categories, etc. Done after
    // the Supabase sign-out so nothing re-hydrates from the old session. See
    // [SessionReset]. Best-effort: never let a cache failure block sign-out.
    try {
      await SessionReset.instance.clear().timeout(const Duration(seconds: 3));
    } catch (e) {
      developer.log('SessionReset clear error: $e', name: 'auth');
    }
  }
}
