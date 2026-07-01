import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/auth/biometric_unlock_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  testWidgets('Biometric Unlock Screen renders locked vault UI',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final profile = UserProfile(
      id: '1',
      authUserId: 'a',
      fullName: 'Tanishq Sharma',
      email: 't@example.com',
      preferredLanguage: 'en',
      biometricEnabled: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    bool unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BiometricUnlockScreen(
          profile: profile,
          onUnlocked: () => unlocked = true,
        ),
      ),
    );

    // Initial check (renders elements)
    expect(find.text('Vault Locked'), findsOneWidget);
    expect(find.text('Unlock Vault'), findsOneWidget);
    expect(find.text('Switch Account'), findsOneWidget);

    // Let the auto-authentication complete
    await tester.pump(const Duration(seconds: 1));
    expect(unlocked, isTrue);
    expect(tester.takeException(), isNull);
  });
}
