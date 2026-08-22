import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inoapp/l10n/app_localizations.dart';

/// Proves the language switch actually reaches rendered widgets.
///
/// The parity test guarantees the table is complete; this one guarantees the
/// wiring — that a locale change rebuilds `Localizations` dependants and the
/// text on screen really changes, rather than staying frozen in English.
void main() {
  /// A stand-in for any screen: reads its copy through [AppLocalizations] the
  /// same way the real widgets do.
  Widget app(Locale locale) => MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Column(
                children: [
                  Text(l10n.t('home')),
                  Text(l10n.t('profile')),
                  Text(l10n.t('save')),
                  Text(l10n.t('cancel')),
                  Text(l10n.t('documents')),
                ],
              ),
            );
          },
        ),
      );

  testWidgets('switching locale re-renders every string', (tester) async {
    await tester.pumpWidget(app(const Locale('en')));
    final english = [
      for (final w in tester.widgetList<Text>(find.byType(Text))) w.data,
    ];

    for (final code in ['hi', 'te']) {
      await tester.pumpWidget(app(Locale(code)));
      await tester.pumpAndSettle();

      final translated = [
        for (final w in tester.widgetList<Text>(find.byType(Text))) w.data,
      ];

      expect(translated.length, english.length);
      for (var i = 0; i < translated.length; i++) {
        expect(
          translated[i],
          isNot(english[i]),
          reason: '"${english[i]}" did not change in $code — the widget is '
              'not following the active locale',
        );
        expect(translated[i]?.trim(), isNotEmpty);
      }
    }
  });

  testWidgets('an unsupported locale falls back to English, never to keys',
      (tester) async {
    await tester.pumpWidget(app(const Locale('fr')));
    await tester.pumpAndSettle();

    final rendered = [
      for (final w in tester.widgetList<Text>(find.byType(Text))) w.data,
    ];
    // A raw key leaking to screen looks like 'someKey'; real copy does not.
    for (final text in rendered) {
      expect(text, isNotNull);
      expect(RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(text!), isFalse,
          reason: '"$text" looks like an unresolved translation key');
    }
  });
}
