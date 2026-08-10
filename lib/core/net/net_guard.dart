import 'package:http/http.dart' as http;

/// Central network-resilience knobs for every Supabase / HTTP call the app
/// makes.
///
/// Before this existed, core queries had no timeout at all: on a throttled or
/// dying connection a request could hang forever, leaving screens stuck on a
/// spinner and futures that never complete. Every repository now caps its calls
/// with these durations, and list queries cap their row counts with these
/// limits so a vault that grew to thousands of rows can no longer produce
/// unbounded payloads.
class NetGuard {
  NetGuard._();

  /// Read queries (selects, signed-URL mints, RPC reads).
  static const Duration query = Duration(seconds: 15);

  /// Writes (insert / update / delete / RPC mutations).
  static const Duration mutation = Duration(seconds: 25);

  /// Auth round-trips (sign-in, OTP, token exchange).
  static const Duration auth = Duration(seconds: 25);

  /// Storage transfers (file upload / download). Generous on purpose: a large
  /// PDF on a slow link is legitimate, only a genuine hang should trip this.
  static const Duration storage = Duration(minutes: 3);

  /// Cap for list queries whose row count is bounded by construction (the
  /// wallet registry, one vault's members, a share's recipients). These cannot
  /// grow with a user's own data, so a ceiling is honest here.
  ///
  /// Lists that DO grow with user data page through [fetchAllPaged] instead -
  /// a bare `.limit()` on those silently hides rows past the cap.
  static const int maxRows = 500;

  /// Cap for bounded high-volume tables where 500 is plausibly reached.
  static const int maxRowsLarge = 1000;

  /// Rows per request when paging. Small enough that any single response stays
  /// modest on a slow link, large enough that a normal account finishes in one
  /// or two round trips.
  static const int pageSize = 200;

  /// Runaway backstop for a paged fetch. Not a product limit - reaching it is
  /// logged, because it means an account is far outside expected size.
  static const int hardMaxRows = 10000;
}

/// An [http.Client] that bounds how long any single request may take to start
/// answering. Installed as the Supabase client's transport in `main.dart`, so
/// even SDK-internal traffic (token refresh, realtime auth) can't hang forever.
///
/// The timeout covers connect + request upload + response headers; body
/// streaming is bounded by the per-call timeouts in the repositories.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(this._inner, {this.sendTimeout = const Duration(seconds: 90)});

  final http.Client _inner;
  final Duration sendTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(sendTimeout);

  @override
  void close() => _inner.close();
}
