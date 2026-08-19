import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A global singleton holding a cached reference to [SharedPreferences].
/// Initialized once during app startup in `main()` to prevent repeated
/// platform-channel IPC calls.
class SharedPrefsCache {
  SharedPrefsCache._();
  static SharedPrefsCache? _instance;
  static SharedPrefsCache get instance => _instance ??= SharedPrefsCache._();

  SharedPreferences? _prefs;

  bool get isInitialized => _prefs != null;

  /// Call once during app startup in `main()` before `runApp()`.
  static Future<SharedPreferences> init() async {
    final cache = SharedPrefsCache.instance;
    cache._prefs ??= await SharedPreferences.getInstance();
    return cache._prefs!;
  }

  /// Synchronously returns the cached [SharedPreferences] instance.
  SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) {
      throw StateError('SharedPrefsCache.init() must be called before accessing prefs.');
    }
    return p;
  }

  /// Asynchronous getter that returns the cached instance or falls back to
  /// `SharedPreferences.getInstance()` (e.g. unit tests).
  Future<SharedPreferences> get prefsAsync async {
    final p = _prefs;
    if (p != null) return p;
    return await SharedPreferences.getInstance();
  }

  @visibleForTesting
  static void resetForTesting() {
    SharedPrefsCache.instance._prefs = null;
  }
}
