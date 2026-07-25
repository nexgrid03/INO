import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'voice_manager.dart';

void _log(String message) => developer.log(message, name: 'greeting');

/// Speaks a time-based welcome ("Good Morning, Rahul.") exactly once per
/// session - right after login, or when the app opens with a user already
/// signed in. Both paths reach the authenticated shell, which calls
/// [greetOnce] from a post-frame callback.
///
/// Double-play protection (the "greeting plays twice" bug), in layers:
///  1. [_greeted] is flipped SYNCHRONOUSLY before any async work, so no two
///     callers - shell rebuilds, navigation back, provider refreshes, a second
///     shell mount during the auth handoff - can both pass the guard;
///  2. speech goes through the app-wide shared [VoiceManager], which is warmed up
///     at app start (the native cold-start re-queue race that could replay the
///     first utterance can no longer occur) and which drops a duplicate
///     request for an utterance that is still being spoken.
///
/// Deliberately fire-and-forget and self-guarding: any TTS failure is
/// swallowed so the greeting can never interfere with the app.
class VoiceGreetingService {
  VoiceGreetingService._() {
    // Flipping the startup-greeting setting OFF must silence an in-flight
    // greeting IMMEDIATELY, no matter which surface flipped it (the Settings
    // switch, the mute pill, or any future control). Listening to the setting
    // itself keeps that guarantee in one place.
    AppSettings.instance.welcomeSound.addListener(_onSettingChanged);
  }
  static final VoiceGreetingService instance = VoiceGreetingService._();

  void _onSettingChanged() {
    if (!AppSettings.instance.welcomeSound.value && speaking.value) {
      _log('Greeting setting turned off mid-utterance - stopping playback');
      speaking.value = false;
      unawaited(VoiceManager.instance.stop());
    }
  }

  /// True once we've greeted this session, so the greeting plays only once.
  bool _greeted = false;

  /// True while the greeting is actually being spoken. The "Mute greeting"
  /// pill ([WelcomeSoundPill]) shows exactly while this is true and hides the
  /// moment the utterance finishes or is muted.
  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  /// Speaks the greeting once. Subsequent calls in the same session are no-ops.
  ///
  /// Respects the persisted "Welcome sound" preference
  /// ([AppSettings.welcomeSound]) - read BEFORE any audio work, so when the
  /// user has muted the greeting nothing is loaded or spoken at all (never
  /// load-then-stop).
  ///
  /// [userName] is the signed-in user's name; when blank the greeting omits it
  /// ("Good Morning.").
  Future<void> greetOnce({String? userName}) async {
    if (_greeted) {
      _log('Greeting skipped - already played this session');
      debugPrint('Greeting skipped - already played this session');
      return;
    }
    // Set BEFORE any await: a second caller in the same microtask window must
    // already see the guard closed.
    _greeted = true;

    if (!AppSettings.instance.welcomeSound.value) {
      _log('Greeting skipped - welcome sound is turned off');
      debugPrint('Greeting skipped - welcome sound is turned off');
      return;
    }

    final text = _greetingFor(DateTime.now().hour, userName);
    _log('Greeting triggered: "$text"');
    debugPrint('Greeting triggered: "$text"');
    speaking.value = true;
    try {
      // Resolves when the utterance COMPLETES (VoiceManager awaits speech
      // completion), so `speaking` brackets the audible window exactly.
      await VoiceManager.instance.speak(text);
    } finally {
      speaking.value = false;
    }
  }

  /// The in-the-moment mute: immediately stops the greeting mid-utterance AND
  /// persists `welcomeSound = false` so it won't play on the next launch
  /// either. No confirmation - the silence intent is honoured instantly.
  Future<void> muteNow() async {
    _log('Greeting muted by the user - disabling the welcome sound');
    debugPrint('Greeting muted by the user - disabling the welcome sound');
    speaking.value = false;
    await AppSettings.instance.setWelcomeSound(false);
    try {
      await VoiceManager.instance.stop();
    } catch (_) {
      // Stopping is best-effort; the preference is already persisted.
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
    // Greet by first name only - it sounds more natural spoken aloud.
    final firstName = person.isEmpty ? '' : person.split(RegExp(r'\s+')).first;
    return firstName.isEmpty ? '$phrase.' : '$phrase, $firstName.';
  }

  /// Re-arms the greeting for the next sign-in. Called from `SessionReset` on
  /// sign-out, so the next account (or the same one signing back in) is
  /// greeted at the start of ITS session - still exactly once.
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
