import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'tts_engine.dart';

void _log(String message) => developer.log(message, name: 'greeting');

/// Speaks a time-based welcome ("Good Morning, Rahul.") exactly once per
/// session — right after login, or when the app opens with a user already
/// signed in. Both paths reach the authenticated shell, which calls
/// [greetOnce] from a post-frame callback.
///
/// Double-play protection (the "greeting plays twice" bug), in layers:
///  1. [_greeted] is flipped SYNCHRONOUSLY before any async work, so no two
///     callers — shell rebuilds, navigation back, provider refreshes, a second
///     shell mount during the auth handoff — can both pass the guard;
///  2. speech goes through the app-wide shared [TtsEngine], which is warmed up
///     at app start (the native cold-start re-queue race that could replay the
///     first utterance can no longer occur) and which drops a duplicate
///     request for an utterance that is still being spoken.
///
/// Deliberately fire-and-forget and self-guarding: any TTS failure is
/// swallowed so the greeting can never interfere with the app.
class VoiceGreetingService {
  VoiceGreetingService._();
  static final VoiceGreetingService instance = VoiceGreetingService._();

  /// True once we've greeted this session, so the greeting plays only once.
  bool _greeted = false;

  /// Speaks the greeting once. Subsequent calls in the same session are no-ops.
  ///
  /// [userName] is the signed-in user's name; when blank the greeting omits it
  /// ("Good Morning.").
  Future<void> greetOnce({String? userName}) async {
    if (_greeted) {
      _log('Greeting skipped — already played this session');
      debugPrint('Greeting skipped — already played this session');
      return;
    }
    // Set BEFORE any await: a second caller in the same microtask window must
    // already see the guard closed.
    _greeted = true;

    final text = _greetingFor(DateTime.now().hour, userName);
    _log('Greeting triggered: "$text"');
    debugPrint('Greeting triggered: "$text"');
    await TtsEngine.instance.speak(text);
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

  /// Re-arms the greeting for the next sign-in. Called from `SessionReset` on
  /// sign-out, so the next account (or the same one signing back in) is
  /// greeted at the start of ITS session — still exactly once.
  void resetForNextSession() {
    _greeted = false;
    _log('Greeting re-armed for the next session');
  }

  /// Test hook: allows the greeting to fire again.
  @visibleForTesting
  void reset() => _greeted = false;

  /// Test hook: the phrase that would be spoken at [hour] for [name].
  @visibleForTesting
  String greetingText(int hour, String? name) => _greetingFor(hour, name);
}
