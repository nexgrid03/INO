import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

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
  /// being initialised — it's only touched when a method is actually called.
  SupabaseClient get _client => Supabase.instance.client;

  // --- Session helpers ------------------------------------------------------

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentSession != null;

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
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: fullName != null ? {'full_name': fullName} : null,
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sends a password-reset email.
  Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
  }

  // --- Email OTP (account verification) -------------------------------------
  //
  // Supabase can confirm a new account with a 6-digit email code instead of a
  // magic link (set the "Confirm signup" email template to use {{ .Token }}).
  // These two calls back the OTP Verification screen.

  /// Re-sends the 6-digit sign-up confirmation code to [email].
  Future<void> resendSignupOtp(String email) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
    );
  }

  /// Verifies the 6-digit sign-up code. On success the returned
  /// [AuthResponse] carries an authenticated session.
  Future<AuthResponse> verifySignupOtp({
    required String email,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email.trim(),
      token: token.trim(),
    );
  }

  // --- Apple (placeholder) --------------------------------------------------

  /// Whether "Continue with Apple" should be offered. Apple requires iOS +
  /// the `sign_in_with_apple` package, which isn't wired yet — so this returns
  /// false for now and the UI hides the button outside iOS.
  bool get isAppleSignInAvailable => false;

  // --- Google (native account picker) --------------------------------------

  bool _googleReady = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(
      // clientId is needed on iOS/web; on Android it's null (the SHA-1 +
      // serverClientId combination is what authenticates the app there).
      clientId: _platformClientId,
      serverClientId: SupabaseConfig.googleWebClientId,
    );
    _googleReady = true;
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
  /// Returns `null` if the user cancels the picker; throws on real errors.
  Future<AuthResponse?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );
    } on GoogleSignInException catch (e) {
      // Swallow user-initiated cancellation; surface everything else.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
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

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  // --- Sign out -------------------------------------------------------------

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Ignore if Google wasn't used / not initialised.
    }
    await _client.auth.signOut();
  }
}
