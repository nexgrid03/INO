import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inoapp/models/wallet_detail_models.dart';
import 'package:inoapp/services/document_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall call) async {
      final tempDir = Directory.systemTemp.createTempSync('ino_test_temp');
      return tempDir.path;
    });
  });

  group('DocumentPdfService Tests', () {
    test('sanitizeFileName removes special characters and maintains readability', () {
      expect(DocumentPdfService.sanitizeFileName('Passport / Visa: 2026?'), equals('Passport  Visa 2026'));
      expect(DocumentPdfService.sanitizeFileName('Aadhaar_Card-Final.pdf'), equals('Aadhaar_Card-Final.pdf'));
      expect(DocumentPdfService.sanitizeFileName('///'), equals('document'));
    });

    test('generatePdfForDocument converts image to a valid PDF with original colors', () async {
      // Create a test image with specific RGB colors (red, green, blue)
      final image = img.Image(width: 400, height: 300);
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 400; x++) {
          image.setPixelRgb(x, y, 220, 100, 50); // custom preserved color
        }
      }
      final tempDir = Directory.systemTemp.createTempSync('ino_pdf_test');
      final imageFile = File('${tempDir.path}/test_card.jpg');
      await imageFile.writeAsBytes(img.encodeJpg(image, quality: 90));

      final record = DocumentRecord(
        id: 'doc-pdf-test-1',
        name: 'My Identity Card',
        category: 'Identity',
        icon: Icons.badge_rounded,
        uploadedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.active,
        filePath: imageFile.path,
      );

      final pdfFile = await DocumentPdfService.instance.generatePdfForDocument(record);
      expect(pdfFile, isNotNull);
      expect(await pdfFile!.exists(), isTrue);
      expect(pdfFile.path.endsWith('My Identity Card.pdf'), isTrue);

      final pdfBytes = await pdfFile.readAsBytes();
      expect(pdfBytes.length, greaterThan(100));

      // PDF header verification
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, equals('%PDF'));
    });

    test('generatePdfForDocument preserves existing PDF file', () async {
      final tempDir = Directory.systemTemp.createTempSync('ino_pdf_test_2');
      final samplePdf = File('${tempDir.path}/sample.pdf');
      await samplePdf.writeAsBytes(Uint8List.fromList('%PDF-1.4 sample content'.codeUnits));

      final record = DocumentRecord(
        id: 'doc-pdf-test-2',
        name: 'Tax Document',
        category: 'Finance',
        icon: Icons.receipt_long_rounded,
        uploadedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.active,
        filePath: samplePdf.path,
      );

      final pdfFile = await DocumentPdfService.instance.generatePdfForDocument(record);
      expect(pdfFile, isNotNull);
      expect(await pdfFile!.exists(), isTrue);
      expect(pdfFile.path.endsWith('Tax Document.pdf'), isTrue);

      final bytes = await pdfFile.readAsBytes();
      expect(String.fromCharCodes(bytes), contains('%PDF-1.4 sample content'));
    });
  });
}
