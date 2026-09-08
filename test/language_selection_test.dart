import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/screens/language/language_selection_screen.dart';
import 'package:inoapp/services/app_settings.dart';
import 'package:inoapp/widgets/ino_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsCache.init();
    await AppSettings.instance.load();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  testWidgets('LanguageSelectionScreen renders INO shield logo, header badge, title and language options', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestableWidget(const LanguageSelectionScreen()));
    await tester.pump(const Duration(milliseconds: 600));

    // Verify INO Shield Logo at the top
    expect(find.byType(InoLogo), findsOneWidget);

    // Verify Pill header
    expect(find.text('भाषा • Language'), findsOneWidget);

    // Verify Title and Subtitle
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('You can change this anytime in Settings'), findsOneWidget);

    // Verify Language Options
    expect(find.text('English'), findsOneWidget);
    expect(find.text('English (अंग्रेज़ी)'), findsOneWidget);
    expect(find.text('हिंदी'), findsOneWidget);
    expect(find.text('Hindi (हिंदी)'), findsOneWidget);
    expect(find.text('తెలుగు'), findsOneWidget);
    expect(find.text('Telugu (తెలుగు)'), findsOneWidget);

    // Verify Continue button
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Tapping a language card selects it and Continue persists it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    bool continued = false;
    await tester.pumpWidget(
      buildTestableWidget(
        LanguageSelectionScreen(
          onContinue: () {
            continued = true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Tap Hindi
    await tester.tap(find.text('हिंदी'));
    await tester.pump(const Duration(milliseconds: 300));

    // Tap Continue
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(continued, isTrue);
    expect(AppSettings.instance.language.value, 'hi');
  });
}
