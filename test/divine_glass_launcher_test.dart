import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inoapp/core/responsive/responsive.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/profile/profile_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/theme/theme_controller.dart';
import 'package:inoapp/theme/theme_style.dart';
import 'package:inoapp/widgets/common/liquid_glass.dart';
import 'package:inoapp/widgets/divine_glass/divine_glass.dart';
import 'package:inoapp/widgets/profile/settings_group.dart';
import 'package:inoapp/widgets/profile/settings_scaffold.dart';

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
    ThemeController.style.value = ThemeStyle.aqua;
  });

  testWidgets('Aqua Profile uses glassy settings groups (LiquidGlass)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrap(
        ProfileScreen(
          profile: profile,
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Profile'), findsOneWidget);
    expect(find.byType(SettingsGroup), findsWidgets);
  });

  testWidgets('Launcher Profile applies Divine Glass groups',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrap(
        ProfileScreen(
          profile: profile,
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
        ),
        style: ThemeStyle.launcher,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Profile'), findsOneWidget);
    expect(find.byType(SettingsGroup), findsWidgets);
  });

  testWidgets('Launcher AdaptiveGlassCard uses LiquidGlass', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Scaffold(
          body: AdaptiveGlassCard(
            child: Text('Glass body'),
          ),
        ),
        style: ThemeStyle.launcher,
      ),
    );
    await tester.pump();

    expect(find.text('Glass body'), findsOneWidget);
    expect(find.byType(LiquidGlass), findsOneWidget);
  });

  testWidgets('AquaMist AdaptiveGlassCard uses LiquidGlass', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Scaffold(
          body: AdaptiveGlassCard(
            child: Text('AquaMist body'),
          ),
        ),
        style: ThemeStyle.aquaMist,
      ),
    );
    await tester.pump();

    expect(find.text('AquaMist body'), findsOneWidget);
    expect(find.byType(LiquidGlass), findsOneWidget);
  });

  testWidgets('Launcher SettingsScaffold uses DivineGlassAppBar',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const SettingsScaffold(
          title: 'Pending Actions',
          child: SizedBox.shrink(),
        ),
        style: ThemeStyle.launcher,
      ),
    );
    await tester.pump();

    expect(find.text('Pending Actions'), findsOneWidget);
    expect(find.byType(DivineGlassAppBar), findsOneWidget);
    expect(find.byType(LiquidGlass), findsWidgets);
  });

  testWidgets('Aqua SettingsScaffold uses DivineGlassAppBar',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const SettingsScaffold(
          title: 'About',
          child: SizedBox.shrink(),
        ),
        style: ThemeStyle.aqua,
      ),
    );
    await tester.pump();

    expect(find.text('About'), findsOneWidget);
    expect(find.byType(DivineGlassAppBar), findsOneWidget);
  });
}
