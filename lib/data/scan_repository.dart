import '../models/scan_models.dart';

/// Thrown when OCR cannot extract usable information from a capture. The
/// processing screen catches this and shows the failure / manual-entry state.
class OcrException implements Exception {
  const OcrException([this.message = 'Unable to extract information']);
  final String message;

  @override
  String toString() => 'OcrException: $message';
}

/// Source of OCR extraction. The Scan flow depends only on this abstraction, so
/// the sample implementation can be swapped for a real OCR service (ML Kit,
/// Textract, a backend endpoint) without touching any UI.
abstract class ScanRepository {
  Future<OcrResult> extract();

  static ScanRepository instance = SampleScanRepository();
}

class SampleScanRepository implements ScanRepository {
  /// Flip to `true` to make the next [extract] throw — exercises the failure /
  /// manual-entry UI without needing a real bad capture.
  bool failNext = false;

  @override
  Future<OcrResult> extract() async {
    // Simulates on-device OCR latency.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (failNext) {
      failNext = false;
      throw const OcrException('No readable text found in the capture');
    }
    return OcrResult(
      documentName: 'PAN Card',
      documentNumber: 'ABCDE1234F',
      issueDate: DateTime(2016, 7, 18),
      expiryDate: null, // PAN cards don't expire
      detectedType: 'PAN Card',
      suggestedWallet: 'Identity Wallet',
      category: 'Identity',
      confidence: DetectionConfidence.high,
      tags: const ['govt', 'tax'],
      notes: '',
    );
  }
}
