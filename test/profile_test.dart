import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/profile/edit_profile_screen.dart';
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

    // Large title + compact identity header (name, email, one subtle badge).
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Tanishq Sharma'), findsWidgets);
    expect(find.text('tanishq@example.com'), findsOneWidget);
    expect(find.text('Vault protected'), findsOneWidget);

    // Grouped settings captions (rendered uppercase).
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('DATA & STORAGE'), findsOneWidget);
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('LEGAL'), findsOneWidget);

    // Representative rows + toggles across the groups.
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Biometric Authentication'), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('About INO'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);

    // Destructive actions sit quietly at the bottom.
    expect(find.text('Delete Account'), findsOneWidget);
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

    final logoutRow = find.widgetWithText(InkWell, 'Logout');
    await tester.ensureVisible(logoutRow);
    await tester.pumpAndSettle();
    await tester.tap(logoutRow);
    await tester.pumpAndSettle();

    // Confirmation modal appears; we cancel (tapping "Log Out" would hit
    // Supabase, which isn't initialised in tests).
    expect(find.text('Log out of INO?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Log out of INO?'), findsNothing);
  });

  testWidgets('Edit Profile prefills editable fields and locks email',
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
        home: EditProfileScreen(profile: _profile()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Profile'), findsOneWidget);

    // Three fields: name, email, phone — with the name pre-filled & editable.
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.widgetWithText(TextFormField, 'Tanishq Sharma'), findsOneWidget);

    // Email is shown but read-only (its field is disabled).
    final emailField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'tanishq@example.com'),
    );
    expect(emailField.enabled, isFalse);

    expect(find.text('Save Changes'), findsOneWidget);
  });
}
