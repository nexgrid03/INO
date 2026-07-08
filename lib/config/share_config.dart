import 'supabase_config.dart';

/// Configuration for Secure Document Sharing.
///
/// There are TWO base URLs, on purpose:
///   • [publicBase] — the Google-Drive-style link the QR encodes and the user
///     shares, e.g. `https://ino-share-web.vercel.app/s/<token>`. This is served
///     by the INO share web frontend (Next.js on Vercel), which renders a real
///     page (Supabase's shared functions domain can't — it downgrades HTML).
///     ⚠️ This MUST match your deployed Vercel URL (or custom domain).
///   • [apiBase] — the Supabase `share` Edge Function, e.g.
///     `https://<ref>.functions.supabase.co/share`. The APP talks to this
///     directly for JSON metadata + proxied file bytes (the web frontend talks
///     to it server-side). Derived from [SupabaseConfig.url] so it follows the
///     project automatically.
class ShareConfig {
  ShareConfig._();

  /// Public share link base (no trailing slash). Point this at your deployed
  /// share web frontend. Change here → every new QR/link follows.
  ///
  /// Set to your live Vercel deployment. Use a custom domain instead if/when you
  /// add one in Vercel (e.g. 'https://share.inoapp.in/s').
  static const String publicBase = 'https://ino-share-web.vercel.app/s';

  static String get _projectRef => Uri.parse(SupabaseConfig.url).host.split('.').first;

  /// The Supabase `share` Edge Function base.
  static String get apiBase => 'https://$_projectRef.functions.supabase.co/share';

  /// The public, shareable URL for a share [token] (what the QR encodes).
  static String publicUrl(String token) => '$publicBase/$token';

  /// The Edge Function URL for a share [token] (app-side JSON/bytes fetch).
  static String apiUrl(String token) => '$apiBase/$token';
}
