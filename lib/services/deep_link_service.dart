import 'dart:async';
import 'dart:developer' as developer;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/share/shared_documents_screen.dart';

/// Handles incoming share deep links (Android App Links + the `ino://` scheme)
/// and routes them to [SharedDocumentsScreen].
///
/// Two entry paths, so it works whether the app was **closed, backgrounded or
/// foregrounded**:
///   • **Cold start** — [captureInitialLink] runs in `main()` before the first
///     frame and records the launch URL's share id in [initialShareId]. The app
///     root shows [SharedDocumentsScreen] directly for that id (so the splash's
///     own navigation can't clobber it).
///   • **Warm** (background→foreground, or already running) — [startListening]
///     subscribes to the link stream and pushes [SharedDocumentsScreen] onto the
///     live navigator.
///
/// The share id is extracted from the URL path (`…/share/<share_id>`), so no
/// Supabase ids or internals are needed. Every step is logged under `deeplink`.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<Uri>? _sub;

  String? _initialShareId;
  String? _initialLinkStr; // to skip the one-time stream replay of the launch link

  /// The share id the app was cold-launched with (null for a normal launch).
  String? get initialShareId => _initialShareId;

  /// Captures the cold-start launch link. Call in `main()` before `runApp`.
  /// Never throws — a failure just means "no initial deep link".
  Future<void> captureInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      _initialLinkStr = uri?.toString();
      _initialShareId = parseShareId(uri);
      developer.log(
        'captureInitialLink → incoming=${uri ?? '(none)'} '
        'shareId=${_initialShareId ?? '(none)'}',
        name: 'deeplink',
      );
    } catch (e, st) {
      developer.log('captureInitialLink failed: $e',
          name: 'deeplink', error: e, stackTrace: st);
    }
  }

  /// Starts listening for links received while the app is running (warm), and
  /// remembers the [navigatorKey] used to present the viewer. Idempotent, and
  /// resilient to a missing platform plugin (e.g. under `flutter test`).
  void startListening(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    if (_sub != null) return;
    try {
      _sub = _appLinks.uriLinkStream.listen(
        _onStreamUri,
        onError: (Object e, StackTrace st) => developer.log(
            'uriLinkStream error: $e',
            name: 'deeplink', error: e, stackTrace: st),
      );
      developer.log('deeplink listening started', name: 'deeplink');
    } catch (e, st) {
      developer.log('deeplink startListening failed: $e',
          name: 'deeplink', error: e, stackTrace: st);
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _onStreamUri(Uri uri) {
    final str = uri.toString();
    developer.log('incoming link (warm) → $uri', name: 'deeplink');
    // The stream can replay the launch link once — it's already shown as the
    // cold-start home, so skip it a single time to avoid a duplicate screen.
    if (str == _initialLinkStr) {
      _initialLinkStr = null;
      developer.log('  skipped: replay of the launch link', name: 'deeplink');
      return;
    }
    final shareId = parseShareId(uri);
    if (shareId == null) {
      developer.log('  ignored: not a share link', name: 'deeplink');
      return;
    }
    developer.log('  extracted shareId=$shareId', name: 'deeplink');
    _navigate(shareId);
  }

  /// Pushes the viewer, retrying briefly if the navigator isn't attached yet.
  void _navigate(String shareId, {int attempt = 0}) {
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      if (attempt >= 20) {
        developer.log('navigate: navigator never became ready — giving up',
            name: 'deeplink');
        return;
      }
      Future.delayed(const Duration(milliseconds: 100),
          () => _navigate(shareId, attempt: attempt + 1));
      return;
    }
    developer.log('navigate → SharedDocumentsScreen(token=$shareId)',
        name: 'deeplink');
    nav.push(
      MaterialPageRoute(
        builder: (_) => SharedDocumentsScreen(token: shareId),
      ),
    );
  }

  /// Extracts the share token (or legacy share_id) from a deep-link [uri].
  /// Returns null when it isn't a share link.
  ///
  /// Handles every shape it can arrive in:
  ///   • `https://share.inoapp.in/s/<token>`                   → `<token>`
  ///   • `https://<ref>.functions.supabase.co/share/share_x`   → `share_x`
  ///   • `https://<ref>.functions.supabase.co/functions/v1/share/share_x` → `share_x`
  ///   • `ino://share/<token>`                                 → `<token>`
  static String? parseShareId(Uri? uri) {
    if (uri == null) return null;
    final segs = uri.pathSegments;

    // New public links: /s/<token>
    final sIdx = segs.indexOf('s');
    if (sIdx >= 0 && sIdx + 1 < segs.length && segs[sIdx + 1].isNotEmpty) {
      return segs[sIdx + 1];
    }

    // Legacy internal links: /share/<share_…>
    for (final seg in segs) {
      if (seg.startsWith('share_')) return seg;
    }

    // Custom scheme `ino://share/<token>`.
    if (uri.host == 'share' && segs.isNotEmpty && segs.first.isNotEmpty) {
      return segs.first;
    }
    return null;
  }
}
