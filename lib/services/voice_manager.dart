import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

void _log(String message) => developer.log(message, name: 'voice');

/// The app's centralized voice output manager — the ONE owner of the ONE
/// [FlutterTts] instance. Every spoken phrase (welcome greeting, "Opening …"
/// navigation confirmations) goes through [speak]; no screen or service may
/// construct its own FlutterTts.
///
/// WHY THIS EXISTS — duplicate speech. Two bugs shared the same shape:
///
///  1. The greeting double-play: two separate FlutterTts instances + speaking
///     on the shell's very first frame, while the native Android TextToSpeech
///     service was still binding. In that cold-start window the flutter_tts
///     Android plugin suspends the call and, if the engine connection isn't
///     usable, re-creates the engine and RE-QUEUES the whole `speak` to run
///     again after init (FlutterTtsPlugin.onMethodCall → `pendingMethodCalls`)
///     — an utterance the engine had already accepted could replay.
///
///  2. The "Opening …" double-play: a stale speech-recognizer callback
///     re-triggering the confirmation after the voice session was already
///     resolved (fixed at the source in VoiceNavigationService, with the
///     guards here as the last line of defense).
///
/// Protections, in order:
///  • warmed up at app start ([warmUp] from `main()`), so the native engine is
///    initialized and stable before anything speaks;
///  • [speak] always waits for initialization before dispatching;
///  • a repeat of the SAME text inside [_dedupeWindow] is dropped — even
///    across separate speak() calls ("[VOICE] Duplicate Ignored");
///  • an in-flight guard ([isSpeaking] + [_speakingText]) drops a duplicate
///    request for the utterance currently being spoken;
///  • `awaitSpeakCompletion` is enabled so the engine knows exactly when an
///    utterance finishes (no overlapping speech requests);
///  • flush queue mode: a new utterance replaces the current one instead of
///    being appended (also lets us avoid the stop()+speak() pair — a known
///    trigger for the Android engine playing a single utterance twice).
///
/// Lifecycle: speech stops when the app goes to background and the native
/// engine is released when the app is detached (proper resource disposal).
class VoiceManager with WidgetsBindingObserver {
  VoiceManager._();
  static final VoiceManager instance = VoiceManager._();

  FlutterTts? _tts;
  Future<bool>? _initFuture;
  bool _observing = false;
  bool _disposed = false;

  /// The utterance currently being spoken (null when idle). Used to drop
  /// duplicate speak requests for the same text.
  String? _speakingText;

  /// True while an utterance is being spoken (speak() in flight).
  bool get isSpeaking => _speakingText != null;

  /// The last utterance dispatched and when. A repeat of the SAME text inside
  /// [_dedupeWindow] is dropped even if the first has already finished — this
  /// is what stops a voice-navigation confirmation ("Opening …") from being
  /// heard twice when a duplicate speak slips past the in-flight guard above
  /// (e.g. a second dispatch arriving just after the first utterance completed).
  String? _lastText;
  DateTime? _lastAt;
  static const Duration _dedupeWindow = Duration(milliseconds: 1500);

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
      // Flush queue mode: a new utterance replaces the current one instead of
      // being appended. This is also what lets us drop the explicit stop()
      // before speak() (see speak()) — the stop()+speak() pair is a known
      // trigger for the Android engine playing a single utterance twice.
      await tts.setQueueMode(0);
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5); // comfortable, natural pace
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      if (!kIsWeb && Platform.isIOS) {
        // Ambient category = app speech obeys the physical Ring/Silent switch
        // (the playsInSilentModeIOS:false behaviour) and mixes politely with
        // other audio instead of interrupting it.
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.ambient,
          [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
        );
      }
      _tts = tts;
      if (!_observing) {
        _observing = true;
        WidgetsBinding.instance.addObserver(this);
      }
      _log('[VOICE] TTS initialized');
      debugPrint('[VOICE] TTS initialized');
      return true;
    } catch (e) {
      // Non-fatal — a device without TTS should never break the app.
      _log('[VOICE] TTS initialization failed (non-fatal): $e');
      _initFuture = null; // allow a later retry
      return false;
    }
  }

  /// Speaks [text], replacing any different utterance in progress. A request
  /// for the SAME text that is currently being spoken — or dispatched within
  /// the last [_dedupeWindow] — is ignored, so no phrase can ever double-play.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    // Drop a repeat of the same phrase within the dedupe window — before the
    // init await, so a duplicate that arrives while initializing is caught too.
    final now = DateTime.now();
    if (_lastText == text &&
        _lastAt != null &&
        now.difference(_lastAt!) < _dedupeWindow) {
      _log('[VOICE] Duplicate Ignored (within window): "$text"');
      debugPrint('[VOICE] Duplicate Ignored (within window): "$text"');
      return;
    }
    _lastText = text;
    _lastAt = now;

    if (!await _ensureInitialized()) return;
    final tts = _tts;
    if (tts == null) return;

    if (_speakingText == text) {
      _log('[VOICE] Duplicate Ignored (already speaking): "$text"');
      debugPrint('[VOICE] Duplicate Ignored (already speaking): "$text"');
      return;
    }

    _speakingText = text;
    try {
      // No stop() here on purpose: with flush queue mode, speak() already
      // replaces any current utterance, and a stop()+speak() pair can make the
      // Android engine speak the same text twice.
      _log('[VOICE] Speaking Started: "$text"');
      debugPrint('[VOICE] Speaking Started: "$text"');
      await tts.speak(text); // resolves on completion (awaitSpeakCompletion)
      _log('[VOICE] Speaking Completed: "$text"');
      debugPrint('[VOICE] Speaking Completed: "$text"');
    } catch (e) {
      _log('[VOICE] TTS speak failed (non-fatal): $e');
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
    _log('[VOICE] TTS disposed');
    debugPrint('[VOICE] TTS disposed');
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
    _lastText = null;
    _lastAt = null;
    _disposed = false;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}
