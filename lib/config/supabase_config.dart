////// Backend credentials for Supabase + Google Sign-In.
///
/// Fill these in with the values from your own dashboards (see the setup
/// guide). The Supabase anon key is safe to ship in a client app; the Google
/// **web client secret** must NEVER live here — it stays only in the Supabase
/// dashboard.
///
/// Tip: don't commit real keys to a public repo. Consider passing them with
/// `--dart-define` instead and reading via `String.fromEnvironment(...)`.
class SupabaseConfig {
  SupabaseConfig._();

  /// Project URL, e.g. https://ab544cdefgh.supabase.co
  static const String url = 'https://ilfzppryyojoponkomrw.supabase.co';

  /// Project publishable (a.k.a. "anon") public API key — safe for clients.
  /// In the Supabase dashboard: Settings → API Keys. New projects show a
  /// `sb_publishable_…` key; older ones show a legacy `anon` JWT — either works.
  static const String publishableKey =
      'sb_publishable_AkYUQB5-mxBJkY_tZQu6EQ_JprMvI97';

  /// Google OAuth **Web** client ID (the one you also paste into Supabase's
  /// Google provider settings). Used as the token audience on every platform.
  /// e.g. 1234567890-abc123.apps.googleusercontent.com
  static const String googleWebClientId = 'YOUR_GOOGLE_WEB_CLIENT_ID';

  /// Google OAuth **iOS** client ID (only needed for the iOS build).
  static const String googleIosClientId = 'YOUR_GOOGLE_IOS_CLIENT_ID';

  /// True once a real Google **Web** client ID has been supplied (i.e. it's no
  /// longer the placeholder / empty). The native Google flow uses this value as
  /// the token audience — with the placeholder, Credential Manager can't mint a
  /// valid ID token, so we detect it up-front and surface a clear error instead
  /// of failing silently.
  static bool get isGoogleConfigured =>
      googleWebClientId.isNotEmpty &&
      !googleWebClientId.startsWith('YOUR_');
}
