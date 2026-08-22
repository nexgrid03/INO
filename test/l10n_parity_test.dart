import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/l10n/app_localizations.dart';

/// Guards the promise that switching language changes *every* string.
///
/// The translation table is a plain Dart map, so a new key added to `en` and
/// forgotten in `hi` / `te` compiles fine and silently falls back to English -
/// exactly the drift that leaves half a screen untranslated. These tests parse
/// the table straight from source and fail the build when that happens.
void main() {
  final source = File('lib/l10n/app_localizations.dart').readAsStringSync();

  /// `key: value` where the value may sit on the next line and may be written
  /// as several adjacent string literals.
  // Triple-quoted raw string: the pattern needs both quote characters, which a
  // single-quoted raw string cannot escape.
  final entry = RegExp(
    r'''  '([A-Za-z0-9_]+)':\s*((?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")(?:\s*(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"))*)\s*,'''
        .trim(),
    dotAll: true,
  );

  Map<String, String> blockFor(String lang) {
    final start = source.indexOf("  '$lang': {");
    // Plain throw, not expect(): this runs while collecting tests, where the
    // matcher library has no active test to attach a failure to.
    if (start < 0) throw StateError("no '$lang' block in the translation table");
    // The block ends where the next language begins, or at the map's close.
    var end = source.length;
    for (final other in const ['en', 'hi', 'te']) {
      final at = source.indexOf("  '$other': {");
      if (at > start && at < end) end = at;
    }
    return {
      for (final m in entry.allMatches(source.substring(start, end)))
        m.group(1)!: m.group(2)!,
    };
  }

  final en = blockFor('en');
  final hi = blockFor('hi');
  final te = blockFor('te');

  test('the table actually parsed', () {
    expect(en.length, greaterThan(1000));
  });

  for (final (name, table) in [('hi', hi), ('te', te)]) {
    test('$name translates every English key', () {
      final missing = en.keys.where((k) => !table.containsKey(k)).toList()
        ..sort();
      expect(
        missing,
        isEmpty,
        reason: '${missing.length} key(s) fall back to English in $name: '
            '${missing.take(20).join(', ')}',
      );
    });

    test('$name has no key the English table lacks', () {
      // A key only in hi/te renders as the raw key name in English.
      final orphans = table.keys.where((k) => !en.containsKey(k)).toList()
        ..sort();
      expect(orphans, isEmpty,
          reason: 'would render as raw key names in English: $orphans');
    });

    test('$name keeps every {placeholder} intact', () {
      final token = RegExp(r'\{(\w+)\}');
      final broken = <String>[];
      for (final k in en.keys) {
        final translated = table[k];
        if (translated == null) continue;
        final expected =
            token.allMatches(en[k]!).map((m) => m.group(1)!).toSet();
        final actual =
            token.allMatches(translated).map((m) => m.group(1)!).toSet();
        if (expected.length != actual.length ||
            !expected.every(actual.contains)) {
          broken.add('$k (expected $expected, got $actual)');
        }
      }
      // A dropped {name} renders the placeholder literally to the user.
      expect(broken, isEmpty, reason: broken.join('; '));
    });

    test('$name has no empty translations', () {
      final empty = table.entries
          .where((e) => e.value.replaceAll(RegExp("['\"]"), '').trim().isEmpty)
          .map((e) => e.key)
          .toList();
      expect(empty, isEmpty);
    });
  }

  test('lookups resolve in every supported locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      // A key that resolves to itself means no translation was found at all.
      expect(l10n.t('home'), isNot('home'),
          reason: 'nothing resolved for ${locale.languageCode}');
    }
  });

  test('the service-side accessor follows the active language', () {
    final original = AppLocalizations.activeLanguageCode;
    addTearDown(() => AppLocalizations.activeLanguageCode = original);

    AppLocalizations.activeLanguageCode = 'hi';
    final inHindi = AppLocalizations.current.t('home');
    AppLocalizations.activeLanguageCode = 'te';
    final inTelugu = AppLocalizations.current.t('home');

    expect(inHindi, equals(const AppLocalizations(Locale('hi')).t('home')));
    expect(inTelugu, isNot(inHindi));
  });
}
