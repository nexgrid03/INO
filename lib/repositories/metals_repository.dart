import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/metal_rates.dart';
import '../services/metals_api_service.dart';

/// The outcome of a rates request, carrying provenance for the UI.
@immutable
class MetalRatesResult {
  const MetalRatesResult({
    required this.rates,
    required this.fromCache,
    required this.isOffline,
  });

  final MetalRates rates;

  /// Served from the local cache rather than a fresh network hit.
  final bool fromCache;

  /// The network failed and we fell back to the last-known values.
  final bool isOffline;
}

/// Caches live metal rates on-device (SharedPreferences) and enforces the
/// 15-minute refresh policy, so repeated screen opens never hit the network.
///
/// Policy: return the cache while it is younger than [cacheTtl]; otherwise
/// fetch live and update the cache. If a live fetch fails but a cached value
/// exists, return the cache flagged `isOffline` (never crash). If it fails and
/// there is no cache at all, the [MetalsException] propagates.
class MetalsRepository {
  MetalsRepository({
    MetalsApiService? api,
    this.cacheTtl = const Duration(minutes: 15),
  }) : _api = api ?? MetalsApiService();

  final MetalsApiService _api;
  final Duration cacheTtl;

  static const _cacheKey = 'metal_rates_cache_v1';

  /// Fast in-RAM copy so repeated reads in a session skip disk entirely.
  MetalRates? _memory;

  /// Returns cached rates when fresh (< [cacheTtl]) unless [forceRefresh];
  /// otherwise fetches live, updating the cache. Falls back to cache on error.
  Future<MetalRatesResult> getRates({bool forceRefresh = false}) async {
    final cached = await _readCache();

    if (!forceRefresh && cached != null && _isFresh(cached)) {
      _log('cache HIT (age ${_age(cached).inSeconds}s)');
      return MetalRatesResult(rates: cached, fromCache: true, isOffline: false);
    }
    _log(forceRefresh ? 'manual refresh → fetching' : 'cache MISS → fetching');

    try {
      final started = DateTime.now();
      final fresh = await _api.fetchLatestRates();
      await _writeCache(fresh);
      _log('refreshed in ${DateTime.now().difference(started).inMilliseconds}ms');
      return MetalRatesResult(rates: fresh, fromCache: false, isOffline: false);
    } on MetalsException catch (e) {
      if (cached != null) {
        _log('fetch failed (${e.type}) → serving cached (offline)');
        return MetalRatesResult(
          rates: cached,
          fromCache: true,
          isOffline: true,
        );
      }
      _log('fetch failed (${e.type}) and no cache → rethrow');
      rethrow;
    }
  }

  /// The last cached value (no network). Null if nothing has been cached yet.
  Future<MetalRates?> peekCache() => _readCache();

  /// Age of a cached snapshot relative to now.
  Duration ageOf(MetalRates rates) => _age(rates);

  bool _isFresh(MetalRates rates) => _age(rates) < cacheTtl;

  Duration _age(MetalRates rates) =>
      DateTime.now().toUtc().difference(rates.timestamp.toUtc());

  Future<MetalRates?> _readCache() async {
    if (_memory != null) return _memory;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      _memory = MetalRates.decode(raw);
      return _memory;
    } catch (_) {
      await prefs.remove(_cacheKey); // corrupt entry — drop it
      return null;
    }
  }

  Future<void> _writeCache(MetalRates rates) async {
    _memory = rates;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, rates.encode());
  }

  void _log(String message) => debugPrint('[Metals·Repo] $message');
}
