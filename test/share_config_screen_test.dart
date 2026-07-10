import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/wallet_detail_models.dart';
import 'package:inoapp/screens/share/share_config_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

DocumentRecord _doc(String id, String name) => DocumentRecord(
      id: id,
      name: name,
      category: 'Identity',
      icon: Icons.badge_rounded,
      uploadedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: DocumentStatus.active,
      filePath: 'user/$id.jpg',
    );

void main() {
  testWidgets('Share Configuration shows selected docs, durations and actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShareConfigScreen(
          documents: [_doc('1', 'Aadhaar Card'), _doc('2', 'PAN Card')],
        ),
      ),
    );

    // Header + selection summary.
    expect(find.text('Share via QR'), findsOneWidget);
    expect(find.text('2 documents selected'), findsOneWidget);

    // Both selected documents are listed.
    expect(find.text('Aadhaar Card'), findsOneWidget);
    expect(find.text('PAN Card'), findsOneWidget);

    // All four expiry options are offered.
    expect(find.text('10 Minutes'), findsOneWidget);
    expect(find.text('1 Hour'), findsOneWidget);
    expect(find.text('24 Hours'), findsOneWidget);
    expect(find.text('7 Days'), findsOneWidget);

    // Primary + secondary actions.
    expect(find.text('Generate QR'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('a different expiry can be selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShareConfigScreen(documents: [_doc('1', 'Aadhaar Card')]),
      ),
    );

    // Tapping "10 Minutes" should not throw and keeps the screen stable.
    await tester.tap(find.text('10 Minutes'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('10 Minutes'), findsOneWidget);
    expect(find.text('1 document selected'), findsOneWidget);
  });
}
