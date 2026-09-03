import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight, rock-solid connectivity checker.
/// Tests actual internet reachability (DNS lookup) with low timeouts,
/// preventing screens from hanging on unresponsive connections.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  Future<bool>? _inFlight;

  /// Checks if internet connectivity is currently available.
  ///
  /// Concurrent callers share one probe: the splash, a lifecycle resume and a
  /// manual "retry" tap can all land at once, and three simultaneous DNS
  /// lookups would each pay the full [timeout] on a dead link.
  Future<bool> checkOnline({
    Duration timeout = const Duration(milliseconds: 2500),
  }) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final probe = _probe(timeout);
    _inFlight = probe;
    return probe.whenComplete(() {
      if (_inFlight == probe) _inFlight = null;
    });
  }

  Future<bool> _probe(Duration timeout) async {
    if (kIsWeb) {
      isOnline.value = true;
      return true;
    }
    try {
      final lookup = await InternetAddress.lookup('google.com').timeout(timeout);
      final ok = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      isOnline.value = ok;
      return ok;
    } catch (_) {
      try {
        final backup = await InternetAddress.lookup('1.1.1.1').timeout(timeout);
        final ok = backup.isNotEmpty && backup[0].rawAddress.isNotEmpty;
        isOnline.value = ok;
        return ok;
      } catch (_) {
        isOnline.value = false;
        return false;
      }
    }
  }
}
