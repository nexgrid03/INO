import 'dart:typed_data';

/// Recipient-facing lifecycle of a share, as reported by the `share` Edge
/// Function's JSON API. Distinct from the owner-side `ShareStatus` because the
/// public API also reports `notFound` and `error`.
enum PublicShareStatus { active, expired, revoked, notFound, error }

PublicShareStatus _statusFrom(String? raw) {
  switch (raw) {
    case 'active':
      return PublicShareStatus.active;
    case 'expired':
      return PublicShareStatus.expired;
    case 'revoked':
      return PublicShareStatus.revoked;
    case 'not_found':
      return PublicShareStatus.notFound;
    default:
      return PublicShareStatus.error;
  }
}

/// One document listed in a public share. Deliberately minimal — the API never
/// returns file paths, owner ids, or any storage internals.
class SharedDoc {
  const SharedDoc({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final String type;

  factory SharedDoc.fromJson(Map<String, dynamic> json) => SharedDoc(
        id: json['id']?.toString() ?? '',
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : 'Document',
        type: (json['type'] as String?)?.trim().isNotEmpty == true
            ? json['type'] as String
            : 'Document',
      );
}

/// The parsed response of `GET /share/:id` — everything the recipient viewer
/// needs, and nothing sensitive.
class PublicShare {
  const PublicShare({
    required this.status,
    this.shareId,
    this.count = 0,
    this.expiresAt,
    this.documents = const [],
    this.message,
  });

  final PublicShareStatus status;
  final String? shareId;
  final int count;
  final DateTime? expiresAt;
  final List<SharedDoc> documents;
  final String? message;

  bool get isActive => status == PublicShareStatus.active;

  factory PublicShare.fromJson(Map<String, dynamic> json) {
    final status = _statusFrom(json['status'] as String?);
    return PublicShare(
      status: status,
      shareId: json['shareId'] as String?,
      count: (json['count'] as num?)?.toInt() ??
          (json['documents'] as List?)?.length ??
          0,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'] as String),
      documents: [
        for (final d in (json['documents'] as List? ?? const []))
          SharedDoc.fromJson(d as Map<String, dynamic>),
      ],
      message: json['message'] as String?,
    );
  }

  /// A safe fallback when the network/response itself failed.
  static const PublicShare errored =
      PublicShare(status: PublicShareStatus.error);
}

/// The bytes of a shared file plus the metadata needed to open/save it. Fetched
/// (proxied) through the Edge Function — never a direct storage URL.
class SharedFile {
  const SharedFile({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}
