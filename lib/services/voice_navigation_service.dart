import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/voice_command.dart';
import '../utils/secure_logger.dart';
import 'voice_manager.dart';

void _log(String message) => SecureLogger.log(message, name: 'voice');

/// The lifecycle of one voice-command session, driving the mic sheet UI.
enum VoiceStatus {
  idle,
  initializing,
  listening,
  matched,
  noMatch,
  denied,
  unavailable,
  error,
}

/// Drives on-device speech recognition for hands-free navigation and speaks the
/// "Opening …" confirmation. UI-agnostic ([ChangeNotifier]); screens react to
/// [status] / [recognizedText] / [match].
///
/// Every stage is logged under the `voice` log name (visible in `flutter run`
/// and `adb logcat -s flutter`), with the exact labels: `Speech Status:`,
/// `Speech Error:`, `Recognized Text:`, `Matched Route:`.
class VoiceNavigationService extends ChangeNotifier {
  VoiceNavigationService._();
  static final VoiceNavigationService instance = VoiceNavigationService._();

  final SpeechToText _speech = SpeechToText();

  VoiceStatus _status = VoiceStatus.idle;
  VoiceStatus get status => _status;

  String _recognized = '';
  String get recognizedText => _recognized;

  VoiceCommand? _match;
  VoiceCommand? get match => _match;

  String? _localeId;
  String? get localeId => _localeId;

  bool _initDone = false;
  bool _permanentlyDenied = false;
  bool get permanentlyDenied => _permanentlyDenied;

  bool get isListening => _status == VoiceStatus.listening;

  int _langRetry = 0;
  int _earlyStopRetry = 0;
  DateTime? _listenStartTime;
  DateTime? _sessionDeadline;
  bool _isOfflineAttempt = false;

  /// True from [start] until the session is RESOLVED (a command matched) or
  /// CANCELLED (sheet closed). The recognizer's callbacks are persistent and
  /// Android routinely delivers one last result/error AFTER `stop()`/`cancel()`
  /// - without this flag such a stale callback lands after [cancel] has reset
  /// [_status] to idle (re-arming the `_status == matched` guards) and re-runs
  /// the whole resolve → speak pipeline. That was the root cause of the
  /// "Opening …" confirmation being spoken twice while navigation (driven by
  /// the sheet, already disposed by then) stayed single.
  ///
  /// A no-match outcome deliberately KEEPS the session active: the recognizer
  /// often finalizes richer text a beat after `notListening`, and that late
  /// upgrade (noMatch → matched while the sheet is still open) is a feature.
  bool _sessionActive = false;

  /// True once the "Opening …" confirmation for THIS session has been
  /// dispatched - a second dispatch attempt is ignored, so the confirmation
  /// can be spoken at most once per listening session.
  bool _confirmationSpoken = false;

  void _set(VoiceStatus s) {
    _status = s;
    notifyListeners();
  }

  /// Begins a listening session. [languageCode] ('en' / 'te' / 'hi')
  /// selects the recognition locale; English resolves to **en_IN** first.
  ///
  /// [preferOffline] forces on-device-only recognition. It defaults to **false**
  /// because forcing on-device recognition on a device without the offline
  /// language pack makes the recognizer end immediately with no result. With
  /// `false`, the OS uses its on-device model automatically when available (so
  /// navigation still works offline) and only reaches for the network otherwise.
  Future<void> start({
    String languageCode = 'en',
    bool preferOffline = false,
  }) async {
    _recognized = '';
    _match = null;
    _permanentlyDenied = false;
    _langRetry = 0;
    _earlyStopRetry = 0;
    _listenStartTime = null;
    _sessionDeadline = DateTime.now().add(const Duration(seconds: 10));
    _sessionActive = true;
    _confirmationSpoken = false;
    _set(VoiceStatus.initializing);

    final startMsg = 'start() languageCode=$languageCode preferOffline=$preferOffline';
    debugPrint('[VOICE] $startMsg');
    _log(startMsg);

    if (!_initDone) {
      try {
        _initDone = await _speech.initialize(
          onError: _onError,
          onStatus: _onStatus,
          debugLogging: kDebugMode,
        );
      } catch (e) {
        final initErr = 'initialize() threw: $e';
        debugPrint('[VOICE] $initErr');
        _log(initErr);
        _initDone = false;
      }
    }
    final initStatusMsg = 'Speech initialization: available=$_initDone '
        'hasPermission=${_speech.hasPermission} '
        'isAvailable=${_speech.isAvailable}';
    debugPrint('[VOICE] $initStatusMsg');
    _log(initStatusMsg);

    if (!_initDone) {
      if (!kIsWeb && Platform.isIOS) {
        // iOS manages speech/mic authorization internally through speech recognizer
        _set(VoiceStatus.unavailable);
        return;
      }
      try {
        final mic = await Permission.microphone.status;
        final micMsg = 'Microphone permission: $mic';
        debugPrint('[VOICE] $micMsg');
        _log(micMsg);
        if (mic.isPermanentlyDenied) {
          _permanentlyDenied = true;
          _set(VoiceStatus.denied);
        } else if (mic.isDenied || mic.isRestricted) {
          _set(VoiceStatus.denied);
        } else {
          final unavailMsg = 'Recognizer unavailable (initialize returned false, mic $mic).';
          debugPrint('[VOICE] $unavailMsg');
          _log(unavailMsg);
          _set(VoiceStatus.unavailable);
        }
      } catch (e) {
        final permErr = 'permission check threw: $e';
        debugPrint('[VOICE] $permErr');
        _log(permErr);
        _set(VoiceStatus.unavailable);
      }
      return;
    }

    _localeId = await _resolveLocale(languageCode);
    await _startListening(preferOffline);
  }

  /// Resolves the recognition locale: exact `en_IN` when English (per spec),
  /// then any variant of that language, then the device default. Logs the full
  /// available-locale list so a wrong/missing locale is obvious on-device.
  Future<String?> _resolveLocale(String code) async {
    try {
      final locales = await _speech.locales();
      final localesMsg = 'Available locales (${locales.length}): '
          '${locales.map((l) => l.localeId).join(', ')}';
      debugPrint('[VOICE] $localesMsg');
      _log(localesMsg);
      String norm(String s) => s.toLowerCase().replaceAll('-', '_');

      for (final l in locales) {
        if (norm(l.localeId) == '${code}_in') return l.localeId;
      }
      for (final l in locales) {
        if (norm(l.localeId).startsWith('${code}_')) return l.localeId;
      }
      // Not listed - for English still try en_IN explicitly (many recognizers
      // accept it), and fall back to the system locale on a language error.
      if (code == 'en') return 'en_IN';
      final sys = await _speech.systemLocale();
      return sys?.localeId;
    } catch (e) {
      final locErr = 'locales() failed: $e';
      debugPrint('[VOICE] $locErr');
      _log(locErr);
      return code == 'en' ? 'en_IN' : null;
    }
  }

  Future<void> _startListening(bool preferOffline) async {
    if (!_sessionActive) return;
    try {
      _isOfflineAttempt = preferOffline;
      _listenStartTime = DateTime.now();
      _sessionDeadline ??= DateTime.now().add(const Duration(seconds: 10));

      final listenMsg = 'listen() localeId=$_localeId onDevice=$preferOffline listenFor=10s pauseFor=5s';
      debugPrint('[VOICE] $listenMsg');
      _log(listenMsg);

      final started = await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          onDevice: preferOffline,
          listenMode: ListenMode.confirmation,
          cancelOnError: false,
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 5),
          localeId: _localeId,
        ),
      );

      debugPrint('[VOICE] speech.listen() call result: $started');

      if (started != false) {
        _set(VoiceStatus.listening);
      } else {
        debugPrint('[VOICE] speech.listen() returned false');
        if (preferOffline) {
          debugPrint('[VOICE] Offline listening failed to start, falling back to online/cloud recognizer.');
          _isOfflineAttempt = false;
          return _startListening(false);
        }
        _set(VoiceStatus.error);
      }
    } catch (e, st) {
      final errMsg = 'listen() threw: $e';
      debugPrint('[VOICE] $errMsg\n$st');
      _log(errMsg);
      if (preferOffline) {
        debugPrint('[VOICE] Offline listen threw exception, falling back to online/cloud recognizer.');
        _isOfflineAttempt = false;
        return _startListening(false);
      }
      _set(VoiceStatus.error);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    // Stale callback from a session that was already resolved or cancelled -
    // must never re-enter the resolve → speak pipeline (the double-speech bug).
    if (!_sessionActive) {
      final staleMsg = '[VOICE] Stale result ignored (session closed): "${result.recognizedWords}"';
      debugPrint(staleMsg);
      _log(staleMsg);
      return;
    }
    _recognized = result.recognizedWords;
    final resMsg = 'Recognized Text: "${result.recognizedWords}" '
        'final=${result.finalResult} confidence=${result.confidence}';
    debugPrint('[VOICE] $resMsg');
    _log(resMsg);

    if (_status == VoiceStatus.matched) return;

    if (result.finalResult) {
      // If speech was heard, resolve command immediately
      if (_recognized.trim().isNotEmpty) {
        _resolveFromRecognized();
        return;
      }

      // If finalResult has empty words, check if it closed too early
      final elapsed = _listenStartTime != null
          ? DateTime.now().difference(_listenStartTime!)
          : Duration.zero;

      if (_isOfflineAttempt) {
        debugPrint('[VOICE] Empty finalResult in offline mode ($elapsed). Falling back to online/cloud.');
        _isOfflineAttempt = false;
        _startListening(false);
        return;
      }

      if (elapsed < const Duration(seconds: 5) &&
          _earlyStopRetry < 2 &&
          _sessionDeadline != null &&
          DateTime.now().isBefore(_sessionDeadline!)) {
        _earlyStopRetry++;
        debugPrint('[VOICE] Empty finalResult too early ($elapsed < 5s). Retrying listening (attempt $_earlyStopRetry)...');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_sessionActive && _status != VoiceStatus.matched && _recognized.trim().isEmpty) {
            _startListening(false);
          }
        });
        return;
      }

      _resolveFromRecognized();
    } else {
      notifyListeners(); // live partial text
    }
  }

  void _onStatus(String status) {
    final statusMsg = 'Speech Status: $status (voiceStatus=$_status, recognized="$_recognized")';
    debugPrint('[VOICE] $statusMsg');
    _log(statusMsg);

    if (!_sessionActive) return; // stale event from a closed session
    if (_status == VoiceStatus.matched) return;

    if (status == 'listening') {
      _set(VoiceStatus.listening);
      return;
    }

    // The recognizer stopped on its own (end of speech / timeout). Resolve
    // whatever we heard - only meaningful once we've actually started listening.
    if ((status == 'done' || status == 'notListening') &&
        _status == VoiceStatus.listening) {

      // If speech was recognized, resolve command immediately
      if (_recognized.trim().isNotEmpty) {
        _resolveFromRecognized();
        return;
      }

      // If offline mode stopped with nothing heard, seamlessly fall back to online
      if (_isOfflineAttempt) {
        debugPrint('[VOICE] Offline recognizer stopped with no speech ($status); falling back to online/cloud.');
        _isOfflineAttempt = false;
        _startListening(false);
        return;
      }

      // Check how much time has passed
      final elapsed = _listenStartTime != null
          ? DateTime.now().difference(_listenStartTime!)
          : Duration.zero;

      // Prevent immediate fallback dialog: if stopped too early without input, restart listening
      if (elapsed < const Duration(seconds: 5) &&
          _earlyStopRetry < 2 &&
          _sessionDeadline != null &&
          DateTime.now().isBefore(_sessionDeadline!)) {
        _earlyStopRetry++;
        debugPrint('[VOICE] Recognizer stopped too early ($elapsed < 5s) with empty speech. Retrying listen (attempt $_earlyStopRetry)...');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_sessionActive && _status != VoiceStatus.matched && _recognized.trim().isEmpty) {
            _startListening(false);
          }
        });
        return;
      }

      // Genuine timeout elapsed: user was given several seconds to speak and said nothing.
      debugPrint('[VOICE] Genuine timeout reached ($elapsed) with no input.');
      _resolveFromRecognized();
    }
  }

  void _onError(SpeechRecognitionError error) {
    final errMsg = 'Speech Error: ${error.errorMsg} permanent=${error.permanent}';
    debugPrint('[VOICE] $errMsg');
    _log(errMsg);

    if (!_sessionActive) return; // stale event from a closed session
    if (_status == VoiceStatus.matched) return;
    final msg = error.errorMsg.toLowerCase();

    // If in offline attempt, error means offline model is not available -> fall back to online/cloud
    if (_isOfflineAttempt) {
      debugPrint('[VOICE] Error in offline mode ($msg). Falling back to online/cloud recognizer.');
      _isOfflineAttempt = false;
      _startListening(false);
      return;
    }

    // A locale the recognizer can't serve → retry once on the system default.
    if ((msg.contains('language') || msg.contains('locale')) &&
        _langRetry == 0) {
      _langRetry = 1;
      final retryMsg = 'Language/locale not supported → retrying with the device default.';
      debugPrint('[VOICE] $retryMsg');
      _log(retryMsg);
      _localeId = null;
      _startListening(false);
      return;
    }

    // "no match" / "no speech" / timeout are benign end-of-session outcomes.
    if (msg.contains('no_match') ||
        msg.contains('no match') ||
        msg.contains('speech_timeout') ||
        msg.contains('no speech') ||
        msg.contains('error_no_match') ||
        msg.contains('error_speech_timeout')) {

      // If speech was recognized, resolve command
      if (_recognized.trim().isNotEmpty) {
        _resolveFromRecognized();
        return;
      }

      // If no speech was recognized, check if it occurred too early
      final elapsed = _listenStartTime != null
          ? DateTime.now().difference(_listenStartTime!)
          : Duration.zero;

      if (elapsed < const Duration(seconds: 5) &&
          _earlyStopRetry < 2 &&
          _sessionDeadline != null &&
          DateTime.now().isBefore(_sessionDeadline!)) {
        _earlyStopRetry++;
        debugPrint('[VOICE] Benign error $msg received too early ($elapsed < 5s). Retrying listen (attempt $_earlyStopRetry)...');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_sessionActive && _status != VoiceStatus.matched && _recognized.trim().isEmpty) {
            _startListening(false);
          }
        });
        return;
      }

      // Genuine timeout
      debugPrint('[VOICE] Genuine timeout via $msg ($elapsed).');
      _resolveFromRecognized();
      return;
    }
    _set(VoiceStatus.error);
  }

  void _resolveFromRecognized() {
    final cmdMsg = '[VOICE] Command Received: "$_recognized"';
    debugPrint(cmdMsg);
    _log(cmdMsg);
    final m = matchVoiceCommand(_recognized);
    _match = m;
    if (m != null) {
      final matchMsg = 'Matched Route: ${m.route}  (command=${m.id}, from "$_recognized")';
      debugPrint('[VOICE] $matchMsg');
      _log(matchMsg);
      // A match RESOLVES the session: close it BEFORE speaking so any late
      // recognizer callback (Android delivers one after stop()) can never
      // re-run this method and speak the confirmation a second time.
      _sessionActive = false;
      _set(VoiceStatus.matched);
      _stopSpeech();
      speakConfirmation(m);
    } else {
      final noMatchMsg = 'Matched Route: none  (recognized="$_recognized")';
      debugPrint('[VOICE] $noMatchMsg');
      _log(noMatchMsg);
      // No match keeps the session active - a late, richer final result may
      // still upgrade this to a match while the sheet is open.
      _set(VoiceStatus.noMatch);
      _stopSpeech();
    }
  }

  /// Speaks the "Opening …" confirmation for [command] via the app's single
  /// centralized [VoiceManager] (one native TTS engine for the whole app -
  /// see voice_manager.dart for why multiple instances caused double speech).
  /// Guaranteed to dispatch at most ONCE per listening session.
  Future<void> speakConfirmation(VoiceCommand command) async {
    if (_confirmationSpoken) {
      _log('[VOICE] Duplicate Ignored (confirmation already spoken '
          'this session): "Opening ${command.spokenLabel}"');
      return;
    }
    _confirmationSpoken = true;
    try {
      await VoiceManager.instance.speak('Opening ${command.spokenLabel}');
    } catch (e) {
      _log('TTS failed (non-fatal): $e');
    }
  }

  Future<void> _stopSpeech() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  /// Opens the OS app settings so the user can grant microphone access after a
  /// permanent denial.
  Future<void> openSettings() => openAppSettings();

  /// Cancels any in-flight session and resets to idle (called when the sheet
  /// closes).
  Future<void> cancel() async {
    // Whether this cancel follows a successful match (the sheet auto-closes
    // 750 ms into the confirmation). In that case the "Opening …" utterance
    // must be allowed to FINISH - stopping it mid-word both sounded broken and
    // made the follow-up stale-callback replay audible as a "second" playback.
    final wasMatched = _status == VoiceStatus.matched;
    _sessionActive = false; // close the session FIRST - late callbacks are dead
    _listenStartTime = null;
    _sessionDeadline = null;
    _earlyStopRetry = 0;
    _isOfflineAttempt = false;
    try {
      await _speech.cancel();
    } catch (_) {}
    if (!wasMatched) {
      // Only silence the engine when nothing meaningful was being confirmed.
      try {
        await VoiceManager.instance.stop();
      } catch (_) {}
    }
    _recognized = '';
    _match = null;
    _status = VoiceStatus.idle;
    notifyListeners();
  }
}
