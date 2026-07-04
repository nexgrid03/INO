import '../utils/date_normalizer.dart';
import 'scan_models.dart';

/// The identity document types INO's OCR can recognise. Each carries the wallet
/// and category it should be filed under, so detection drives auto-filing.
enum IdDocumentType {
  aadhaar('Aadhaar Card', 'Identity Wallet', 'Identity'),
  pan('PAN Card', 'Identity Wallet', 'Identity'),
  passport('Passport', 'Identity Wallet', 'Identity'),
  drivingLicense('Driving License', 'Identity Wallet', 'Identity'),
  voterId('Voter ID', 'Identity Wallet', 'Identity'),
  unknown('Document', 'Document Wallet', 'Other');

  const IdDocumentType(this.label, this.wallet, this.category);

  final String label;
  final String wallet;
  final String category;

  bool get isKnown => this != IdDocumentType.unknown;
}

/// The structured output of the OCR pipeline: the detected document type, a
/// confidence score, and the extracted identity fields, plus the raw recognised
/// text (kept for debugging / re-parsing). This is the app-facing extraction
/// model; [toOcrResult] maps it into the flow's editable [OcrResult].
class OcrExtraction {
  const OcrExtraction({
    required this.type,
    required this.typeConfidence,
    required this.fields,
    required this.rawText,
  });

  final IdDocumentType type;

  /// 0.0–1.0 — how confidently the document type was detected.
  final double typeConfidence;

  /// Extracted field values keyed by `name`, `dob`, `gender`, `number`,
  /// `fatherName`. Missing fields are absent or null.
  final Map<String, String?> fields;

  final String rawText;

  String? get name => _clean(fields['name']);

  /// Normalized to DD/MM/YYYY regardless of the format OCR produced.
  String? get dob => DateNormalizer.normalizeDob(_clean(fields['dob']));
  String? get gender => _clean(fields['gender']);
  String? get number => _clean(fields['number']);
  String? get fatherName => _clean(fields['fatherName']);

  DetectionConfidence get confidence {
    if (typeConfidence >= 0.66) return DetectionConfidence.high;
    if (typeConfidence >= 0.33) return DetectionConfidence.medium;
    return DetectionConfidence.low;
  }

  /// The identity fields expected for this type that came back empty — surfaced
  /// on the review screen so the user knows what to fill in.
  List<String> get missingFields {
    final expected = switch (type) {
      IdDocumentType.aadhaar => const ['name', 'dob', 'gender', 'number'],
      IdDocumentType.pan => const ['name', 'dob', 'number'],
      _ => const <String>[],
    };
    return [for (final f in expected) if (_clean(fields[f]) == null) f];
  }

  /// Maps the extraction into the editable [OcrResult] the review screen and
  /// Add Document form consume. Identity fields are also folded into `notes` so
  /// they persist to Supabase without a schema change.
  OcrResult toOcrResult() {
    final tags = <String>[
      if (type.isKnown) 'identity',
      if (type == IdDocumentType.aadhaar) 'aadhaar',
      if (type == IdDocumentType.pan) 'pan',
    ];

    // Identity fields travel as structured values (shown as separate editable
    // inputs on the review screen); they're folded into `notes` when the user
    // confirms, so they persist to the document without a schema change.
    return OcrResult(
      documentName: type.isKnown ? type.label : '',
      documentNumber: number,
      detectedType: type.label,
      suggestedWallet: type.wallet,
      category: type.category,
      confidence: confidence,
      tags: tags,
      notes: '',
      fullName: name,
      dob: dob,
      gender: gender,
      fatherName: fatherName,
    );
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
