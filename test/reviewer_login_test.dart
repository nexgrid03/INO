import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/config/demo_account.dart';
import 'package:inoapp/screens/auth/login_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

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

  group('Apple Reviewer Login Tests', () {
    test('isReviewerIdentifier identifies reviewer and demo accounts correctly', () {
      expect(isReviewerIdentifier('reviewer@ino.app'), isTrue);
      expect(isReviewerIdentifier('apple.review@ino.app'), isTrue);
      expect(isReviewerIdentifier('demo@ino.app'), isTrue);
      expect(isReviewerIdentifier('REVIEWER@INO.APP'), isTrue);
      expect(isReviewerIdentifier(' reviewer@ino.app '), isTrue);
      expect(isReviewerIdentifier('reviewer@customdomain.com'), isTrue);
      expect(isReviewerIdentifier('apple.review@custom.com'), isTrue);

      // Normal user accounts should NEVER be identified as reviewer
      expect(isReviewerIdentifier('user@gmail.com'), isFalse);
      expect(isReviewerIdentifier('john.doe@example.com'), isFalse);
      expect(isReviewerIdentifier('+919876543210'), isFalse);
      expect(isReviewerIdentifier(''), isFalse);
    });

    testWidgets('Normal login starts in OTP mode with App Reviewer toggle available',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signIn)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewer_password_field')), findsNothing);
      expect(find.byKey(const ValueKey('reviewer_login_toggle')), findsOneWidget);
      expect(find.text('App Reviewer Login'), findsOneWidget);
    });

    testWidgets('Tapping App Reviewer Login activates password field and updates CTA to Sign In',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signIn)));
      await tester.pump(const Duration(milliseconds: 500));

      final toggleFinder = find.byKey(const ValueKey('reviewer_login_toggle'));
      await tester.ensureVisible(toggleFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap App Reviewer Login
      await tester.tap(toggleFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // Password field and Reviewer CTA should be visible
      expect(find.byKey(const ValueKey('reviewer_password_field')), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Send OTP'), findsNothing);
      expect(find.text('Back to OTP sign-in'), findsOneWidget);

      // Tapping back should return to OTP mode
      await tester.ensureVisible(toggleFinder);
      await tester.tap(toggleFinder);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('reviewer_password_field')), findsNothing);
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.text('App Reviewer Login'), findsOneWidget);
    });

    testWidgets('Typing reviewer email automatically shows password field without toggle click',
        (tester) async {
      useTallView(tester);
      await tester.pumpWidget(host(const LoginScreen(initialMode: AuthMode.signIn)));
      await tester.pump(const Duration(milliseconds: 500));

      final identifierField = find.byKey(const ValueKey('login_identifier_field'));
      expect(identifierField, findsOneWidget);

      // Type normal email - password field should not appear
      await tester.enterText(identifierField, 'normaluser@gmail.com');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('reviewer_password_field')), findsNothing);
      expect(find.text('Send OTP'), findsOneWidget);

      // Type reviewer email - password field should appear automatically
      await tester.enterText(identifierField, 'apple.review@ino.app');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('reviewer_password_field')), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });
  });
}
