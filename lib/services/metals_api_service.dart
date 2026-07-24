import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/metal_rates.dart';

/// Classified failure modes so callers (and the UI) can react precisely.
enum MetalsErrorType {
  noInternet,
  timeout,
  rateLimit,
  unauthorized,
  server,
  invalidResponse,
  unknown,
}

/// A typed error from the metals feed. [userMessage] is safe to show in the UI.
class MetalsException implements Exception {
  const MetalsException(this.type, this.message);

  final MetalsErrorType type;
  final String message;

  String get userMessage {
    switch (type) {
      case MetalsErrorType.noInternet:
        return 'No internet connection';
      case MetalsErrorType.timeout:
        return 'Request timed out';
      case MetalsErrorType.rateLimit:
        return 'Too many requests — try again shortly';
      case MetalsErrorType.unauthorized:
        return 'Rate service unauthorized';
      case MetalsErrorType.server:
        return 'Rate service is temporarily unavailable';
      case MetalsErrorType.invalidResponse:
        return 'Could not read the latest rates';
      case MetalsErrorType.unknown:
        return 'Could not update rates';
    }
  }

  @override
  String toString() => 'MetalsException($type): $message';
}

/// Fetches LIVE gold & silver rates and returns them as [MetalRates] in ₹/gram.
///
/// Uses two FREE, KEYLESS public endpoints (no signup, no secret to leak):
///   • Swissquote public quotes → spot USD/troy-ounce for XAU (gold) / XAG
///     (silver).
///   • frankfurter (ECB data)   → USD→INR exchange rate.
///
/// Automatically retries transient failures with a short backoff. The HTTP
/// client is injectable so the whole path is unit-testable with a mock.
class MetalsApiService {
  MetalsApiService({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.maxAttempts = 3,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maxAttempts;

  static const _spotBase =
      'https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument';
  static const _fxUrl =
      'https://api.frankfurter.dev/v1/latest?base=USD&symbols=INR';

  /// Fetches the latest gold + silver rates, retrying transient errors.
  /// Throws [MetalsException] if every attempt fails.
  Future<MetalRates> fetchLatestRates() async {
    MetalsException? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final started = DateTime.now();
      try {
        _log('request (attempt $attempt/$maxAttempts)');
        final rates = await _fetchOnce();
        final ms = DateTime.now().difference(started).inMilliseconds;
        _log(
          'response OK in ${ms}ms → '
          'gold ₹${rates.goldPerGram.toStringAsFixed(2)}/g · '
          'silver ₹${rates.silverPerGram.toStringAsFixed(2)}/g',
        );
        return rates;
      } on MetalsException catch (e) {
        last = e;
        _log('attempt $attempt failed: ${e.type} (${e.message})');
        // An auth error will not fix itself on retry — fail fast.
        if (e.type == MetalsErrorType.unauthorized) rethrow;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
    throw last ?? const MetalsException(MetalsErrorType.unknown, 'unknown');
  }

  /// One full round: spot gold, spot silver and FX in parallel, then convert.
  Future<MetalRates> _fetchOnce() async {
    final results = await Future.wait([
      _spotUsdPerOunce('XAU'),
      _spotUsdPerOunce('XAG'),
      _usdToInr(),
    ]);
    final gold = results[0];
    final silver = results[1];
    final fx = results[2];
    if (gold == null || silver == null || fx == null) {
      throw const MetalsException(
        MetalsErrorType.invalidResponse,
        'missing gold/silver/fx value',
      );
    }
    return MetalRates.fromSpot(
      goldUsdPerOunce: gold,
      silverUsdPerOunce: silver,
      usdToInr: fx,
      timestamp: DateTime.now().toUtc(),
      source: 'swissquote + frankfurter',
    );
  }

  Future<double?> _spotUsdPerOunce(String symbol) async {
    final res = await _get(
      '$_spotBase/$symbol/USD',
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );
    return parseSpotUsdPerOunce(res.body);
  }

  Future<double?> _usdToInr() async {
    final res = await _get(_fxUrl);
    return parseUsdInr(res.body);
  }

  /// GET with status-code → [MetalsException] mapping and network guards.
  Future<http.Response> _get(String url, {Map<String, String>? headers}) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);
      final code = res.statusCode;
      if (code == 200) return res;
      if (code == 429) {
        throw const MetalsException(MetalsErrorType.rateLimit, 'HTTP 429');
      }
      if (code == 401 || code == 403) {
        throw MetalsException(MetalsErrorType.unauthorized, 'HTTP $code');
      }
      if (code >= 500) {
        throw MetalsException(MetalsErrorType.server, 'HTTP $code');
      }
      throw MetalsException(MetalsErrorType.invalidResponse, 'HTTP $code');
    } on SocketException catch (e) {
      throw MetalsException(MetalsErrorType.noInternet, e.message);
    } on TimeoutException {
      throw const MetalsException(MetalsErrorType.timeout, 'timed out');
    } on http.ClientException catch (e) {
      throw MetalsException(MetalsErrorType.noInternet, e.message);
    }
  }

  // --- Pure parse helpers (unit-tested directly) ---------------------------

  /// Extracts the mid spot price from a Swissquote quotes payload, or null.
  static double? parseSpotUsdPerOunce(String body) {
    try {
      final list = jsonDecode(body) as List<dynamic>;
      if (list.isEmpty) return null;
      final prices =
          (list.first as Map<String, dynamic>)['spreadProfilePrices']
              as List<dynamic>?;
      if (prices == null || prices.isEmpty) return null;
      final p = prices.first as Map<String, dynamic>;
      final bid = (p['bid'] as num?)?.toDouble();
      final ask = (p['ask'] as num?)?.toDouble();
      if (bid == null || ask == null || bid <= 0) return null;
      return (bid + ask) / 2; // mid price
    } catch (_) {
      return null;
    }
  }

  /// Extracts the USD→INR rate from a frankfurter payload, or null.
  static double? parseUsdInr(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final rate =
          ((json['rates'] as Map<String, dynamic>?)?['INR'] as num?)?.toDouble();
      return (rate != null && rate > 0) ? rate : null;
    } catch (_) {
      return null;
    }
  }

  void _log(String message) => debugPrint('[Metals·API] $message');

  /// Closes the underlying client. (The app-wide singleton never disposes.)
  void dispose() => _client.close();
}
