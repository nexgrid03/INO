import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inoapp/core/responsive/responsive.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/home/home_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/theme/theme_controller.dart';
import 'package:inoapp/theme/theme_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
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

  Widget wrap(Widget child, {ThemeStyle style = ThemeStyle.aqua}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: InoStyleScope(
        style: style,
        child: InoResponsiveInit(child: child),
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeController.style.value = ThemeStyle.aqua;
  });

  testWidgets('Aqua Home renders launcher layout with My Vaults',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrap(
        HomeScreen(
          profile: profile,
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('My Vaults'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Pending Actions'), findsNothing);
  });

  testWidgets(
      'Launcher: first fold is Quick Actions → Vaults → Needs attention',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrap(
        HomeScreen(
          profile: profile,
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
        style: ThemeStyle.launcher,
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);

    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('My Vaults'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);

    // Merged attention module — no duplicate Pending / Reminders sections.
    expect(find.text('Pending Actions'), findsNothing);
    expect(find.text('Reminders'), findsNothing);

    // Previous Launcher quick actions (4) — short labels; Notes + Offline
    // share a chip row under Quick Actions (same layout as Expenses / Net Worth).
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Reminder'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Scan Document'), findsNothing);
    expect(find.text('Voice Assistant'), findsNothing);

    // Summary tiles live inside Needs attention.
    expect(find.text('Expiring'), findsOneWidget);
    expect(find.text('EMI Due'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Insurance'), findsOneWidget);

    // Order: Quick Actions → Notes/Offline row → My Vaults → Needs attention.
    final quickY = tester.getTopLeft(find.text('Quick Actions')).dy;
    final notesY = tester.getTopLeft(find.text('Notes')).dy;
    final offlineY = tester.getTopLeft(find.text('Offline')).dy;
    final vaultsY = tester.getTopLeft(find.text('My Vaults')).dy;
    final needsY = tester.getTopLeft(find.text('Needs attention')).dy;
    final expiringY = tester.getTopLeft(find.text('Expiring')).dy;
    expect(quickY, lessThan(notesY));
    expect(quickY, lessThan(offlineY));
    expect(notesY, lessThan(vaultsY));
    expect(offlineY, lessThan(vaultsY));
    expect(vaultsY, lessThan(needsY));
    expect(needsY, lessThan(expiringY));

    // Hub shortcuts demoted below tools (still reachable).
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Net Worth'), findsOneWidget);
    final toolsY =
        tester.getTopLeft(find.text('Property & Finance Tools')).dy;
    final expensesY = tester.getTopLeft(find.text('Expenses')).dy;
    expect(toolsY, lessThan(expensesY));

    expect(find.text('Property & Finance Tools'), findsOneWidget);
    // Market Snapshot was removed from Home in 629f0a2 — assert it stays gone.
    expect(find.text('Market Snapshot'), findsNothing);

    // Old Today/Tomorrow/Completed summary removed.
    expect(find.text('Today'), findsNothing);
    expect(find.text('This Week'), findsNothing);
    expect(find.text('Completed'), findsNothing);
  });
}
