import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/voice_command.dart';
import 'package:inoapp/services/voice_navigation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Voice Assistant Regression & Hardening Verification', () {
    late File voiceServiceFile;
    late String voiceServiceCode;

    setUpAll(() {
      voiceServiceFile = File('lib/services/voice_navigation_service.dart');
      expect(voiceServiceFile.existsSync(), isTrue,
          reason: 'voice_navigation_service.dart must exist');
      voiceServiceCode = voiceServiceFile.readAsStringSync();
    });

    test('Regression fix: preferOffline defaults to false', () {
      // Must NOT default preferOffline to true
      expect(
        voiceServiceCode.contains('bool preferOffline = true'),
        isFalse,
        reason:
            'preferOffline = true causes immediate disconnect/fallback dialog on devices without offline speech pack',
      );

      // Must default preferOffline to false
      expect(
        voiceServiceCode.contains('bool preferOffline = false'),
        isTrue,
        reason:
            'preferOffline = false allows Android/iOS to use offline model if present, or cloud without crashing',
      );
    });

    test('Timeout values: listenFor is at least 8-10s and pauseFor is at least 4-5s', () {
      expect(
        voiceServiceCode.contains('listenFor: const Duration(seconds: 10)') ||
            voiceServiceCode.contains('listenFor: const Duration(seconds: 8)'),
        isTrue,
        reason: 'listenFor must provide at least 8 to 10 seconds for user to speak',
      );

      expect(
        voiceServiceCode.contains('pauseFor: const Duration(seconds: 5)') ||
            voiceServiceCode.contains('pauseFor: const Duration(seconds: 4)'),
        isTrue,
        reason: 'pauseFor must provide at least 4 to 5 seconds of pause tolerance',
      );
    });

    test('Defensive protection: premature stops do NOT immediately show noMatch fallback', () {
      expect(
        voiceServiceCode.contains('elapsed < const Duration(seconds: 5)'),
        isTrue,
        reason: 'Must check if recognizer stopped prematurely before minimum speech window',
      );

      expect(
        voiceServiceCode.contains('_earlyStopRetry'),
        isTrue,
        reason: 'Must track early stop retries before giving up to genuine timeout',
      );

      expect(
        voiceServiceCode.contains('_isOfflineAttempt'),
        isTrue,
        reason: 'Must track offline attempts to fall back to online recognizer seamlessly',
      );
    });

    test('Diagnostic logs: all required telemetry logs are present', () {
      // 1. Microphone permission
      expect(voiceServiceCode.contains('Microphone permission:'), isTrue);
      // 2. Speech initialization
      expect(voiceServiceCode.contains('Speech initialization:'), isTrue);
      // 3. Available locales
      expect(voiceServiceCode.contains('Available locales'), isTrue);
      // 4. Listen start
      expect(voiceServiceCode.contains('listen() localeId='), isTrue);
      // 5. Recognized text
      expect(voiceServiceCode.contains('Recognized Text:'), isTrue);
      // 6. Speech status
      expect(voiceServiceCode.contains('Speech Status:'), isTrue);
      // 7. Speech error
      expect(voiceServiceCode.contains('Speech Error:'), isTrue);
    });

    test('Voice command matcher: valid commands map accurately', () {
      expect(matchVoiceCommand('open documents')?.id, equals('documents'));
      expect(matchVoiceCommand('open scanner')?.id, equals('scanner'));
      expect(matchVoiceCommand('open expenses')?.id, equals('expenses'));
      expect(matchVoiceCommand('open emi calculator')?.id, equals('emi'));
      expect(matchVoiceCommand('open settings')?.id, equals('settings'));
    });

    test('Voice command matcher: empty or silence returns null without crash', () {
      expect(matchVoiceCommand(''), isNull);
      expect(matchVoiceCommand('   '), isNull);
      expect(matchVoiceCommand('what is the weather today'), isNull);
    });

    test('VoiceNavigationService singleton instance is non-null and starts in idle status', () {
      final service = VoiceNavigationService.instance;
      expect(service, isNotNull);
      expect(service.status, equals(VoiceStatus.idle));
      expect(service.isListening, isFalse);
      expect(service.recognizedText, isEmpty);
      expect(service.match, isNull);
    });

    test('Safety check: Voice service does NOT touch unrelated subsystems', () {
      // Check that voice_navigation_service.dart does NOT import or reference sensitive services
      final sensitiveKeywords = [
        'package:supabase_flutter',
        'SupabaseClient',
        'AuthService',
        'delete_account',
        'account_service.dart',
        'wallet_repository.dart',
        'document_repository.dart',
        'push_service.dart',
      ];

      for (final keyword in sensitiveKeywords) {
        expect(
          voiceServiceCode.contains(keyword),
          isFalse,
          reason: 'voice_navigation_service.dart must NOT reference $keyword',
        );
      }
    });
  });
}
