import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/profile/profile_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

UserProfile _profile() => UserProfile(
      id: '1',
      authUserId: 'a',
      fullName: 'Tanishq Sharma',
      email: 'tanishq@example.com',
      phone: '+91 98765 43210',
      preferredLanguage: 'en',
      biometricEnabled: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('Profile screen renders all account & settings sections',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileScreen(
          profile: _profile(),
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);

    // Header + identity.
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Tanishq Sharma'), findsWidgets);
    expect(find.text('tanishq@example.com'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);

    // Account status + storage.
    expect(find.text('Account Active'), findsOneWidget);
    expect(find.text('Cloud Synced'), findsOneWidget);
    expect(find.text('1.2 GB'), findsOneWidget);

    // Every section title.
    expect(find.text('Security Center'), findsOneWidget);
    expect(find.text('Data & Storage'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);

    // A few representative rows + toggles.
    expect(find.text('Biometric Authentication'), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('About INO'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);

    // Logout at the bottom.
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('Logout asks for confirmation before signing out',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileScreen(
          profile: _profile(),
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    await tester.ensureVisible(find.text('Logout'));
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    // Confirmation modal appears; we cancel (tapping "Log Out" would hit
    // Supabase, which isn't initialised in tests).
    expect(find.text('Log out of INO?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Log out of INO?'), findsNothing);
  });
}
