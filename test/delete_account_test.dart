import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _read(String path) => File(path).readAsStringSync();

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

  group('deleting an account is one confirmation, nothing more', () {
    late String profile;

    setUpAll(() => profile = _read('lib/screens/profile/profile_screen.dart'));

    test('the type-DELETE gate and password re-entry are gone', () {
      // Login is OTP-only now, so a password prompt here would be
      // un-completable - there is no password to type. The live authenticated
      // session that reaches this screen IS the re-authentication.
      for (final gone in const [
        'typeDeleteToConfirm',
        'confirmYourPassword',
        'reauthenticate',
        'DeleteAccountScreen',
      ]) {
        expect(profile.contains(gone), isFalse,
            reason: '$gone should no longer be part of the delete flow');
      }
    });

    test('the old high-friction screen is deleted, not just unreferenced', () {
      expect(
        File('lib/screens/profile/delete_account_screen.dart').existsSync(),
        isFalse,
      );
    });

    test('the confirmation still spells out that everything is erased', () {
      // Removing the friction must not also remove the warning - this is the
      // only thing standing between a stray tap and permanent data loss.
      expect(profile, contains("l10n.t('cantBeUndone')"));
      expect(profile, contains("l10n.t('deleteAccountWarning')"));
      expect(profile, contains("l10n.t('keepMyAccount')"));
    });

    test('confirming is what deletes - and only confirming', () {
      final body = profile.substring(profile.indexOf('_confirmDeleteAccount'));
      final end = body.indexOf('Future<void> _performLogout');
      final flow = body.substring(0, end);
      expect(flow, contains('if (confirmed == true)'),
          reason: 'dismissing the sheet must never delete anything');
      expect(flow, contains('AccountService.instance.deleteAccount()'));
    });

    test('the delete round-trip blocks the UI so it cannot be fired twice', () {
      final body = profile.substring(profile.indexOf('_performDeleteAccount() async'));
      final flow = body.substring(0, body.indexOf('Future<void> _performLogout'));
      expect(flow, contains('barrierDismissible: false'));
      expect(flow, contains('InoLoader'));
      // A failure has to give the user their screen back.
      expect(flow, contains("_toast(l10n.t('couldNotDeleteAccount'))"));
    });
  });
}
