import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/voice_command.dart';

void main() {
  group('matchVoiceCommand', () {
    test('English "open documents" → documents', () {
      expect(matchVoiceCommand('open documents')?.id, VoiceCommandId.documents);
    });

    test('matches the keyword inside a longer sentence', () {
      expect(matchVoiceCommand('please open my notes now')?.id,
          VoiceCommandId.notes);
    });

    test('is case-insensitive', () {
      expect(matchVoiceCommand('OPEN SETTINGS')?.id, VoiceCommandId.settings);
    });

    test('each English destination has a distinct trigger', () {
      expect(matchVoiceCommand('cards')?.id, VoiceCommandId.cards);
      expect(matchVoiceCommand('expenses')?.id, VoiceCommandId.expenses);
      expect(matchVoiceCommand('scanner')?.id, VoiceCommandId.scanner);
      expect(matchVoiceCommand('profile')?.id, VoiceCommandId.profile);
    });

    test('"tax records" is not shadowed by "cards"', () {
      expect(matchVoiceCommand('open tax records')?.id,
          VoiceCommandId.taxRecords);
    });

    test('Telugu script maps correctly', () {
      expect(matchVoiceCommand('పత్రాలు')?.id, VoiceCommandId.documents);
      expect(matchVoiceCommand('నోట్స్')?.id, VoiceCommandId.notes);
    });

    test('Hinglish / romanized maps correctly', () {
      expect(matchVoiceCommand('kharcha')?.id, VoiceCommandId.expenses);
      expect(matchVoiceCommand('dastavez kholo')?.id, VoiceCommandId.documents);
    });

    test('short + alias keywords work', () {
      expect(matchVoiceCommand('note')?.id, VoiceCommandId.notes);
      expect(matchVoiceCommand('docs')?.id, VoiceCommandId.documents);
      expect(matchVoiceCommand('card')?.id, VoiceCommandId.cards);
      expect(matchVoiceCommand('scan')?.id, VoiceCommandId.scanner);
      expect(matchVoiceCommand('tax')?.id, VoiceCommandId.taxRecords);
      expect(matchVoiceCommand('itr')?.id, VoiceCommandId.taxRecords);
    });

    test('fuzzy matching tolerates minor recognition mistakes', () {
      expect(matchVoiceCommand('nots')?.id, VoiceCommandId.notes);
      expect(matchVoiceCommand('documnt')?.id, VoiceCommandId.documents);
      expect(matchVoiceCommand('setings')?.id, VoiceCommandId.settings);
      expect(matchVoiceCommand('expence')?.id, VoiceCommandId.expenses);
    });

    test('every command exposes a display route', () {
      for (final c in kVoiceCommands) {
        expect(c.route.startsWith('/'), isTrue);
      }
    });

    test('unrelated speech returns null', () {
      expect(matchVoiceCommand('what is the weather today'), isNull);
      expect(matchVoiceCommand(''), isNull);
      expect(matchVoiceCommand('   '), isNull);
    });

    test('every destination is reachable from its own phrases', () {
      final reached = <VoiceCommandId>{};
      for (final c in kVoiceCommands) {
        for (final phrase in c.phrases) {
          final m = matchVoiceCommand(phrase);
          if (m != null) reached.add(m.id);
        }
      }
      expect(reached, containsAll(VoiceCommandId.values));
    });
  });
}
