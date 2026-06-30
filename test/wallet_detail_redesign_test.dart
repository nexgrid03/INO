import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

/// Guards the "premium document manager" redesign: the document-first structure
/// is present and the old dashboard sections are gone.
const _identity = WalletCategory(
  name: 'Identity Wallet',
  icon: Icons.badge_rounded,
  contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
  metric: '5',
  metricLabel: 'documents',
  gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
);

void main() {
  testWidgets('Wallet Detail renders the document-manager structure',
      (tester) async {
    // Wide (800 logical) so the fixed-height bottom nav lays out cleanly, tall
    // enough to build every sliver (incl. the off-screen document list).
    tester.view.physicalSize = const Size(2400, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const WalletDetailScreen(category: _identity),
      ),
    );
    // Repo's 280ms delayed load + entrance animations (no pumpAndSettle: the
    // loading skeleton repeats forever, but it's replaced once data arrives).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(tester.takeException(), isNull);

    // Header + the four supporting elements above the list.
    expect(find.text('Identity Wallet'), findsOneWidget);
    expect(find.text('Search documents...'), findsOneWidget); // sticky search
    expect(find.text('View Vault'), findsOneWidget); // summary card
    expect(find.text('Protected'), findsOneWidget); // ✓ vault protected
    // 'Documents' is both the summary stat label and the list label.
    expect(find.text('Documents'), findsWidgets);

    // Smart banner: the Passport is expiring → a single actionable banner.
    expect(find.text('Renew'), findsOneWidget);

    // Status filter chips (focused subset; 'All' also appears as a category).
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('All'), findsWidgets);

    // The document list itself.
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Aadhaar Card'), findsOneWidget);

    // Removed dashboard sections must NOT be present.
    expect(find.text('Recently Accessed'), findsNothing);
    expect(find.textContaining('Storage'), findsNothing);
    expect(find.text('Security Center'), findsNothing);
  });
}
