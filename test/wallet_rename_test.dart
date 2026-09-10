import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/repositories/wallet_tables.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/services/wallet_store.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/wallet_detail/wallet_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPrefsCache.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsCache.init();
    await CustomWalletStore.instance.clear();
  });

  tearDown(() async {
    await CustomWalletStore.instance.clear();
  });

  group('CustomWalletStore.rename', () {
    test('renames a wallet in-place preserving icon, color, slug and ordering', () async {
      final w1 = await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'First Wallet',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
          slug: 'w_first_wallet',
        ),
      );
      final w2 = await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Second Wallet',
          iconKey: 'heart',
          colorValue: 0xFFF5704A,
          slug: 'w_second_wallet',
        ),
      );

      expect(w2.name, 'Second Wallet');

      expect(CustomWalletStore.instance.all.length, 2);
      expect(CustomWalletStore.instance.all[0].name, 'First Wallet');
      expect(CustomWalletStore.instance.all[1].name, 'Second Wallet');

      // Rename First Wallet to "Renamed First"
      final updated = await CustomWalletStore.instance.rename(
        'First Wallet',
        '  Renamed First  ',
      );

      expect(updated.name, 'Renamed First');
      expect(updated.iconKey, w1.iconKey);
      expect(updated.colorValue, w1.colorValue);
      expect(updated.slug, w1.slug);

      // Verify ordering is preserved
      final all = CustomWalletStore.instance.all;
      expect(all.length, 2);
      expect(all[0].name, 'Renamed First');
      expect(all[1].name, 'Second Wallet');

      // Verify WalletTables.slugFor preserves table association
      expect(WalletTables.slugFor('Renamed First'), 'w_first_wallet');
    });

    test('validates empty name and whitespace', () async {
      await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'My Docs',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
        ),
      );

      expect(
        () => CustomWalletStore.instance.rename('My Docs', ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CustomWalletStore.instance.rename('My Docs', '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects non-existent wallet', () async {
      expect(
        () => CustomWalletStore.instance.rename('Non Existent', 'New Name'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects collision with another custom wallet', () async {
      await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Alpha',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
        ),
      );
      await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Beta',
          iconKey: 'star',
          colorValue: 0xFFF5704A,
        ),
      );

      expect(
        () => CustomWalletStore.instance.rename('Alpha', 'Beta'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => CustomWalletStore.instance.rename('Alpha', 'beta'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects collision with built-in wallet names', () async {
      await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Personal',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
        ),
      );

      expect(
        () => CustomWalletStore.instance.rename('Personal', 'Identity Wallet'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => CustomWalletStore.instance.rename('Personal', 'document wallet'),
        throwsA(isA<StateError>()),
      );
    });

    test('no-op when renamed to the exact same name', () async {
      final original = await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Keep Me',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
        ),
      );
      expect(original.name, 'Keep Me');

      final same = await CustomWalletStore.instance.rename('Keep Me', 'Keep Me');
      expect(same.name, 'Keep Me');
      expect(CustomWalletStore.instance.all.length, 1);
    });

    test('renamed wallet persists to SharedPreferences and reloads correctly', () async {
      await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Old Label',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
          slug: 'w_old_label',
        ),
      );

      await CustomWalletStore.instance.rename('Old Label', 'Fresh Label');

      // Clear in-memory state and reload from disk
      await CustomWalletStore.instance.load();

      expect(CustomWalletStore.instance.byName('Old Label'), isNull);
      final reloaded = CustomWalletStore.instance.byName('Fresh Label');
      expect(reloaded, isNotNull);
      expect(reloaded!.name, 'Fresh Label');
      expect(reloaded.slug, 'w_old_label');
      expect(WalletTables.slugFor('Fresh Label'), 'w_old_label');
    });
  });

  group('WalletHeader edit option', () {
    testWidgets('shows edit icon when onEditName is provided', (tester) async {
      var editTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WalletHeader(
              title: 'My Custom Wallet',
              onBack: () {},
              onEditName: () => editTapped = true,
            ),
          ),
        ),
      );

      final editIcon = find.byIcon(Icons.edit_outlined);
      expect(editIcon, findsOneWidget);

      await tester.tap(editIcon);
      await tester.pumpAndSettle();
      expect(editTapped, isTrue);
    });

    testWidgets('does not show edit icon when onEditName is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WalletHeader(
              title: 'Identity Wallet',
              onBack: () {},
              onEditName: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('WalletDetailScreen wallet name edit flow', () {
    testWidgets('allows editing custom wallet name and updates title', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final custom = await CustomWalletStore.instance.add(
        const CustomWallet(
          name: 'Trip Docs',
          iconKey: 'folder',
          colorValue: 0xFF14B8A6,
          slug: 'w_trip_docs',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: WalletDetailScreen(category: custom.toCategory()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1200));

      expect(find.text('Trip Docs'), findsWidgets);

      // Tap the edit icon
      final editButton = find.byIcon(Icons.edit_outlined);
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify rename dialog opened with text field
      expect(find.byType(TextField), findsOneWidget);

      // Enter new name
      await tester.enterText(find.byType(TextField), 'Europe Vacation');
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Verify wallet was renamed in store
      expect(CustomWalletStore.instance.byName('Trip Docs'), isNull);
      final renamed = CustomWalletStore.instance.byName('Europe Vacation');
      expect(renamed, isNotNull);
      expect(renamed!.slug, 'w_trip_docs');

      // Verify screen header displays the new name
      expect(find.text('Europe Vacation'), findsWidgets);
    });
  });
}
