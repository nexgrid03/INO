import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks a time-based welcome ("Good Morning, Rahul.") exactly once per app
/// launch — right after login, or when the app opens with a user already signed
/// in. Both paths reach the authenticated shell, which calls [greetOnce].
///
/// Deliberately fire-and-forget and self-guarding: navigating between screens
/// never re-triggers it, and any TTS failure is swallowed so the greeting can
/// never interfere with the app.
class VoiceGreetingService {
  VoiceGreetingService._();
  static final VoiceGreetingService instance = VoiceGreetingService._();

  final FlutterTts _tts = FlutterTts();

  /// True once we've greeted this launch, so the greeting plays only once.
  bool _greeted = false;

  /// Speaks the greeting once. Subsequent calls in the same launch are no-ops.
  ///
  /// [userName] is the signed-in user's name; when blank the greeting omits it
  /// ("Good Morning.").
  Future<void> greetOnce({String? userName}) async {
    if (_greeted) return;
    _greeted = true;

    final text = _greetingFor(DateTime.now().hour, userName);
    try {
      await _tts.stop();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5); // comfortable, natural pace
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.speak(text);
    } catch (e) {
      // Non-fatal — a device without TTS should never break the app.
      debugPrint('Voice greeting failed (non-fatal): $e');
    }
  }

  /// Builds the phrase for [hour] (0–23):
  /// 5–11 → morning · 12–16 → afternoon · everything else → evening
  /// (evening also covers night, 21:00–04:59, per the product spec).
  String _greetingFor(int hour, String? name) {
    final String phrase;
    if (hour >= 5 && hour < 12) {
      phrase = 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      phrase = 'Good Afternoon';
    } else {
      phrase = 'Good Evening';
    }
    final person = (name ?? '').trim();
    // Greet by first name only — it sounds more natural spoken aloud.
    final firstName = person.isEmpty ? '' : person.split(RegExp(r'\s+')).first;
    return firstName.isEmpty ? '$phrase.' : '$phrase, $firstName.';
  }

  /// Test hook: allows the greeting to fire again.
  @visibleForTesting
  void reset() => _greeted = false;

  /// Test hook: the phrase that would be spoken at [hour] for [name].
  @visibleForTesting
  String greetingText(int hour, String? name) => _greetingFor(hour, name);
}
