import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/card_models.dart';
import 'package:inoapp/models/investment_models.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/models/property_models.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/cards/cards_wallet_screen.dart';
import 'package:inoapp/screens/investments/investment_wallet_screen.dart';
import 'package:inoapp/screens/passwords/password_vault_screen.dart';
import 'package:inoapp/screens/property/property_wallet_screen.dart';
import 'package:inoapp/services/card_store.dart';
import 'package:inoapp/services/investment_store.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/property_store.dart';
import 'package:inoapp/theme/app_theme.dart';

WalletCategory _category(String name, IconData icon) => WalletCategory(
      name: name,
      icon: icon,
      contents: const [],
      metric: '0',
      metricLabel: 'records',
      gradient: const [AppColors.primaryGreen, AppColors.lightBlue],
    );

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() async {
    // No shared_preferences plugin in tests - the stores degrade to empty. They
    // are hydrated here (as `main()` does at startup) so each screen mounts
    // already-loaded and renders its empty state rather than a skeleton.
    PropertyStore.instance.reset();
    InvestmentStore.instance.reset();
    CardStore.instance.reset();
    PasswordStore.instance.reset();
    await PropertyStore.instance.ensureLoaded();
    await InvestmentStore.instance.ensureLoaded();
    await CardStore.instance.ensureLoaded();
    await PasswordStore.instance.ensureLoaded();
  });

  group('module screens render', () {
    testWidgets('Property Wallet shows its empty state', (tester) async {
      await _pumpScreen(
        tester,
        PropertyWalletScreen(
          category: _category('Property Wallet', Icons.home_work_rounded),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Property Wallet'), findsOneWidget);
      expect(find.text('No properties yet'), findsOneWidget);
      expect(find.text('Add property'), findsOneWidget);
    });

    testWidgets('Investment Wallet shows its empty state', (tester) async {
      await _pumpScreen(
        tester,
        InvestmentWalletScreen(
          category: _category('Investment Wallet', Icons.trending_up_rounded),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Investments'), findsOneWidget);
      expect(find.text('No investments yet'), findsOneWidget);
    });

    testWidgets('Banking Wallet shows the card empty state', (tester) async {
      await _pumpScreen(
        tester,
        CardsWalletScreen(
          category: _category('Banking Wallet', Icons.account_balance_rounded),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('My Cards'), findsOneWidget);
      expect(find.text('No cards saved'), findsOneWidget);
    });

    testWidgets('Password Vault stays locked without biometrics',
        (tester) async {
      await _pumpScreen(
        tester,
        PasswordVaultScreen(
          category: _category('Password Vault', Icons.lock_rounded),
        ),
      );
      expect(tester.takeException(), isNull);
      // The gate failed (no plugin), so no credential UI is built at all.
      expect(find.text('Passwords'), findsNothing);
    });
  });

  group('card security', () {
    test('a card only ever carries four digits', () {
      final card = SavedCard(
        id: 'c1',
        name: 'Travel',
        bank: 'HDFC Bank',
        kind: CardKind.debit,
        network: CardNetwork.visa,
        holderName: 'Tanishq Jasti',
        last4: '4821',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(card.last4.length, 4);
      expect(card.maskedNumber, '•••• •••• •••• 4821');
      expect(card.toJson().containsKey('cvv'), isFalse);
      expect(card.toJson().containsKey('number'), isFalse);
    });

    test('a legacy row holding a full number is truncated on read', () {
      // Defensive path: even if something wrote more than four digits, only the
      // last four survive into the model.
      final card = SavedCard.fromJson({
        'id': 'c2',
        'name': 'Old',
        'bank': 'X',
        'holderName': 'Y',
        'last4': '4111 1111 1111 1234',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });
      expect(card.last4, '1234');
    });

    test('expiry state is derived from the recorded month', () {
      final now = DateTime.now();
      final expired = SavedCard(
        id: 'c3',
        name: 'Old',
        bank: 'X',
        kind: CardKind.credit,
        network: CardNetwork.rupay,
        holderName: 'Y',
        last4: '0000',
        expiryMonth: 1,
        expiryYear: now.year - 1,
        createdAt: now,
        updatedAt: now,
      );
      expect(expired.isExpired, isTrue);
      expect(expired.isExpiringSoon, isFalse);
    });
  });

  group('password vault', () {
    test('strength rises with length and variety', () {
      expect(passwordStrength('abc'), PasswordStrength.weak);
      expect(passwordStrength('password'), PasswordStrength.fair);
      expect(passwordStrength(r'Str0ng!Passphrase#42'), PasswordStrength.strong);
    });

    test('the generator honours its recipe', () {
      const recipe = PasswordRecipe(length: 24, symbols: false);
      final generated = generatePassword(recipe);
      expect(generated.length, 24);
      expect(RegExp(r'[a-z]').hasMatch(generated), isTrue);
      expect(RegExp(r'[A-Z]').hasMatch(generated), isTrue);
      expect(RegExp(r'\d').hasMatch(generated), isTrue);
      expect(RegExp(r'[^A-Za-z0-9]').hasMatch(generated), isFalse);
      // Look-alike characters are excluded so it stays typeable.
      expect(generated.contains('0'), isFalse);
      expect(generated.contains('l'), isFalse);
    });

    test('two generated passwords differ', () {
      expect(generatePassword(), isNot(equals(generatePassword())));
    });

    test('search never matches on the secret itself', () {
      final entry = PasswordEntry(
        id: 'p1',
        title: 'Google',
        password: 'hunter2secret',
        category: PasswordCategory.email,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        username: 'someone',
      );
      expect(entry.matches('google'), isTrue);
      expect(entry.matches('someone'), isTrue);
      expect(entry.matches('hunter2'), isFalse);
    });
  });

  group('derived portfolio maths', () {
    test('an investment derives its own return', () {
      final i = Investment(
        id: 'i1',
        name: 'Index Fund',
        type: InvestmentType.mutualFunds,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        units: 100,
        purchasePrice: 50,
        currentValue: 6000,
      );
      expect(i.invested, 5000);
      expect(i.profit, 1000);
      expect(i.returnPercent, closeTo(0.2, 0.0001));
      expect(i.isUp, isTrue);
    });

    test('an investment with no valuation shows no phantom gain', () {
      final i = Investment(
        id: 'i2',
        name: 'FD',
        type: InvestmentType.fixedDeposit,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        investedAmount: 10000,
      );
      expect(i.value, 10000);
      expect(i.profit, 0);
    });

    test('an account number is only ever shown as its last four', () {
      final i = Investment(
        id: 'i3',
        name: 'Demat',
        type: InvestmentType.stocks,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        accountNumber: '1234567890123',
      );
      expect(i.maskedAccount, '•••• 0123');
    });

    test('property appreciation is null until both prices exist', () {
      final base = Property(
        id: 'pr1',
        name: 'Villa',
        type: PropertyType.villa,
        status: PropertyStatus.owned,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        purchasePrice: 1000000,
      );
      expect(base.appreciation, isNull);
      final valued = base.copyWith(currentValue: 1500000);
      expect(valued.appreciation, closeTo(0.5, 0.0001));
      expect(valued.gain, 500000);
    });

    test('property JSON survives a round trip', () {
      final p = Property(
        id: 'pr2',
        name: 'Plot 42',
        type: PropertyType.plot,
        status: PropertyStatus.underConstruction,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 2, 1),
        city: 'Hyderabad',
        hasLoan: true,
        outstandingLoan: 250000,
        coOwners: const [CoOwner(name: 'A', sharePercent: 50)],
        legalHeirs: const ['B', 'C'],
      );
      final restored = Property.fromJson(p.toJson());
      expect(restored.name, 'Plot 42');
      expect(restored.type, PropertyType.plot);
      expect(restored.status, PropertyStatus.underConstruction);
      expect(restored.city, 'Hyderabad');
      expect(restored.hasLoan, isTrue);
      expect(restored.outstandingLoan, 250000);
      expect(restored.coOwners.single.name, 'A');
      expect(restored.legalHeirs, ['B', 'C']);
    });
  });
}
