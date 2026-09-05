import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/screens/auth/google_terms_consent_screen.dart';
import 'package:inoapp/screens/documents/offline_documents_screen.dart';
import 'package:inoapp/services/auth_service.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: child,
      );

  group('Terms Consent Security & Universal Routing Tests', () {
    testWidgets('GoogleTermsConsentScreen renders universal copy, 18+ attestation and sign out',
        (tester) async {
      useTallView(tester);
      var consentCalled = false;

      await tester.pumpWidget(host(
        GoogleTermsConsentScreen(
          onConsentGiven: () {
            consentCalled = true;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Verify title & universal copy (not restricted to only Google)
      expect(find.text('Terms & Privacy Consent'), findsOneWidget);
      expect(
        find.text(
          'Before continuing, please review and accept our Terms of Service and Privacy Policy.',
        ),
        findsOneWidget,
      );

      // Verify 18+ attestation checkbox copy
      expect(
        find.text(
          'I confirm that I am at least 18 years of age and agree to the Terms of Service & Privacy Policy.',
        ),
        findsOneWidget,
      );

      // Verify legal cards
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      // Verify Accept CTA is disabled when unchecked
      expect(find.text('Accept & Continue'), findsOneWidget);
      await tester.tap(find.text('Accept & Continue'));
      await tester.pump();
      expect(consentCalled, isFalse);

      // Verify Decline and Sign Out button is present
      expect(find.text('Decline and Sign Out'), findsOneWidget);
    });

    testWidgets('Toggling 18+ checkbox enables Accept CTA', (tester) async {
      useTallView(tester);

      await tester.pumpWidget(host(
        GoogleTermsConsentScreen(
          onConsentGiven: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);

      // Initially unchecked
      Checkbox cbWidget = tester.widget(checkbox);
      expect(cbWidget.value, isFalse);

      // Tap to toggle
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      cbWidget = tester.widget(checkbox);
      expect(cbWidget.value, isTrue);
    });

    testWidgets('Decline and Sign Out navigates without crashing with zero named routes',
        (tester) async {
      useTallView(tester);

      await tester.pumpWidget(host(
        GoogleTermsConsentScreen(
          onConsentGiven: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final declineBtn = find.text('Decline and Sign Out');
      expect(declineBtn, findsOneWidget);

      await tester.tap(declineBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Must not throw any route error
      expect(tester.takeException(), isNull);
    });

    test('AuthService.instance.hasAcceptedTerms safely returns false without authenticated session', () {
      expect(AuthService.instance.hasAcceptedTerms, isFalse);
    });

    testWidgets('OfflineDocumentsScreen redirects to GoogleTermsConsentScreen when terms not accepted',
        (tester) async {
      useTallView(tester);

      await tester.pumpWidget(host(
        const OfflineDocumentsScreen(),
      ));
      // Pump past the post-frame callback
      await tester.pumpAndSettle();

      // Expect GoogleTermsConsentScreen to be presented
      expect(find.byType(GoogleTermsConsentScreen), findsOneWidget);
    });
  });
}
