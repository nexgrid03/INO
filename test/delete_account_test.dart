import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountService.deleteAccount', () {
    test('throws AuthException when unauthenticated', () async {
      expect(
        () => AccountService.instance.deleteAccount(),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
