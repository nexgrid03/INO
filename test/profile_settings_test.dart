import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/screens/legal/legal_document_screen.dart';
import 'package:inoapp/screens/profile/change_password_screen.dart';
import 'package:inoapp/screens/profile/help_center_screen.dart';
import 'package:inoapp/services/account_service.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/utils/formatting.dart';

void main() {
  group('Formatting helpers', () {
    test('formatBytes uses binary units with sensible precision', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    });
  });

  group('Password strength', () {
    test('scores from weak to strong', () {
      expect(AccountService.scorePassword('abc'), PasswordStrength.weak);
      expect(AccountService.scorePassword('abcdefg1'), isNot(PasswordStrength.weak));
      expect(
        AccountService.scorePassword('Str0ng!Passw0rd#2026'),
        PasswordStrength.strong,
      );
    });
  });

  testWidgets('Change Password validates before submitting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ChangePasswordScreen(email: 'user@example.com'),
      ),
    );
    await tester.pump();

    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Current password'), findsOneWidget);

    // Tapping update with empty fields surfaces validation, not a backend call.
    await tester.tap(find.text('Update Password'));
    await tester.pump();
    expect(find.text('Enter your current password'), findsOneWidget);
  });

  testWidgets('Help Center filters FAQs as you search', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const HelpCenterScreen(),
      ),
    );
    await tester.pump();

    expect(find.textContaining('How do I add a document?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'delete account');
    await tester.pump();

    expect(find.textContaining('How do I delete my account?'), findsOneWidget);
    expect(find.textContaining('How do I add a document?'), findsNothing);
  });

  testWidgets('Legal pages render bundled content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: LegalDocumentScreen.privacy()),
    );
    await tester.pump();
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: LegalDocumentScreen.terms()),
    );
    await tester.pump();
    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Acceptance'), findsOneWidget);
  });
}
