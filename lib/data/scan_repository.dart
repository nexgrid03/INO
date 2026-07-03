import '../models/scan_models.dart';
import '../services/ocr_service.dart';

/// Thrown when OCR cannot extract usable information from a capture. The
/// processing screen catches this and shows the failure / manual-entry state.
class OcrException implements Exception {
  const OcrException([this.message = 'Unable to extract information']);
  final String message;

  @override
  String toString() => 'OcrException: $message';
}

/// Source of OCR extraction. The Scan flow depends only on this abstraction, so
/// the implementation can be swapped (real ML Kit ↔ sample) without touching any
/// UI. Production defaults to [MlKitScanRepository] (real on-device OCR); tests
/// swap in [SampleScanRepository].
abstract class ScanRepository {
  /// Runs OCR on the captured/imported image at [imagePath] (when available)
  /// and returns the structured result.
  Future<OcrResult> extract({String? imagePath});

  static ScanRepository instance = MlKitScanRepository();
}

/// The production implementation: real on-device OCR via [OcrService].
class MlKitScanRepository implements ScanRepository {
  @override
  Future<OcrResult> extract({String? imagePath}) async {
    if (imagePath == null || imagePath.isEmpty) {
      throw const OcrException('No image to analyse.');
    }
    final extraction = await OcrService.instance.extract(imagePath);
    return extraction.toOcrResult();
  }
}

class SampleScanRepository implements ScanRepository {
  /// Flip to `true` to make the next [extract] throw — exercises the failure /
  /// manual-entry UI without needing a real bad capture.
  bool failNext = false;

  @override
  Future<OcrResult> extract({String? imagePath}) async {
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
