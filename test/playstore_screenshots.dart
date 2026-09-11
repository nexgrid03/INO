import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inoapp/core/responsive/responsive.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/home/home_screen.dart';
import 'package:inoapp/screens/onboarding/onboarding_screen.dart';
import 'package:inoapp/screens/property_finance/property_finance_tools_screen.dart';
import 'package:inoapp/screens/reminders/reminders_screen.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/screens/wallet/wallet_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/theme/theme_controller.dart';
import 'package:inoapp/theme/theme_style.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Renders each Play Store screen at exactly 1080x1920 (9:16) and writes it to
/// test/screenshots/.
///
/// Deliberately NOT named *_test.dart: this is a capture tool, not a test, so
/// `flutter test` skips it. Run it explicitly with:
///   flutter test test/playstore_screenshots.dart --update-goldens
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;

    // Widget tests draw every glyph as a filled box unless a real typeface is
    // registered under the exact family the theme asks for. AppTheme uses
    // GoogleFonts.manrope(), whose family strings are "Manrope_<variant>", and
    // Manrope is not bundled in assets - so borrow Segoe UI under those names.
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

    await register('Manrope', regular);
    await register('Manrope_regular', regular);
    await register('Manrope_italic', regular);
    for (final w in [100, 200, 300]) {
      await register('Manrope_$w', light);
    }
    for (final w in [400, 500]) {
      await register('Manrope_$w', regular);
    }
    for (final w in [600, 700, 800, 900]) {
      await register('Manrope_$w', bold);
    }


    // The engine's test-bundled icon font is older than the SDK's, so newer
    // Material icons come out as empty boxes. Load the real one.
    await register(
      'MaterialIcons',
      r'C:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    );
  });

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Screens that read Supabase otherwise hang on an "initialize first"
    // assertion and never leave their loading gate. A throwaway instance lets
    // every query fail fast, so each screen renders its real layout.
    try {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test-anon-key',
        debug: false,
      );
    } catch (_) {
      // Already initialised, or unavailable - no worse off than before.
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeController.style.value = ThemeStyle.aqua;
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

  Widget wrap(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: InoStyleScope(
          style: ThemeStyle.aqua,
          child: InoResponsiveInit(child: child),
        ),
      );

  /// One phone frame: 1080x1920 physical == exactly 9:16, which is what the
  /// Play Console accepts.
  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Future<void> Function(WidgetTester)? after,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(screen));
    // Never pumpAndSettle: several screens own perpetual ambient loops. Pump a
    // generous run of frames instead so async loads and entrances finish.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    // Fake-time pumps do not advance real I/O, so screens waiting on a network
    // round-trip stay on their spinner. Give the real event loop a moment.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (after != null) await after(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('01 home', (t) => shoot(t, '01_home', HomeScreen(profile: profile)));

  testWidgets('02 wallets',
      (t) => shoot(t, '02_wallets', WalletScreen(profile: profile)));

  testWidgets('03 identity wallet',
      (t) => shoot(t, '03_identity_wallet',
          const WalletDetailScreen(category: identityWallet)));

  testWidgets('04 reminders',
      (t) => shoot(t, '04_reminders', RemindersScreen(profile: profile)));

  testWidgets('05 finance tools',
      (t) => shoot(t, '05_finance_tools', const PropertyFinanceToolsScreen()));

  testWidgets('06 onboarding QR', (t) async {
    await shoot(t, '06_onboarding_qr', const OnboardingScreen(),
        after: (tester) async {
      // Swipe to the third slide - the QR / share one.
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
