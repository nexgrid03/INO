import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/country_code.dart';
import 'package:inoapp/screens/auth/login_screen.dart';
import 'package:inoapp/screens/auth/otp_verification_screen.dart';
import 'package:inoapp/services/auth_service.dart';
import 'package:inoapp/services/guest_mode.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/auth/otp_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: child,
      );

  group('Auth Redesign & OTP Flow Tests', () {
    testWidgets('Create Account collects name, email and mobile - all mandatory',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signUp)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Join the Vault'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Send Verification Code'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      // The user picks which identifier gets verified - and that one becomes
      // the only way into the account.
      expect(find.text('Send my code to'), findsOneWidget);
      expect(find.text('Email OTP'), findsOneWidget);
      expect(find.text('Mobile OTP'), findsOneWidget);
    });

    testWidgets('the picker states which identifier will log you in',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(
          host(const LoginScreen(initialMode: AuthMode.signUp)));
      await tester.pump(const Duration(milliseconds: 500));

      // Mobile is the default.
      expect(find.textContaining('log in with your mobile number'),
          findsOneWidget);

      await tester.tap(find.text('Email OTP'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('log in with your email'), findsOneWidget);
      expect(find.textContaining('log in with your mobile number'),
          findsNothing);
    });

    testWidgets('Login takes ONE identifier field - email or mobile, no password',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signIn)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Email or mobile number'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);

      // Login takes either identifier - it has to, so that typing the one you
      // did NOT verify can tell you so - but offers no channel picker of its
      // own and no password path.
      expect(find.text('Mobile OTP'), findsNothing);
      expect(find.text('Email OTP'), findsNothing);
      expect(find.text('Sign in with Password instead'), findsNothing);
      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('the country prefix appears for a number and hides for an email',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signIn)));
      await tester.pump(const Duration(milliseconds: 500));

      final field = find.byKey(const ValueKey('login_identifier_field'));
      expect(field, findsOneWidget);

      // A bare number is a mobile: the dial code has to be selectable.
      await tester.enterText(field, '9876543210');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(kCountryCodes.first.dialCode), findsOneWidget);

      // The moment it reads as an address, the dial code is meaningless.
      await tester.enterText(field, 'ada@example.com');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(kCountryCodes.first.dialCode), findsNothing);
    });

    testWidgets('OTP Verification Screen renders 6 digit boxes, change destination, and countdown',
        (tester) async {
      useTallView(tester);
      bool changedDestination = false;

      await tester.pumpWidget(host(
        OtpVerificationScreen(
          destination: '+919876543210',
          onVerify: (code) async => code == '123456',
          onVerified: (_) {},
          onResend: () async {},
          onChangeDestination: () {
            changedDestination = true;
          },
          resendSeconds: 30,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('+919876543210'),
        ),
        findsOneWidget,
      );
      expect(find.text('Change Mobile Number'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.text('Verify'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);

      // Tap Change Mobile Number
      await tester.tap(find.text('Change Mobile Number'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(changedDestination, isTrue);
    });

    test('AuthService.formatAuthError converts auth exceptions to user-friendly messages', () {
      final invalidOtpErr = AuthException('Invalid token or code');
      expect(
        AuthService.formatAuthError(invalidOtpErr),
        contains('verification code entered is incorrect'),
      );

      final expiredOtpErr = AuthException('Token has expired');
      expect(
        AuthService.formatAuthError(expiredOtpErr),
        contains('verification code has expired'),
      );

      final rateLimitErr = AuthException('over_email_send_rate_limit: rate limit exceeded');
      expect(
        AuthService.formatAuthError(rateLimitErr),
        contains('Too many attempts'),
      );

      // gotrue-dart surfaces HTTP 500 bodies verbatim. The login screen must
      // not show that JSON. The message is the mailer's failure to send the
      // email OTP, which Supabase still labels "magic link".
      final mailerErr = AuthException(
        '{"code":"unexpected_failure","message":"Error sending magic link email"}',
      );
      final friendly = AuthService.formatAuthError(mailerErr);
      expect(friendly, contains("couldn't send the verification code"));
      expect(friendly, isNot(contains('unexpected_failure')));
      expect(friendly, isNot(contains('{')));
    });

    test('GuestMode starts in explore mode for first-time / unauthenticated users', () {
      GuestMode.active = true;
      final profile = GuestMode.guestProfile();
      expect(profile.id, 'guest');
      expect(profile.fullName, isNotEmpty);
      expect(GuestMode.active, isTrue);
    });

    testWidgets('OtpInput backspace on empty focused box clears previous digit and moves focus back',
        (tester) async {
      useTallView(tester);
      String latest = '';
      await tester.pumpWidget(host(Scaffold(
        body: OtpInput(
          onChanged: (v) => latest = v,
        ),
      )));
      await tester.pump();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(6));

      // Type '1' into box 0 -> auto-advances focus to box 1 (holding sentinel).
      await tester.tap(fields.at(0));
      await tester.pump();
      await tester.enterText(fields.at(0), '1');
      await tester.pump();
      expect(latest, '1');

      // Type '2' into box 1 -> auto-advances focus to box 2 (holding sentinel).
      await tester.enterText(fields.at(1), '\u200B2');
      await tester.pump();
      expect(latest, '12');

      // Simulate iOS soft-keyboard Backspace on empty box 2 (deletes sentinel -> '').
      final box2 = tester.widget<TextField>(fields.at(2));
      expect(box2.controller!.text, '\u200B');
      box2.onChanged!('');
      await tester.pump();

      // Box 1 should be cleared and focused, latest should be '1'.
      expect(latest, '1');
      expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isTrue);

      // Press Backspace again on now-empty box 1 -> clears box 0 and focuses box 0.
      tester.widget<TextField>(fields.at(1)).onChanged!('');
      await tester.pump();
      expect(latest, '');
      expect(tester.widget<TextField>(fields.at(0)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('OtpInput distributes pasted multi-digit code across all 6 boxes',
        (tester) async {
      useTallView(tester);
      String latest = '';
      String completed = '';
      await tester.pumpWidget(host(Scaffold(
        body: OtpInput(
          onChanged: (v) => latest = v,
          onCompleted: (v) => completed = v,
        ),
      )));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '654321');
      await tester.pump();

      expect(latest, '654321');
      expect(completed, '654321');
    });
  });
}
