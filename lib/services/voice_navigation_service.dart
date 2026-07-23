import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/voice_command.dart';

void _log(String message) => developer.log(message, name: 'voice');

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
  final FlutterTts _tts = FlutterTts();

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

  void _set(VoiceStatus s) {
    _status = s;
    notifyListeners();
  }

  /// Begins a listening session. [languageCode] ('en' / 'te' / 'hi' / 'ta')
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
    _set(VoiceStatus.initializing);
    _log('start() languageCode=$languageCode preferOffline=$preferOffline');

    if (!_initDone) {
      try {
        _initDone = await _speech.initialize(
          onError: _onError,
          onStatus: _onStatus,
          debugLogging: true,
        );
      } catch (e) {
        _log('initialize() threw: $e');
        _initDone = false;
      }
    }
    _log('Speech initialization: available=$_initDone '
        'hasPermission=${_speech.hasPermission} '
        'isAvailable=${_speech.isAvailable}');

    if (!_initDone) {
      try {
        final mic = await Permission.microphone.status;
        _log('Microphone permission: $mic');
        if (mic.isPermanentlyDenied) {
          _permanentlyDenied = true;
          _set(VoiceStatus.denied);
        } else if (mic.isDenied || mic.isRestricted) {
          _set(VoiceStatus.denied);
        } else {
          _log('Recognizer unavailable (initialize returned false, mic $mic).');
          _set(VoiceStatus.unavailable);
        }
      } catch (e) {
        _log('permission check threw: $e');
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
      _log('Available locales (${locales.length}): '
          '${locales.map((l) => l.localeId).join(', ')}');
      String norm(String s) => s.toLowerCase().replaceAll('-', '_');

      for (final l in locales) {
        if (norm(l.localeId) == '${code}_in') return l.localeId;
      }
      for (final l in locales) {
        if (norm(l.localeId).startsWith('${code}_')) return l.localeId;
      }
      // Not listed — for English still try en_IN explicitly (many recognizers
      // accept it), and fall back to the system locale on a language error.
      if (code == 'en') return 'en_IN';
      final sys = await _speech.systemLocale();
      return sys?.localeId;
    } catch (e) {
      _log('locales() failed: $e');
      return code == 'en' ? 'en_IN' : null;
    }
  }

  Future<void> _startListening(bool preferOffline) async {
    try {
      _log('listen() localeId=$_localeId onDevice=$preferOffline');
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          onDevice: preferOffline,
          listenMode: ListenMode.confirmation,
          cancelOnError: false,
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 4),
          localeId: _localeId,
        ),
      );
      _set(VoiceStatus.listening);
    } catch (e) {
      _log('listen() threw: $e');
      _set(VoiceStatus.error);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    _recognized = result.recognizedWords;
    _log('Recognized Text: "${result.recognizedWords}" '
        'final=${result.finalResult} confidence=${result.confidence}');
    if (_status == VoiceStatus.matched) return;
    if (result.finalResult) {
      _resolveFromRecognized();
    } else {
      notifyListeners(); // live partial text
    }
  }

  void _onStatus(String status) {
    _log('Speech Status: $status');
    if (_status == VoiceStatus.matched) return;
    // The recognizer stopped on its own (end of speech / timeout). Resolve
    // whatever we heard — only meaningful once we've actually started listening.
    if ((status == 'done' || status == 'notListening') &&
        _status == VoiceStatus.listening) {
      _resolveFromRecognized();
    }
  }

  void _onError(SpeechRecognitionError error) {
    _log('Speech Error: ${error.errorMsg} permanent=${error.permanent}');
    if (_status == VoiceStatus.matched) return;
    final msg = error.errorMsg.toLowerCase();

    // A locale the recognizer can't serve → retry once on the system default.
    if ((msg.contains('language') || msg.contains('locale')) &&
        _langRetry == 0) {
      _langRetry = 1;
      _log('Language/locale not supported → retrying with the device default.');
      _localeId = null;
      _startListening(false);
      return;
    }

    // "no match" / "no speech" / timeout are benign end-of-session outcomes.
    if (msg.contains('no_match') ||
        msg.contains('no match') ||
        msg.contains('speech_timeout') ||
        msg.contains('no speech')) {
      _resolveFromRecognized();
      return;
    }
    _set(VoiceStatus.error);
  }

  void _resolveFromRecognized() {
    final m = matchVoiceCommand(_recognized);
    _match = m;
    if (m != null) {
      _log('Matched Route: ${m.route}  (command=${m.id}, '
          'from "$_recognized")');
      _set(VoiceStatus.matched);
      _stopSpeech();
      speakConfirmation(m);
    } else {
      _log('Matched Route: none  (recognized="$_recognized")');
      _set(VoiceStatus.noMatch);
      _stopSpeech();
    }
  }

  /// Speaks the "Opening …" confirmation for [command].
  Future<void> speakConfirmation(VoiceCommand command) async {
    try {
      await _tts.stop();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.speak('Opening ${command.spokenLabel}');
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
    try {
      await _speech.cancel();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    _recognized = '';
    _match = null;
    _status = VoiceStatus.idle;
    notifyListeners();
  }
}
