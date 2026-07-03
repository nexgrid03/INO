import '../models/ocr_result_model.dart';

/// The outcome of document-type detection: the winning [type] and a normalised
/// 0.0–1.0 [confidence].
class DetectionResult {
  const DetectionResult(this.type, this.confidence);
  final IdDocumentType type;
  final double confidence;
}

/// Identifies which Indian ID document a block of OCR text belongs to by
/// keyword scoring. Each type has strong (unique) and weak (supporting)
/// keywords; the highest-scoring type wins, and the score is turned into a
/// confidence. Returns [IdDocumentType.unknown] when nothing scores.
class DocumentDetector {
  DocumentDetector._();

  // Strong keywords are near-unique to a document; weak ones merely support.
  static const Map<IdDocumentType, List<String>> _strong = {
    IdDocumentType.aadhaar: [
      'aadhaar', 'aadhar', 'uidai', 'unique identification',
      'आधार', 'भारतीय विशिष्ट पहचान',
    ],
    IdDocumentType.pan: [
      'permanent account number', 'income tax department',
      'आयकर विभाग',
    ],
    IdDocumentType.passport: [
      'passport', 'republic of india passport', 'passport no',
    ],
    IdDocumentType.drivingLicense: [
      'driving licence', 'driving license', 'licence to drive',
      'transport department', 'dl no', 'form 7',
    ],
    IdDocumentType.voterId: [
      'election commission', 'elector', 'epic no', "elector's photo identity",
    ],
  };

  static const Map<IdDocumentType, List<String>> _weak = {
    IdDocumentType.aadhaar: ['government of india', 'भारत सरकार', 'vid', 'dob', 'year of birth'],
    IdDocumentType.pan: ['govt. of india', 'signature', 'father'],
    IdDocumentType.passport: ['type', 'country code', 'date of expiry', 'place of issue'],
    IdDocumentType.drivingLicense: ['valid till', 'date of issue', 'blood group', 'cov'],
    IdDocumentType.voterId: ['voter', 'assembly constituency', 'age as on'],
  };

  static DetectionResult detect(String rawText) {
    final text = rawText.toLowerCase();
    if (text.trim().isEmpty) {
      return const DetectionResult(IdDocumentType.unknown, 0);
    }

    var bestType = IdDocumentType.unknown;
    var bestScore = 0.0;

    for (final type in _strong.keys) {
      var score = 0.0;
      for (final kw in _strong[type]!) {
        if (text.contains(kw)) score += 2.0;
      }
      for (final kw in _weak[type] ?? const <String>[]) {
        if (text.contains(kw)) score += 0.5;
      }
      if (score > bestScore) {
        bestScore = score;
        bestType = type;
      }
    }

    if (bestScore == 0) return const DetectionResult(IdDocumentType.unknown, 0);
    // ~2 strong hits (score 4) → full confidence; one strong hit → ~0.5.
    final confidence = (bestScore / 4.0).clamp(0.0, 1.0);
    return DetectionResult(bestType, confidence);
  }
}
