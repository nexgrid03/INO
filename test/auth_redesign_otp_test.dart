import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/country_code.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/auth/login_screen.dart';
import 'package:inoapp/screens/auth/otp_verification_screen.dart';
import 'package:inoapp/services/auth_service.dart';
import 'package:inoapp/services/guest_mode.dart';
import 'package:inoapp/theme/app_theme.dart';
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
    testWidgets('LoginScreen renders Create Account mode with Name, Email, Mobile & OTP channel toggle',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signUp)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Join the Vault'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Verification Method'), findsOneWidget);
      expect(find.text('Email OTP'), findsOneWidget);
      expect(find.text('Mobile OTP'), findsOneWidget);
      expect(find.text('Send Verification Code'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('LoginScreen renders Existing User Sign In mode with Phone & Email OTP tabs',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signIn)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Mobile OTP'), findsOneWidget);
      expect(find.text('Email OTP'), findsOneWidget);
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.text('Sign in with Password instead'), findsOneWidget);

      // Tap Email OTP tab
      await tester.tap(find.text('Email OTP'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
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
    });

    test('GuestMode starts in explore mode for first-time / unauthenticated users', () {
      GuestMode.active = true;
      final profile = GuestMode.guestProfile();
      expect(profile.id, 'guest');
      expect(profile.fullName, isNotEmpty);
      expect(GuestMode.active, isTrue);
    });
  });
}
