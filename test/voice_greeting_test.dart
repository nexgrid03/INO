import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/voice_greeting_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = VoiceGreetingService.instance;

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
}
