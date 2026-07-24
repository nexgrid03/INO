import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/wallet/wallet_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  testWidgets('Wallet Hub is a launcher: summary + all 8 wallets, no overview',
      (tester) async {
    final profile = UserProfile(
      id: '1',
      authUserId: 'a',
      fullName: 'Tanishq Sharma',
      email: 't@example.com',
      preferredLanguage: 'en',
      biometricEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WalletScreen(profile: profile),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);

    // All 8 wallets are present (the launcher grid).
    for (final name in const [
      'Identity Wallet',
      'Document Wallet',
      'Property Wallet',
      'Insurance Wallet',
      'Health Wallet',
      'Investment Wallet',
      'Banking Wallet',
      'Password Vault',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '$name missing');
    }

    // The Vault Overview analytics card is gone.
    expect(find.text('Vault Overview'), findsNothing);
    expect(find.text('Storage used'), findsNothing);
  });
}
