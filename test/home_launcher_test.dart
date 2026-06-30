import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/home/home_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  testWidgets('Home is a minimal launcher: 6 sections, no duplicated modules',
      (tester) async {
    // Tall phone canvas so every section is laid out (default 800×600 would
    // clip the lower sliver children before they build).
    tester.view.physicalSize = const Size(1200, 6000);
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
      biometricEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          profile: profile,
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450)); // repo load
    await tester.pump(const Duration(milliseconds: 600)); // entrance

    expect(tester.takeException(), isNull);

    // The six focused sections.
    expect(find.text('Total Net Worth'), findsOneWidget);
    expect(find.text('Priority Center'), findsOneWidget);
    expect(find.text('Market Snapshot'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);

    // Hero shows the four headline metrics — and only those.
    for (final m in const ['Assets', 'Documents', 'Pending', 'Protected']) {
      expect(find.text(m), findsOneWidget);
    }

    // The five quick actions are present (some labels, e.g. "Reminder", also
    // appear as a priority status chip — so assert presence, not uniqueness).
    for (final a in const ['Scan', 'Document', 'Wallet', 'Reminder', 'More']) {
      expect(find.text(a), findsWidgets);
    }

    // Removed / module-owned sections must NOT appear on Home anymore.
    for (final gone in const [
      'Life Overview',
      'Wallet Ecosystem',
      'Family & Events',
      'Investments',
      'Smart Insights',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone should be gone');
    }
  });
}
