import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/vault_item.dart';
import 'package:inoapp/services/password_utils.dart';
import 'package:inoapp/services/vault_crypto_service.dart';

void main() {
  final crypto = VaultCryptoService.instance;

  group('VaultCryptoService', () {
    test('encrypt → decrypt round-trips with the derived key', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveKey('correct horse battery', salt);

      const plaintext = '{"u":"me@ino.app","p":"S3cr3t!","n":"note"}';
      final blob = await crypto.encrypt(plaintext, key);

      expect(blob, isNot(contains('me@ino.app'))); // no plaintext leaks
      expect(await crypto.decrypt(blob, key), plaintext);
    });

    test('a wrong master password fails authentication', () async {
      final salt = crypto.generateSalt();
      final right = await crypto.deriveKey('right-password', salt);
      final wrong = await crypto.deriveKey('wrong-password', salt);

      final blob = await crypto.encrypt('top secret', right);

      expect(
        () => crypto.decrypt(blob, wrong),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('the same password + salt derives a stable key', () async {
      final salt = crypto.generateSalt();
      final a = await crypto.deriveKey('pw', salt);
      final b = await crypto.deriveKey('pw', salt);
      expect(await a.extractBytes(), await b.extractBytes());
    });
  });

  group('PasswordUtils', () {
    test('strength rises with length and diversity', () {
      expect(PasswordUtils.strength(''), PasswordStrength.empty);
      expect(PasswordUtils.strength('abc'), PasswordStrength.weak);
      expect(
        PasswordUtils.strength('Xk9\$mQ2!vLp7@rTf').score,
        greaterThanOrEqualTo(PasswordStrength.good.score),
      );
    });

    test('generate honours length and includes each enabled class', () {
      final pwd = PasswordUtils.generate(length: 20);
      expect(pwd.length, 20);
      expect(RegExp(r'[a-z]').hasMatch(pwd), isTrue);
      expect(RegExp(r'[A-Z]').hasMatch(pwd), isTrue);
      expect(RegExp(r'\d').hasMatch(pwd), isTrue);
      expect(RegExp(r'[^A-Za-z0-9]').hasMatch(pwd), isTrue);
    });

    test('generate produces unique passwords', () {
      final a = PasswordUtils.generate();
      final b = PasswordUtils.generate();
      expect(a, isNot(b));
    });
  });

  group('VaultItem & VaultCategory', () {
    test('copyWith overrides only the given fields', () {
      final item = VaultItem(
        id: '1',
        title: 'Gmail',
        username: 'me',
        password: 'pw',
        category: VaultCategory.email,
        favorite: false,
        updatedAt: DateTime(2026, 1, 1),
      );
      final updated = item.copyWith(favorite: true, title: 'Gmail Work');
      expect(updated.favorite, isTrue);
      expect(updated.title, 'Gmail Work');
      expect(updated.username, 'me'); // unchanged
    });

    test('fromId maps known ids and defaults to other', () {
      expect(VaultCategory.fromId('finance'), VaultCategory.finance);
      expect(VaultCategory.fromId('nonsense'), VaultCategory.other);
      expect(VaultCategory.fromId(null), VaultCategory.other);
    });
  });
}
