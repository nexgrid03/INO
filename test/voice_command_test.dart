import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/voice_command.dart';

void main() {
  group('matchVoiceCommand', () {
    test('English "open documents" → documents', () {
      expect(matchVoiceCommand('open documents')?.id, 'documents');
    });

    test('matches the keyword inside a longer sentence', () {
      expect(matchVoiceCommand('please open my notes now')?.id, 'notes');
    });

    test('is case-insensitive', () {
      expect(matchVoiceCommand('OPEN SETTINGS')?.id, 'settings');
    });

    test('each English destination has a distinct trigger', () {
      expect(matchVoiceCommand('expenses')?.id, 'expenses');
      expect(matchVoiceCommand('scanner')?.id, 'scanner');
      expect(matchVoiceCommand('profile')?.id, 'profile');
      expect(matchVoiceCommand('cards')?.id, 'banking');
      expect(matchVoiceCommand('passwords')?.id, 'passwords');
    });

    test('"tax records" is not shadowed by another command', () {
      expect(matchVoiceCommand('open tax records')?.id, 'tax-records');
    });

    test('specific action verbs beat the wallet nouns', () {
      // "add document" must open the Add Document flow, not the Documents wallet.
      expect(matchVoiceCommand('add document')?.id, 'add-document');
      // "gold calculator" must open the calculator, not the Investment wallet.
      expect(matchVoiceCommand('open gold calculator')?.id, 'gold-calculator');
      // ...but a bare "gold" still means the investment holdings.
      expect(matchVoiceCommand('gold')?.id, 'investments');
    });

    test('new destinations resolve', () {
      expect(matchVoiceCommand('open emi calculator')?.id, 'emi');
      expect(matchVoiceCommand('sip')?.id, 'sip');
      expect(matchVoiceCommand('area converter')?.id, 'area-converter');
      expect(matchVoiceCommand('open insurance')?.id, 'insurance');
      expect(matchVoiceCommand('health records')?.id, 'health');
      expect(matchVoiceCommand('two factor authentication')?.id, 'two-factor');
      expect(matchVoiceCommand('notifications')?.id, 'notifications');
      expect(matchVoiceCommand('net worth')?.id, 'net-worth');
    });

    test('Telugu script maps correctly', () {
      expect(matchVoiceCommand('పత్రాలు')?.id, 'documents');
      expect(matchVoiceCommand('నోట్స్')?.id, 'notes');
    });

    test('Hinglish / romanized maps correctly', () {
      expect(matchVoiceCommand('kharcha')?.id, 'expenses');
      expect(matchVoiceCommand('dastavej kholo')?.id, 'documents');
    });

    test('short + alias keywords work', () {
      expect(matchVoiceCommand('note')?.id, 'notes');
      expect(matchVoiceCommand('docs')?.id, 'documents');
      expect(matchVoiceCommand('card')?.id, 'banking');
      expect(matchVoiceCommand('scan')?.id, 'scanner');
      expect(matchVoiceCommand('itr')?.id, 'tax-records');
    });

    test('fuzzy matching tolerates minor recognition mistakes', () {
      expect(matchVoiceCommand('nots')?.id, 'notes');
      expect(matchVoiceCommand('documnt')?.id, 'documents');
      expect(matchVoiceCommand('setings')?.id, 'settings');
      expect(matchVoiceCommand('expence')?.id, 'expenses');
    });

    test('every command exposes a display route and unique id', () {
      final ids = <String>{};
      for (final c in kVoiceCommands) {
        expect(c.route.startsWith('/'), isTrue);
        expect(ids.add(c.id), isTrue, reason: 'duplicate id ${c.id}');
      }
    });

    test('unrelated speech returns null', () {
      expect(matchVoiceCommand('what is the weather today'), isNull);
      expect(matchVoiceCommand(''), isNull);
      expect(matchVoiceCommand('   '), isNull);
    });

    test('every destination is reachable from at least one of its phrases', () {
      for (final c in kVoiceCommands) {
        final reachable = c.phrases.any((p) => matchVoiceCommand(p)?.id == c.id);
        expect(reachable, isTrue, reason: 'No phrase resolves to "${c.id}"');
      }
    });
  });
}
