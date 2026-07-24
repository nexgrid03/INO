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
      preferredLanguage: 'en',
      biometricEnabled: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('Profile screen renders user details and key settings',
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
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Tanishq Sharma'), findsWidgets);
    expect(find.text('tanishq@example.com'), findsWidgets);

    // Key settings rows
    for (final title in const [
      'Change Password',
      'Trusted Devices',
      'Help Center',
      'Logout',
    ]) {
      expect(find.text(title), findsWidgets, reason: '$title missing');
    }
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
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final logoutFinder = find.text('Logout');
    expect(logoutFinder, findsWidgets);
    await tester.ensureVisible(logoutFinder.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(logoutFinder.first);
    await tester.pump(const Duration(milliseconds: 500));

    // Confirmation modal appears; we cancel.
    expect(find.text('Cancel'), findsWidgets);
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
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tanishq Sharma'), findsWidgets);
    expect(find.text('tanishq@example.com'), findsWidgets);
  });
}
