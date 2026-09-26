import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inoapp/core/responsive/responsive.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/home/home_screen.dart';
import 'package:inoapp/screens/property_finance/property_finance_tools_screen.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/screens/wallet/wallet_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/theme/theme_style.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = true;

    Future<void> register(String family, String path) async {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }

    const regular = r'C:\Windows\Fonts\segoeui.ttf';
    const bold = r'C:\Windows\Fonts\segoeuib.ttf';
    const light = r'C:\Windows\Fonts\segoeuil.ttf';

    final names = [
      'Manrope',
      'Manrope-Regular',
      'Manrope-Medium',
      'Manrope-SemiBold',
      'Manrope-Bold',
      'Manrope-Light',
      'Manrope-ExtraBold',
      'Manrope_regular',
      'Manrope_italic',
      'PlusJakartaSans',
      'PlusJakartaSans-Regular',
      'PlusJakartaSans-Medium',
      'PlusJakartaSans-SemiBold',
      'PlusJakartaSans-Bold',
    ];
    for (final name in names) {
      await register(name, regular);
    }
    for (final w in [100, 200, 300]) {
      await register('Manrope_$w', light);
      await register('PlusJakartaSans_$w', light);
    }
    for (final w in [400, 500]) {
      await register('Manrope_$w', regular);
      await register('PlusJakartaSans_$w', regular);
    }
    for (final w in [600, 700, 800, 900]) {
      await register('Manrope_$w', bold);
      await register('PlusJakartaSans_$w', bold);
    }

    // Material icons
    final root = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
    final iconFile = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (iconFile.existsSync()) {
      await register('MaterialIcons', iconFile.path);
    }

    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-anon-key',
        
        debug: false,
      );
    } catch (_) {}
  });

  final profile = UserProfile(
    id: '1',
    authUserId: 'a',
    fullName: 'Tanishq Sharma',
    email: 'tanishq@example.com',
    preferredLanguage: 'en',
    biometricEnabled: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  const identityWallet = WalletCategory(
    name: 'Identity Wallet',
    icon: Icons.badge_rounded,
    contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
    metric: '5',
    metricLabel: 'documents',
    gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
  );

  Widget wrapTheme(Widget child, {required ThemeStyle style, required ThemeData theme}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: InoStyleScope(
          style: style,
          child: InoResponsiveInit(child: child),
        ),
      );

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget screen, {
    ThemeStyle style = ThemeStyle.launcher,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrapTheme(screen, style: style, theme: theme ?? AppTheme.light));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  // Sky Blue / Launcher Style
  testWidgets('launcher home',
      (t) => capture(t, 'launcher_01_home', HomeScreen(profile: profile), style: ThemeStyle.launcher));
  testWidgets('launcher wallets',
      (t) => capture(t, 'launcher_02_wallets', WalletScreen(profile: profile), style: ThemeStyle.launcher));
  testWidgets('launcher identity',
      (t) => capture(t, 'launcher_03_identity', const WalletDetailScreen(category: identityWallet), style: ThemeStyle.launcher));
  testWidgets('launcher finance',
      (t) => capture(t, 'launcher_04_finance', const PropertyFinanceToolsScreen(), style: ThemeStyle.launcher));

  // Dark Theme
  testWidgets('dark home',
      (t) => capture(t, 'dark_01_home', HomeScreen(profile: profile), style: ThemeStyle.aqua, theme: AppTheme.dark));
  testWidgets('dark wallets',
      (t) => capture(t, 'dark_02_wallets', WalletScreen(profile: profile), style: ThemeStyle.aqua, theme: AppTheme.dark));
  testWidgets('dark identity',
      (t) => capture(t, 'dark_03_identity', const WalletDetailScreen(category: identityWallet), style: ThemeStyle.aqua, theme: AppTheme.dark));
  testWidgets('dark finance',
      (t) => capture(t, 'dark_04_finance', const PropertyFinanceToolsScreen(), style: ThemeStyle.aqua, theme: AppTheme.dark));
}
