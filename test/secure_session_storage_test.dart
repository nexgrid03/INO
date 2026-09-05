import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/storage/secure_local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('SecureLocalStorage Security Tests (H7)', () {
    test('writes and reads session from hardware-backed secure storage', () async {
      final storage = SecureLocalStorage();
      await storage.persistSession('{"access_token":"secure_jwt_123"}');

      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), '{"access_token":"secure_jwt_123"}');

      // Verify NOT persisted in plaintext SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('supabase.auth.token'), isNull);

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });

    test('seamlessly migrates legacy plaintext session from SharedPreferences to SecureStorage', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('supabase.auth.token', '{"access_token":"legacy_plaintext_jwt"}');

      final storage = SecureLocalStorage();
      // Reading access token triggers seamless migration
      final token = await storage.accessToken();
      expect(token, '{"access_token":"legacy_plaintext_jwt"}');

      // Legacy plaintext must be deleted from SharedPreferences to prevent token leakage
      expect(prefs.getString('supabase.auth.token'), isNull);

      // And token is now present in SecureStorage
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('confirm logout removes all persisted tokens from both secure storage and SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('supabase.auth.token', 'legacy_token');

      final storage = SecureLocalStorage();
      await storage.persistSession('secure_token');

      // Execute logout / removePersistedSession
      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
      expect(prefs.getString('supabase.auth.token'), isNull);
    });
  });
}
