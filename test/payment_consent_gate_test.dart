import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/models/payment_qr.dart';
import 'package:inoapp/services/app_settings.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/scan/payment_app_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profile -> Privacy -> "Payment apps" is the switch that decides whether INO
/// may hand a scanned payee's VPA to Google Pay / PhonePe / Paytm. With it off,
/// the app picker must not appear at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.paymentAppConsent.value = false;
  });

  Widget host(void Function(BuildContext) onTap) => MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => onTap(context),
              child: const Text('scan'),
            ),
          ),
        ),
      );

  testWidgets('a scanned payment QR asks for permission before the app picker',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(host((context) => showPaymentAppSheet(
          context,
          PaymentRequest(
            payeeAddress: 'someone@bank',
            uri: 'upi://pay?pa=someone@bank',
          ),
        )));

    await tester.tap(find.text('scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The consent dialog, not the picker. Showing the apps first and only
    // refusing on the tap read as the picker being broken.
    expect(find.text('Open your payment app?'), findsOneWidget);
    expect(AppSettings.instance.paymentAppConsent.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
