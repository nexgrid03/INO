import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/scan_models.dart';
import 'package:inoapp/screens/documents/add_document_screen.dart';

void main() {
  testWidgets('Add Document: empty state shows the three real sources',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: AddDocumentScreen()),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // Header + three upload options + empty state, no form yet.
    expect(find.text('Add Document'), findsOneWidget);
    expect(find.text('Scan Document'), findsOneWidget);
    expect(find.text('Upload PDF'), findsOneWidget);
    expect(find.text('Upload Image'), findsOneWidget);
    expect(find.textContaining('Choose a document source'), findsOneWidget);
    expect(find.text('Save Document'), findsNothing);
  });

  testWidgets('Add Document: an OCR prefill lands straight on the filled form',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const prefill = OcrResult(
      documentName: 'My Document',
      detectedType: 'PAN Card',
      suggestedWallet: 'Identity Wallet',
      category: 'Identity',
      confidence: DetectionConfidence.high,
    );

    await tester.pumpWidget(
      const MaterialApp(home: AddDocumentScreen(prefill: prefill)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // Prefill skips the empty state and shows the details form + Save bar.
    expect(find.text('Document Name'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Save Document'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('Choose a document source'), findsNothing);
  });
}
