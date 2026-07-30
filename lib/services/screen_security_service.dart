import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/services.dart';

/// Screen-capture protection for sensitive content (currently: view-once
/// documents).
///
/// Implemented as a tiny MethodChannel against code already in `MainActivity.kt`
/// / `AppDelegate.swift` rather than a plugin, so it adds no dependency to the
/// build graph.
///
/// **What you actually get, per platform:**
///
/// * **Android** - real protection. [enable] sets `WindowManager.LayoutParams
///   .FLAG_SECURE` on the activity window, which makes the OS refuse
///   screenshots, blanks the window in screen recordings and the recents
///   thumbnail, and blocks casting to non-secure displays. This is enforced by
///   the system, not by the app.
///
/// * **iOS - screenshots CANNOT be blocked.** There is no public API for it; any
///   library claiming otherwise either fails or risks App Store rejection. What
///   [enable] does instead is the best iOS genuinely allows:
///     1. hides the content behind an opaque cover while the app is in the app
///        switcher / backgrounded, so it never appears in the task snapshot;
///     2. reports **screen recording / AirPlay mirroring** live via
///        [captureDetected] (`UIScreen.isCaptured`) so the app can hide the
///        document while capture is active;
///     3. reports **after-the-fact screenshots** via [screenshotTaken] so the UI
///        can react (INO closes the view-once document and tells the sender's
///        link it has been spent - which it already is).
///   The real protection on iOS is the one-time token itself: even a screenshot
///   only ever captures a document the recipient was already authorised to see
///   once, and the link is dead the moment it opens.
///
/// Everything degrades silently: on desktop/web, an old OS, or a missing
/// handler, calls are no-ops rather than crashes.
class ScreenSecurityService {
  ScreenSecurityService._();
  static final ScreenSecurityService instance = ScreenSecurityService._();

  static const MethodChannel _channel = MethodChannel('ino/secure_screen');

  bool _wired = false;

  /// How many screens currently want protection. Reference-counted so a nested
  /// push/pop can't disable protection while an outer secure screen is still up.
  int _holds = 0;

  /// True while the OS-level secure flag is (or is meant to be) on.
  bool get isProtected => _holds > 0;

  /// Fires each time the user takes a screenshot while protection is on.
  ///
  /// **iOS only in practice** - on Android the screenshot never happens, so
  /// there is nothing to report.
  final ValueNotifier<int> screenshotTaken = ValueNotifier<int>(0);

  /// True while the screen is being recorded or mirrored (iOS
  /// `UIScreen.isCaptured`). Always false on Android, where FLAG_SECURE already
  /// blanks the capture.
  final ValueNotifier<bool> captureDetected = ValueNotifier<bool>(false);

  /// Only Android and iOS have a native handler; everywhere else every call is
  /// a silent no-op.
  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'screenshotTaken':
          developer.log('screenshot detected', name: 'secure-screen');
          screenshotTaken.value++;
          break;
        case 'captureChanged':
          final captured = call.arguments == true;
          developer.log('screen capture active=$captured', name: 'secure-screen');
          captureDetected.value = captured;
          break;
      }
      return null;
    });
  }

  /// Turns on screen-capture protection. Safe to call more than once - calls are
  /// reference-counted, so [disable] only lifts protection once every holder has
  /// released it.
  ///
  /// Never throws: a platform without support just returns false.
  Future<bool> enable() async {
    if (!_supported) return false;
    _wire();
    _holds++;
    if (_holds > 1) return true; // already on
    try {
      final ok = await _channel.invokeMethod<bool>('enable');
      developer.log('secure screen ENABLED (native=$ok)', name: 'secure-screen');
      return ok ?? false;
    } on PlatformException catch (e) {
      developer.log('enable failed: ${e.message}', name: 'secure-screen');
      return false;
    } on MissingPluginException {
      // Native side not present (e.g. a widget test) - not an error.
      return false;
    }
  }

  /// Releases one hold on protection, clearing the OS flag when the last one
  /// goes. Never throws.
  Future<void> disable() async {
    if (!_supported) return;
    if (_holds == 0) return;
    _holds--;
    if (_holds > 0) return; // another secure screen is still up
    captureDetected.value = false;
    try {
      await _channel.invokeMethod<bool>('disable');
      developer.log('secure screen DISABLED', name: 'secure-screen');
    } on PlatformException catch (e) {
      developer.log('disable failed: ${e.message}', name: 'secure-screen');
    } on MissingPluginException {
      /* no native side - nothing to undo */
    }
  }

  /// Whether the screen is being recorded/mirrored right now (iOS). Returns
  /// false on Android and wherever the check isn't available.
  Future<bool> isBeingCaptured() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isCaptured') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True when the platform can genuinely BLOCK screen capture (Android only).
  /// The UI uses this to tell the user the truth instead of implying iOS
  /// screenshots are prevented.
  bool get canBlockCapture => _supported && Platform.isAndroid;
}
