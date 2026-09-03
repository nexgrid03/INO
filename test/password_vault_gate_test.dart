import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/screens/passwords/password_form_screen.dart';
import 'package:inoapp/screens/passwords/vault_passphrase_sheet.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Password Vault's write gate, and the layout of the form behind it.
///
/// A test process can never hold a vault key (there is no Supabase session, so
/// nothing can be derived), which makes it exactly the locked state these
/// guards exist for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VaultCrypto.instance.lock();
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        home: child,
      );

  testWidgets('a password cannot be saved while the vault has no key',
      (tester) async {
    // A narrow phone, which is also what reproduces the label overflow below.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    expect(VaultCrypto.instance.isUnlocked, isFalse);
    final before = PasswordStore.instance.count;

    await tester.pumpWidget(wrap(const PasswordFormScreen()));
    // The backdrop's ambient drift repeats forever, so pumpAndSettle would
    // never return here — pump fixed durations instead.
    await tester.pump(const Duration(milliseconds: 700));

    await tester.enterText(find.byType(TextFormField).first, 'blue parrot');
    await tester.enterText(find.byType(TextFormField).last, 'hunter2hunter2');
    await tester.pump();

    await tester.tap(find.text('Save password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Refused before the consent sheet, and nothing was written. Saving here
    // would have put the credential into shared_preferences in the clear,
    // with no key to ever seal it for sync.
    expect(find.text('Set a vault passphrase before saving a password.'),
        findsOneWidget);
    expect(PasswordStore.instance.count, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Add Password form lays out without overflow on a narrow phone',
      (tester) async {
    // 360dp wide - the width that overflowed the nickname label by 3px, since
    // its long copy sat in a Row that could not wrap.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(const PasswordFormScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    // A RenderFlex overflow throws in debug, so this is the assertion.
    expect(tester.takeException(), isNull);
    expect(
      find.text('Type a name by which you can remember this password'),
      findsOneWidget,
    );
  });

  /// Opens the passphrase sheet in [isFirstTime] mode and settles it.
  Future<void> openSheet(WidgetTester tester, {required bool first}) async {
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () => showVaultPassphraseSheet(context, isFirstTime: first),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('unlocking an existing vault offers a way back in', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await openSheet(tester, first: false);

    // Without this the only options were the right passphrase or nothing -
    // a forgotten one meant a vault that could never be opened again.
    expect(find.text('Forgot passphrase?'), findsOneWidget);
    expect(find.text('Unlock Vault'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-time setup has nothing to recover, so offers no reset',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await openSheet(tester, first: true);

    expect(find.text('Forgot passphrase?'), findsNothing);
    expect(find.text('Create Vault'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
