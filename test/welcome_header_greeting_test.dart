import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/dashboard/welcome_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  String timeGreeting() {
    final h = DateTime.now().hour;
    if (h < 5 || h >= 21) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );
  }

  Future<void> pumpHeader(
    WidgetTester tester, {
    required TargetPlatform platform,
    required String fullName,
    required bool launcherStyle,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      wrap(
        WelcomeHeader(
          fullName: fullName,
          onNotifications: () {},
          launcherStyle: launcherStyle,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('Android launcher greeting still shows Hi and the first name',
      (tester) async {
    await onPlatform(TargetPlatform.android, () async {
      await pumpHeader(
        tester,
        platform: TargetPlatform.android,
        fullName: 'Rahul Kumar',
        launcherStyle: true,
      );
      expect(find.text('Hi, Rahul'), findsOneWidget);
    });
  });

  testWidgets('iOS launcher greeting shows Hi and the first name',
      (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpHeader(
        tester,
        platform: TargetPlatform.iOS,
        fullName: 'Rahul Kumar',
        launcherStyle: true,
      );
      expect(find.text('Hi, Rahul'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Hi, Rahul'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('time-of-day greeting and a blank name stay safe on iOS',
      (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpHeader(
        tester,
        platform: TargetPlatform.iOS,
        fullName: '   ',
        launcherStyle: false,
      );
      expect(find.textContaining('${timeGreeting()}, there'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.textContaining('${timeGreeting()}, there'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Android time-of-day greeting text is unchanged', (tester) async {
    await onPlatform(TargetPlatform.android, () async {
      await pumpHeader(
        tester,
        platform: TargetPlatform.android,
        fullName: 'Rahul Kumar',
        launcherStyle: false,
      );
      expect(find.textContaining('${timeGreeting()}, Rahul'), findsOneWidget);
    });
  });
}
