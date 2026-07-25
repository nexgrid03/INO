import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inoapp/services/app_settings.dart';
import 'package:inoapp/services/voice_greeting_service.dart';
import 'package:inoapp/widgets/home/welcome_sound_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = VoiceGreetingService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.welcomeSound.value = true;
    svc.reset();
    svc.speaking.value = false;
  });

  group('voice greeting text', () {
    test('time-of-day phrasing', () {
      expect(svc.greetingText(5, 'Rahul'), 'Good Morning, Rahul.');
      expect(svc.greetingText(11, 'Rahul'), 'Good Morning, Rahul.');
      expect(svc.greetingText(12, 'Rahul'), 'Good Afternoon, Rahul.');
      expect(svc.greetingText(16, 'Rahul'), 'Good Afternoon, Rahul.');
      expect(svc.greetingText(17, 'Rahul'), 'Good Evening, Rahul.');
      expect(svc.greetingText(20, 'Rahul'), 'Good Evening, Rahul.');
      // Night (21:00–04:59) uses the evening phrasing per spec.
      expect(svc.greetingText(21, 'Rahul'), 'Good Evening, Rahul.');
      expect(svc.greetingText(3, 'Rahul'), 'Good Evening, Rahul.');
    });

    test('greets by first name only', () {
      expect(svc.greetingText(9, 'Rahul Kumar Sharma'), 'Good Morning, Rahul.');
    });

    test('omits the name when unavailable', () {
      expect(svc.greetingText(9, null), 'Good Morning.');
      expect(svc.greetingText(9, ''), 'Good Morning.');
      expect(svc.greetingText(13, '   '), 'Good Afternoon.');
    });
  });

  group('welcome sound setting', () {
    test('greeting is skipped entirely when the welcome sound is off', () async {
      AppSettings.instance.welcomeSound.value = false;
      var startedSpeaking = false;
      void listener() {
        if (svc.speaking.value) startedSpeaking = true;
      }

      svc.speaking.addListener(listener);
      await svc.greetOnce(userName: 'Rahul');
      svc.speaking.removeListener(listener);

      // Muted → no audible window ever opened (nothing loaded, nothing spoken).
      expect(startedSpeaking, isFalse);
      expect(svc.speaking.value, isFalse);
    });

    test('greeting opens (and closes) the speaking window when enabled',
        () async {
      var startedSpeaking = false;
      void listener() {
        if (svc.speaking.value) startedSpeaking = true;
      }

      svc.speaking.addListener(listener);
      await svc.greetOnce(userName: 'Rahul');
      svc.speaking.removeListener(listener);

      // In the test host TTS init fails silently, but the speaking window is
      // still bracketed correctly: opened, then closed by the time we return.
      expect(startedSpeaking, isTrue);
      expect(svc.speaking.value, isFalse);
    });

    test('turning the setting off mid-greeting stops playback immediately',
        () async {
      svc.speaking.value = true; // greeting mid-utterance
      // Flip the setting the way the Settings switch does - the service
      // listens to the notifier and silences playback instantly.
      await AppSettings.instance.setWelcomeSound(false);
      expect(svc.speaking.value, isFalse);
      expect(AppSettings.instance.welcomeSound.value, isFalse);
    });

    test('muteNow silences and persists welcomeSound=false', () async {
      svc.speaking.value = true; // simulate a greeting mid-utterance
      await svc.muteNow();

      expect(svc.speaking.value, isFalse);
      expect(AppSettings.instance.welcomeSound.value, isFalse);
      // Persisted - survives an app restart.
      final p = await SharedPreferences.getInstance();
      expect(p.getBool('pref_welcome_sound_enabled'), isFalse);
    });
  });

  group('WelcomeSoundPill', () {
    // The pill's OWN IgnorePointer is the outermost widget it builds; several
    // framework widgets also contain IgnorePointers, so scope + take first.
    IgnorePointer pillGate(WidgetTester tester) => tester.widget<IgnorePointer>(
          find
              .descendant(
                of: find.byType(WelcomeSoundPill),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );

    testWidgets('hidden while nothing plays, mutes on tap', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: WelcomeSoundPill()),
      ));

      // Not speaking → non-interactive (invisible to touch).
      expect(pillGate(tester).ignoring, isTrue);

      // Greeting starts → the pill appears and is tappable.
      svc.speaking.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(pillGate(tester).ignoring, isFalse);
      expect(find.text('Mute greeting'), findsOneWidget);

      // Tap → immediate silence + persisted opt-out, pill hides.
      await tester.tap(find.text('Mute greeting'));
      await tester.pump();
      expect(AppSettings.instance.welcomeSound.value, isFalse);
      expect(svc.speaking.value, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(pillGate(tester).ignoring, isTrue);
    });

    testWidgets('auto-dismisses after 3 seconds', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: WelcomeSoundPill()),
      ));

      svc.speaking.value = true;
      await tester.pump();
      expect(pillGate(tester).ignoring, isFalse);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(pillGate(tester).ignoring, isTrue);

      svc.speaking.value = false; // tidy up the shared notifier
    });
  });
}
