/// A Dart representation of one row in the `public.documents` table.
///
/// Same idea as [UserProfile]: a type-safe object mirroring the database
/// columns, so the app works with `doc.name` instead of untyped
/// `map['name']`. The repository converts Supabase rows into these.
class Document {
  const Document({
    required this.id,
    required this.wallet,
    required this.name,
    this.category,
    this.recordNumber,
    this.status = 'active',
    this.tags = const [],
    this.notes,
    this.isFavorite = false,
    this.expiresAt,
    this.filePath,
    this.doctorName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id; // documents.id (UUID)
  final String wallet; // "Identity Wallet"
  final String name; // "PAN Card"
  final String? category; // "Identity"
  final String? recordNumber; // document number (from OCR)
  final String status; // active / expiringSoon / shared / archived
  final List<String> tags;
  final String? notes;
  final bool isFavorite;
  final DateTime? expiresAt;
  final String? filePath; // location of the image in Storage (null for now)
  final String? doctorName;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Builds a [Document] from a row returned by Supabase (a `Map`).
  /// The keys are the exact column names from the database.
  ///
  /// [wallet] names the wallet the row came from. Rows read from a per-wallet
  /// table have no `wallet` column - the table IS the wallet - so the caller
  /// supplies it; rows from the `documents` union view carry their own.
  factory Document.fromMap(Map<String, dynamic> map, {String? wallet}) {
    return Document(
      id: map['id'] as String,
      wallet: (map['wallet'] as String?) ?? wallet ?? '',
      name: map['name'] as String,
      category: map['category'] as String?,
      recordNumber: map['record_number'] as String?,
      status: (map['status'] as String?) ?? 'active',
      tags: (map['tags'] as List?)?.cast<String>() ?? const [],
      notes: map['notes'] as String?,
      isFavorite: (map['is_favorite'] as bool?) ?? false,
      expiresAt: map['expires_at'] == null
          ? null
          : DateTime.parse(map['expires_at'] as String),
      filePath: _nullablePath(map['file_path']),
      doctorName: map['doctor_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'wallet': wallet,
        'name': name,
        'category': category,
        'record_number': recordNumber,
        'status': status,
        'tags': tags,
        'notes': notes,
        'is_favorite': isFavorite,
        'expires_at': expiresAt?.toIso8601String(),
        'file_path': filePath,
        'doctor_name': doctorName,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// True when this row points at a real Storage object.
  bool get hasUploadedFile {
    final p = filePath;
    return p != null && p.trim().isNotEmpty;
  }

  /// Normalises DB / JSON path values (trim, empty → null).
  static String? _nullablePath(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
