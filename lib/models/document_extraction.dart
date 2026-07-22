import 'dart:convert';

/// Structured data extracted from a scanned/uploaded document (OCR), persisted
/// alongside the document so it is ALWAYS visible again when the document is
/// reopened — after an app restart, logout/login, or navigation.
///
/// Storage strategy: encoded as a compact JSON envelope in the document's
/// `notes` column. That column already exists, is per-user + RLS-scoped, and is
/// durable in Supabase — so extracted data survives everything with **no schema
/// migration**. The envelope keeps the machine-readable extracted fields
/// separate from any free-text notes the user typed. Moving this to a dedicated
/// `jsonb` column later is a one-line change at the repository boundary.
class DocumentExtraction {
  const DocumentExtraction({
    this.documentType,
    this.data = const {},
    this.userNotes = '',
  });

  /// Semantic document-type key: 'aadhaar', 'pan', 'passport',
  /// 'drivingLicense', 'voterId', 'insurance', 'property' — or null when the
  /// document type is unknown / not an identity document.
  final String? documentType;

  /// Extracted fields keyed by SEMANTIC key ('name', 'number', 'dob', …). The
  /// display label for each is resolved from [documentType] + key at render
  /// time, so the same 'number' value reads as "Aadhaar Number" or "PAN Number".
  final Map<String, String> data;

  /// Free-text notes the user typed (kept separate from the extracted fields).
  final String userNotes;

  bool get hasData => data.isNotEmpty;
  bool get isEmpty => data.isEmpty && userNotes.trim().isEmpty;

  /// One string combining every extracted value + notes — used for search.
  String get searchableText =>
      [...data.values, userNotes].where((s) => s.trim().isNotEmpty).join(' ');

  static const _marker = '_ino';

  /// Encodes to the JSON envelope stored in the document's `notes` column.
  String encode() => jsonEncode({
        _marker: 1,
        if (documentType != null) 'type': documentType,
        'data': data,
        if (userNotes.trim().isNotEmpty) 'notes': userNotes.trim(),
      });

  /// Decodes a stored `notes` value. Handles three cases gracefully so no data
  /// is ever lost:
  ///  • our JSON envelope → structured fields + user notes,
  ///  • legacy "Label: value" lines (produced by an early OCR build) → recovered
  ///    back into structured fields,
  ///  • any other plain text → treated as free-text notes.
  static DocumentExtraction decode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const DocumentExtraction();

    // 1) Our JSON envelope.
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded.containsKey(_marker)) {
          final rawData = decoded['data'];
          final data = <String, String>{};
          if (rawData is Map) {
            rawData.forEach((k, v) {
              if (v != null && '$v'.trim().isNotEmpty) data['$k'] = '$v';
            });
          }
          return DocumentExtraction(
            documentType: decoded['type'] as String?,
            data: data,
            userNotes: (decoded['notes'] as String?)?.trim() ?? '',
          );
        }
      } catch (_) {
        // Not our JSON — fall through to legacy / plain handling.
      }
    }

    // 2) Legacy "Label: value" lines produced by an earlier OCR build.
    const legacyLabels = <String, String>{
      'name': 'name',
      'dob': 'dob',
      'gender': 'gender',
      "father's name": 'fatherName',
      'father name': 'fatherName',
    };
    final data = <String, String>{};
    final leftover = <String>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final colon = trimmed.indexOf(':');
      if (colon > 0) {
        final label = trimmed.substring(0, colon).trim();
        final value = trimmed.substring(colon + 1).trim();
        final key = legacyLabels[label.toLowerCase()];
        if (key != null && value.isNotEmpty) {
          data[key] = value;
          continue;
        }
      }
      leftover.add(trimmed);
    }
    if (data.isEmpty) return DocumentExtraction(userNotes: text);
    return DocumentExtraction(data: data, userNotes: leftover.join('\n'));
  }

  /// Renders the extracted fields as display (label, value) pairs, ordered by a
  /// stable, human-friendly field order.
  List<({String label, String value})> displayFields() {
    const order = [
      'name',
      'number',
      'dob',
      'gender',
      'fatherName',
      'address',
      'nationality',
      'validity',
      'expiryDate',
      'vehicleClass',
      'insurer',
      'ownerName',
      'surveyNumber',
      'registrationNumber',
      'propertyDetails',
    ];
    final keys = <String>[
      ...order.where(data.containsKey),
      ...data.keys.where((k) => !order.contains(k)),
    ];
    return [
      for (final k in keys) (label: labelFor(documentType, k), value: data[k]!),
    ];
  }

  /// A human display label for the document type, e.g. 'Aadhaar Card'.
  String? get typeLabel => switch (documentType) {
        'aadhaar' => 'Aadhaar Card',
        'pan' => 'PAN Card',
        'passport' => 'Passport',
        'drivingLicense' => 'Driving License',
        'voterId' => 'Voter ID',
        'insurance' => 'Insurance',
        'property' => 'Property Document',
        _ => null,
      };

  /// Resolves the display label for a field [key] under a document [type].
  static String labelFor(String? type, String key) {
    if (key == 'number') {
      switch (type) {
        case 'aadhaar':
          return 'Aadhaar Number';
        case 'pan':
          return 'PAN Number';
        case 'passport':
          return 'Passport Number';
        case 'drivingLicense':
          return 'License Number';
        case 'voterId':
          return 'EPIC Number';
        case 'insurance':
          return 'Policy Number';
        case 'property':
          return 'Registration Number';
        default:
          return 'Document Number';
      }
    }
    const labels = <String, String>{
      'name': 'Full Name',
      'dob': 'Date of Birth',
      'gender': 'Gender',
      'fatherName': "Father's Name",
      'address': 'Address',
      'nationality': 'Nationality',
      'validity': 'Valid Till',
      'expiryDate': 'Expiry Date',
      'vehicleClass': 'Vehicle Class',
      'insurer': 'Insurer',
      'ownerName': 'Owner Name',
      'surveyNumber': 'Survey Number',
      'registrationNumber': 'Registration Number',
      'propertyDetails': 'Property Details',
      'epicNumber': 'EPIC Number',
      'policyNumber': 'Policy Number',
    };
    final mapped = labels[key];
    if (mapped != null) return mapped;
    // Already-a-label (legacy) or unknown key → prettify.
    if (key.contains(' ')) return key;
    return _titleCase(key);
  }

  /// Maps an OCR detected-type label ("Aadhaar Card", "PAN Card") to a semantic
  /// key. Returns null for unknown / other documents.
  static String? typeKeyFromLabel(String? label) {
    final l = (label ?? '').toLowerCase();
    if (l.contains('aadhaar') || l.contains('aadhar')) return 'aadhaar';
    if (l.contains('pan')) return 'pan';
    if (l.contains('passport')) return 'passport';
    if (l.contains('driving') || l.contains('licen')) return 'drivingLicense';
    if (l.contains('voter') || l.contains('epic')) return 'voterId';
    if (l.contains('insurance') || l.contains('policy')) return 'insurance';
    if (l.contains('property') || l.contains('deed')) return 'property';
    return null;
  }

  static String _titleCase(String key) {
    // camelCase → "Camel Case", then Title Case each word.
    final spaced =
        key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
