import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/screens/documents/add_document_screen.dart';

void main() {
  testWidgets('Add Document: empty state → pick source reveals the form',
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

    // Pick a source → form + save bar appear, empty state gone.
    await tester.tap(find.text('Scan Document'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Document Name'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Save Document'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('Choose a document source'), findsNothing);
  });
}
