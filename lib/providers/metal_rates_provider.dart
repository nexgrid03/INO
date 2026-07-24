import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/metal_rates.dart';
import '../repositories/metals_repository.dart';
import '../services/metals_api_service.dart';

/// High-level UI state for the live-rates widget.
enum MetalRatesStatus { idle, loading, loaded, error }

/// App-wide store for live metal rates.
///
/// A [ChangeNotifier] — the state pattern used across INO (no Riverpod) — that
/// owns the **15-minute auto-refresh timer** and a **resume-from-background**
/// refresh, so the UI just listens via [ListenableBuilder]. Fetching + caching
/// live in [MetalsRepository]; this class only maps results to view state.
///
/// Use [MetalRatesProvider.instance] in the app; construct with an injected
/// [MetalsRepository] in tests.
class MetalRatesProvider extends ChangeNotifier with WidgetsBindingObserver {
  MetalRatesProvider({MetalsRepository? repository})
    : _repo = repository ?? MetalsRepository();

  /// The shared app-wide instance (lives for the app's lifetime).
  static final MetalRatesProvider instance = MetalRatesProvider();

  final MetalsRepository _repo;

  static const Duration refreshEvery = Duration(minutes: 15);

  MetalRatesStatus _status = MetalRatesStatus.idle;
  MetalRates? _rates;
  bool _isOffline = false;
  bool _refreshing = false;
  String? _error;
  MetalsErrorType? _errorType;

  Timer? _timer;
  bool _started = false;

  // --- Public, read-only state --------------------------------------------
  MetalRatesStatus get status => _status;
  MetalRates? get rates => _rates;
  bool get hasData => _rates != null;
  bool get isOffline => _isOffline;
  bool get isRefreshing => _refreshing;
  String? get error => _error;
  MetalsErrorType? get errorType => _errorType;

  /// When the shown rates were fetched, in local time (null until first load).
  DateTime? get lastUpdated => _rates?.timestamp.toLocal();

  /// Start once (idempotent): paint from cache instantly, refresh if stale,
  /// then keep the 15-minute timer + lifecycle observer alive.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(refreshEvery, (_) => refresh());

    final cached = await _repo.peekCache();
    if (cached != null && _rates == null) {
      _rates = cached;
      _status = MetalRatesStatus.loaded;
      notifyListeners();
    }
    await refresh();
  }

  /// Fetch through the repository. [force] bypasses the freshness window
  /// (used by the manual refresh button).
  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (_rates == null) _status = MetalRatesStatus.loading;
    notifyListeners();

    try {
      final result = await _repo.getRates(forceRefresh: force);
      _rates = result.rates;
      _isOffline = result.isOffline;
      _status = MetalRatesStatus.loaded;
      _error = null;
      _errorType = null;
    } on MetalsException catch (e) {
      _errorType = e.type;
      _error = e.userMessage;
      if (_rates == null) {
        _status = MetalRatesStatus.error;
      } else {
        _isOffline = true; // keep the last-known values on screen
      }
    } catch (_) {
      _error = 'Could not update rates';
      if (_rates == null) _status = MetalRatesStatus.error;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_started) return;
    // Background refresh: only when the cache has actually gone stale.
    _repo.peekCache().then((cached) {
      final stale = cached == null || _repo.ageOf(cached) >= refreshEvery;
      if (stale) refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
