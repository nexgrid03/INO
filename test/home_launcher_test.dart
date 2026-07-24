import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/responsive/responsive.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/home/home_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
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

  testWidgets('Home is a minimal launcher: 6 sections, no duplicated modules',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: InoResponsiveInit(
          child: HomeScreen(
            profile: profile,
            themeMode: ThemeMode.light,
            onToggleTheme: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);

    // The focused sections on redesigned Home.
    expect(find.text("Today's Overview"), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Property & Finance Tools'), findsOneWidget);
    expect(find.text('Market Snapshot'), findsOneWidget);

    // Today's Overview summary cards.
    for (final m in const [
      'Documents Expiring',
      'EMI Due Tomorrow',
      'Reminders Today',
      'Insurance Renewals'
    ]) {
      expect(find.text(m), findsOneWidget);
    }

    // The 4 Quick Actions.
    for (final a in const ['Documents', 'Notes', 'Expenses', 'Scanner']) {
      expect(find.text(a), findsWidgets);
    }
  });

  // Verification across standard target device viewports
  const viewports = <String, Size>{
    '360x640 Small Phone': Size(360, 640),
    '393x851 Normal Phone': Size(393, 851),
    '412x915 Large Phone': Size(412, 915),
    '480x960 Extra Large Phone': Size(480, 960),
    '768x1024 Tablet': Size(768, 1024),
  };

  for (final entry in viewports.entries) {
    testWidgets('Home renders without exceptions or overflows on ${entry.key}',
        (tester) async {
      tester.view.physicalSize = Size(entry.value.width * 2, entry.value.height * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: InoResponsiveInit(
            child: HomeScreen(
              profile: profile,
              themeMode: ThemeMode.light,
              onToggleTheme: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text("Today's Overview"), findsOneWidget);
    });
  }
}
