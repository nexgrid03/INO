import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

void _log(String message) => developer.log(message, name: 'tts');

/// The app's single shared text-to-speech engine.
///
/// WHY THIS EXISTS — the "greeting plays twice" bug. The app used to hold TWO
/// separate [FlutterTts] instances (voice greeting + voice navigation), and the
/// greeting spoke on the very first frame of the shell, while the native
/// Android TextToSpeech service was still binding. In that cold-start window
/// the flutter_tts Android plugin suspends the method call and, if the engine
/// connection isn't usable yet, re-creates the engine and RE-QUEUES the whole
/// `speak` call to run again after init (see FlutterTtsPlugin.onMethodCall →
/// `pendingMethodCalls`) — so an utterance the engine had already accepted
/// could be replayed, and the user heard "Good Morning, …" twice.
///
/// This engine removes that window:
///  • ONE FlutterTts instance for the whole app (greeting + navigation),
///  • it is warmed up at app start ([warmUp] from `main()`), so by the time
///    anything speaks, the native engine is initialized and stable,
///  • `speak` always waits for initialization before dispatching,
///  • an in-flight guard drops a duplicate request for the SAME utterance
///    while it is still being spoken — the same text can never double-play,
///  • `awaitSpeakCompletion` is enabled so the engine knows exactly when an
///    utterance finishes (no overlapping speech requests).
///
/// Lifecycle: speech stops when the app goes to background and the native
/// engine is released when the app is detached (proper resource disposal).
class TtsEngine with WidgetsBindingObserver {
  TtsEngine._();
  static final TtsEngine instance = TtsEngine._();

  FlutterTts? _tts;
  Future<bool>? _initFuture;
  bool _observing = false;
  bool _disposed = false;

  /// The utterance currently being spoken (null when idle). Used to drop
  /// duplicate speak requests for the same text.
  String? _speakingText;

  /// Kicks off engine initialization without waiting for it. Called from
  /// `main()` so the native TTS service is already bound (and past its
  /// cold-start races) by the time the greeting fires.
  void warmUp() => unawaited(_ensureInitialized());

  Future<bool> _ensureInitialized() {
    if (_disposed) return Future.value(false);
    return _initFuture ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      final tts = FlutterTts();
      // Make speak() resolve when the utterance COMPLETES, so the in-flight
      // guard below reliably brackets the whole utterance.
      await tts.awaitSpeakCompletion(true);
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5); // comfortable, natural pace
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      _tts = tts;
      if (!_observing) {
        _observing = true;
        WidgetsBinding.instance.addObserver(this);
      }
      _log('TTS initialized');
      debugPrint('TTS initialized');
      return true;
    } catch (e) {
      // Non-fatal — a device without TTS should never break the app.
      _log('TTS initialization failed (non-fatal): $e');
      _initFuture = null; // allow a later retry
      return false;
    }
  }

  /// Speaks [text], replacing any different utterance in progress. A request
  /// for the SAME text that is currently being spoken is dropped — this is the
  /// belt-and-suspenders guarantee that no phrase can ever double-play.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!await _ensureInitialized()) return;
    final tts = _tts;
    if (tts == null) return;

    if (_speakingText == text) {
      _log('Duplicate speech request skipped: "$text"');
      debugPrint('Duplicate speech request skipped: "$text"');
      return;
    }

    _speakingText = text;
    try {
      await tts.stop(); // flush anything different that was still playing
      _log('Speaking: "$text"');
      await tts.speak(text); // resolves on completion (awaitSpeakCompletion)
    } catch (e) {
      _log('TTS speak failed (non-fatal): $e');
    } finally {
      if (_speakingText == text) _speakingText = null;
    }
  }

  /// Stops any utterance in progress.
  Future<void> stop() async {
    _speakingText = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  /// Releases the native engine. Safe to call more than once; a later [speak]
  /// after an explicit dispose is a no-op.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
    _tts = null;
    _initFuture = null;
    _log('TTS disposed');
    debugPrint('TTS disposed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Never keep talking from the background.
      unawaited(stop());
    } else if (state == AppLifecycleState.detached) {
      unawaited(dispose());
    }
  }

  /// Test hook: forget all engine state so a test can exercise init again.
  @visibleForTesting
  void resetForTest() {
    _tts = null;
    _initFuture = null;
    _speakingText = null;
    _disposed = false;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}
