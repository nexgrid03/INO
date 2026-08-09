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

  /// Default cap for list queries. Nothing in the UI pages yet, so this is a
  /// safety ceiling, not pagination: generous enough that a normal account
  /// never notices, small enough that a runaway table can't OOM the client.
  static const int maxRows = 500;

  /// Cap for high-volume tables (transactions) where 500 is plausibly reached.
  static const int maxRowsLarge = 1000;
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
