// Guards the "one account, two identifiers" rule.
//
// Supabase Auth keys an account by email OR phone. The app used to call
// signInWithOtp(..., shouldCreateUser: true) on both channels, so signing up
// with an email and later "logging in" with a phone silently minted a SECOND
// account - two auth users, two profiles, two vaults. The fix has three parts,
// and each is easy to undo by accident:
//
//   1. login never passes shouldCreateUser: true,
//   2. login asks account_exists() first, so an unknown identifier is told to
//      sign up rather than handed to Supabase,
//   3. signup confirms BOTH identifiers against the one auth user.
//
// These tests read the source for 1 and 2 (the calls themselves need a live
// Supabase, but the arguments are the whole point), and cover the identifier
// parsing that decides which channel a typed value belongs to.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:inoapp/screens/auth/auth_validators.dart';
import 'package:inoapp/screens/auth/login_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/services/auth_service.dart';
import 'package:inoapp/widgets/auth/auth_primary_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('login can never create an account', () {
    late String login;
    late String auth;

    setUpAll(() {
      login = _read('lib/screens/auth/login_screen.dart');
      auth = _read('lib/services/auth_service.dart');
    });

    test('every OTP send on the login path passes shouldCreateUser: false', () {
      // Both login sends and both resends.
      final guarded = RegExp(r'shouldCreateUser: false').allMatches(login).length;
      expect(guarded, greaterThanOrEqualTo(4),
          reason: 'login send + resend, for each of email and phone');
    });

    test('the login path never opts into user creation', () {
      expect(login.contains('shouldCreateUser: true'), isFalse,
          reason: 'a login must not be able to mint an account');
    });

    test('login checks the users table before asking for a code', () {
      expect(login.contains('accountExists'), isTrue);
      // The "no account" branch must send people to signup, not silently pass
      // the identifier to Supabase.
      expect(login, contains('Please create an account first'));
      expect(login, contains('_mode = AuthMode.signUp'));
    });

    test('accountExists fails closed rather than guessing "no account"', () {
      // It must not swallow errors into a false - a lookup that failed because
      // the device is offline would send an existing user to the signup form.
      final body = auth.substring(auth.indexOf('Future<bool> accountExists'));
      final end = body.indexOf('\n  }');
      expect(body.substring(0, end).contains('catch'), isFalse,
          reason: 'a failed lookup must rethrow, not report "no account"');
    });

    test('signup confirms the mobile as well as the email', () {
      // Without linkPhone + verifyPhoneLink the phone is never attached to the
      // auth user, and logging in with it could only ever create a new account.
      expect(login.contains('linkPhone'), isTrue);
      expect(login.contains('verifyPhoneLink'), isTrue);
      expect(auth.contains('OtpType.phoneChange'), isTrue);
    });

    test('password sign-in is gone from the login screen', () {
      for (final gone in const [
        'signInWithEmail',
        '_signInWithPassword',
        'ForgotPasswordScreen',
      ]) {
        expect(login.contains(gone), isFalse, reason: '$gone should be removed');
      }
    });
  });

  group('the database half', () {
    late String sql;

    setUpAll(() {
      sql = _read(
        'supabase/migrations/20260907130000_single_account_identity.sql',
      );
    });

    test('account_exists is callable by anon and returns only a boolean', () {
      expect(sql, contains('create or replace function public.account_exists'));
      expect(sql, contains('returns boolean'));
      expect(sql, contains('security definer'));
      expect(sql, contains('grant execute on function public.account_exists(text) to anon'));
    });

    test('it matches a phone on digits alone, so formatting cannot miss', () {
      // "+91 98765 43210" and "919876543210" are the same account.
      expect(sql, contains("regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')"));
    });

    test('it only counts confirmed identifiers', () {
      expect(sql, contains('email_confirmed_at is not null'));
      expect(sql, contains('phone_confirmed_at is not null'));
    });

    test('one email and one phone can never map to two profiles', () {
      expect(sql, contains('users_email_unique_idx'));
      expect(sql, contains('users_phone_unique_idx'));
    });

    test('the migration deletes nothing', () {
      final live = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n')
          .toLowerCase();
      for (final destructive in const [
        'delete from',
        'drop table',
        'truncate',
        'update public.users set',
      ]) {
        expect(live.contains(destructive), isFalse,
            reason: 'existing accounts must survive this migration untouched');
      }
    });

    test('the unique indexes cannot abort the script on legacy duplicates', () {
      // The old split-account bug is exactly what leaves duplicate rows behind,
      // so a bare CREATE UNIQUE INDEX would fail on the very databases that
      // most need this migration - taking the account_exists function down with
      // it, and with it every login.
      expect(sql, contains('raise warning'));
      expect(sql, contains('having count(*) > 1'));
    });
  });

  group('a server-side setup gap is named, not swallowed', () {
    // The login flow calls the account_exists RPC before asking for a code, so
    // a project that has not run the migration fails HERE. That used to render
    // as "An unexpected error occurred", which is indistinguishable from an
    // outage and sent us hunting in the wrong place.
    test('a missing account_exists function says exactly that', () {
      for (final e in [
        const PostgrestException(
          message: 'Could not find the function public.account_exists(p_identifier) '
              'in the schema cache',
          code: 'PGRST202',
        ),
        const PostgrestException(
          message: 'function public.account_exists(text) does not exist',
          code: '42883',
        ),
      ]) {
        final msg = AuthService.formatAuthError(e);
        expect(msg, contains('account_exists'));
        expect(msg, contains('migration'));
        expect(msg, isNot(contains('unexpected')));
      }
    });

    test('a missing grant points at the grant', () {
      final msg = AuthService.formatAuthError(
        const PostgrestException(
          message: 'permission denied for function account_exists',
          code: '42501',
        ),
      );
      expect(msg, contains('Grant execute'));
      expect(msg, isNot(contains('unexpected')));
    });

    test('any other database failure still carries its code', () {
      final msg = AuthService.formatAuthError(
        const PostgrestException(message: 'boom', code: 'P0001'),
      );
      expect(msg, contains('P0001'));
    });

    test('a dropped connection reads as a connection problem', () {
      final msg = AuthService.formatAuthError(
        ClientException('Connection closed before full header was received'),
      );
      expect(msg, contains('check your internet connection'));
    });

    test('auth errors are untouched by the new branches', () {
      expect(
        AuthService.formatAuthError(
          const AuthException('User not found'),
        ),
        contains('create an account first'),
      );
    });
  });

  group('identifier parsing', () {
    test('an address is an email, a bare number is not', () {
      expect(AuthValidators.looksLikeEmail('ada@example.com'), isTrue);
      expect(AuthValidators.looksLikeEmail('9876543210'), isFalse);
      expect(AuthValidators.looksLikeEmail('+91 98765 43210'), isFalse);
    });

    test('isValidEmail is stricter than looksLikeEmail', () {
      // looksLikeEmail only picks the branch; isValidEmail decides whether to
      // spend an OTP on it.
      expect(AuthValidators.looksLikeEmail('ada@'), isTrue);
      expect(AuthValidators.isValidEmail('ada@'), isFalse);
      expect(AuthValidators.isValidEmail('ada@example.com'), isTrue);
      expect(AuthValidators.isValidEmail('  ada@example.com  '), isTrue);
    });
  });

  group('the login screen itself', () {
    testWidgets('refuses to send a code for an unusable identifier',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 3200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Too short to be a number, no "@" to be an address.
      await tester.enterText(
        find.byKey(const ValueKey('login_identifier_field')),
        '123',
      );
      await tester.pump();
      // Invoke the CTA's callback rather than tapping it: AuthScaffold's
      // scrolling stack makes a synthetic tap land on the scroll view instead
      // of the button (a pre-existing quirk - the button is fine on device),
      // and its ambient animation means pumpAndSettle would never return.
      // What is under test is the handler, not Flutter's hit testing.
      tester
          .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
          .onPressed!
          .call();
      await tester.pump(); // run the handler
      await tester.pump(const Duration(milliseconds: 400)); // snackbar slides in

      expect(
        find.text('Enter a valid email address or mobile number.'),
        findsOneWidget,
      );
    });
  });
}
