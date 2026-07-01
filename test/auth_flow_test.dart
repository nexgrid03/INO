import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/auth/biometric_setup_screen.dart';
import 'package:inoapp/screens/auth/complete_profile_screen.dart';
import 'package:inoapp/screens/auth/forgot_password_screen.dart';
import 'package:inoapp/screens/auth/login_screen.dart';
import 'package:inoapp/screens/auth/otp_verification_screen.dart';
import 'package:inoapp/screens/auth/signup_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

/// The auth screens are UI-only until the user acts, so they must build and
/// render their key affordances without a live Supabase/biometric backend —
/// never throwing in the test host.
void main() {
  // A generously tall window so the content-heavy forms lay out without
  // overflow warnings during the render checks.
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: child);

  testWidgets('Login renders sign-in, social and create-account affordances',
      (tester) async {
    useTallView(tester);
    await tester.pumpWidget(host(const LoginScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('Signup renders all five fields and the CTA', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(host(const SignupScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.widgetWithText(GestureDetector, 'Create Account'),
        findsOneWidget);
  });

  testWidgets('Forgot Password validates and shows its reset CTA',
      (tester) async {
    useTallView(tester);
    await tester.pumpWidget(host(const ForgotPasswordScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Send Verification Code'), findsOneWidget);
  });

  testWidgets('OTP screen renders six boxes, countdown and Verify',
      (tester) async {
    useTallView(tester);
    await tester.pumpWidget(host(
      OtpVerificationScreen(
        destination: 'you@example.com',
        onVerify: (_) async => true,
        onVerified: (_) {},
        onResend: () async {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Verification Code'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(6)); // six OTP boxes
    expect(find.text('Verify'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);
  });

  testWidgets('Complete Profile renders name + phone fields and Continue',
      (tester) async {
    useTallView(tester);
    await tester.pumpWidget(host(
      const CompleteProfileScreen(
        authUserId: 'auth1',
        fullName: 'Ada Lovelace',
        email: 'ada@example.com',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Complete Your Profile'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // Name is pre-filled from the Google identity; phone starts empty.
    expect(find.widgetWithText(TextFormField, 'Ada Lovelace'), findsOneWidget);
  });

  testWidgets('Biometric Setup renders illustration, enable and skip',
      (tester) async {
    useTallView(tester);
    final profile = UserProfile(
      id: 'u1',
      authUserId: 'auth1',
      fullName: 'Test User',
      email: 'test@example.com',
      preferredLanguage: 'en',
      biometricEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await tester.pumpWidget(host(BiometricSetupScreen(profile: profile)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Secure Your Vault'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });
}
