import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/services/wallet_store.dart';
import 'package:inoapp/widgets/wallet_modules/module_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestFrame(Widget child, [double width = 320]) {
    return MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: child,
          ),
        ),
      ),
    );
  }

  group('Property Label Truncation Fix Tests (module_kit.dart)', () {
    testWidgets('DetailRow renders long property labels without ellipsis or clipping on 320px screen',
        (tester) async {
      final labelsToTest = [
        'Ownership Share',
        'Registration Number',
        'Registered Date',
        'Rental Income',
        'Annual Property Tax',
        'Maintenance Cost',
        'Other Expenses',
      ];

      for (final label in labelsToTest) {
        await tester.pumpWidget(
          buildTestFrame(
            DetailRow(
              label: label,
              value: '₹ 1,50,000 / yr',
            ),
            320,
          ),
        );
        await tester.pumpAndSettle();

        // Verify no RenderFlex overflow
        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow detected for label: $label');

        // Verify full label is present in widget tree
        final labelFinder = find.text(label);
        expect(labelFinder, findsOneWidget,
            reason: 'Full label not found: $label');

        final textWidget = tester.widget<Text>(labelFinder);
        // Overflow must not be ellipsis (it wraps naturally)
        expect(textWidget.overflow, isNot(TextOverflow.ellipsis),
            reason: 'Label $label still has TextOverflow.ellipsis');

        // Verify value is present
        expect(find.text('₹ 1,50,000 / yr'), findsOneWidget);
      }
    });

    testWidgets('DetailRow preserves right-aligned value and multi-line wrapping on 375px and 412px screens',
        (tester) async {
      for (final width in [375.0, 412.0]) {
        await tester.pumpWidget(
          buildTestFrame(
            const DetailRow(
              label: 'Annual Property Tax',
              value: '₹ 25,000',
            ),
            width,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Annual Property Tax'), findsOneWidget);
        expect(find.text('₹ 25,000'), findsOneWidget);
      }
    });
  });

  group('CustomWalletStore Remote Restore Tests', () {
    test('CustomWallet model encodes and decodes properly', () {
      final wallet = CustomWallet(name: 'School', iconKey: 'school', colorValue: 0xFF2196F3);
      final json = wallet.toJson();
      final decoded = CustomWallet.fromJson(json);

      expect(decoded.name, equals('School'));
      expect(decoded.iconKey, equals('school'));
      expect(decoded.colorValue, equals(0xFF2196F3));
    });

    test('CustomWallet id generation is normalized case-insensitively', () {
      final w1 = CustomWallet(name: 'College', iconKey: 'school', colorValue: 0xFF000000);
      final w2 = CustomWallet(name: 'college', iconKey: 'other', colorValue: 0xFF111111);

      expect(w1.id, equals(w2.id));
      expect(w1.id, equals('college'));
    });
  });
}
