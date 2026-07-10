import '../config/share_config.dart';

/// Lifecycle of a share, mirroring the `document_shares.status` column.
enum ShareStatus { active, expired, revoked }

/// The expiry options offered on the Share Configuration screen.
enum ShareDuration { tenMinutes, oneHour, twentyFourHours, sevenDays }

extension ShareDurationX on ShareDuration {
  /// Human label shown in the picker.
  String get label {
    switch (this) {
      case ShareDuration.tenMinutes:
        return '10 Minutes';
      case ShareDuration.oneHour:
        return '1 Hour';
      case ShareDuration.twentyFourHours:
        return '24 Hours';
      case ShareDuration.sevenDays:
        return '7 Days';
    }
  }

  /// Time-to-live in seconds — sent to the `create_document_share` RPC.
  int get seconds {
    switch (this) {
      case ShareDuration.tenMinutes:
        return 10 * 60;
      case ShareDuration.oneHour:
        return 60 * 60;
      case ShareDuration.twentyFourHours:
        return 24 * 60 * 60;
      case ShareDuration.sevenDays:
        return 7 * 24 * 60 * 60;
    }
  }
}

/// A generated QR/link share granting read-only access to a fixed set of
/// documents until it expires or is revoked. Mirrors one `document_shares` row.
class DocumentShare {
  const DocumentShare({
    required this.id,
    required this.shareId,
    required this.token,
    required this.ownerId,
    required this.documentIds,
    required this.status,
    required this.viewsCount,
    required this.downloadsCount,
    required this.createdAt,
    required this.expiresAt,
    this.lastAccessedAt,
  });

  final String id;
  final String shareId; // internal id (RLS / analytics)
  final String token; // short public token used in the shareable link
  final String ownerId;
  final List<String> documentIds;
  final ShareStatus status;
  final int viewsCount;
  final int downloadsCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastAccessedAt;

  /// The public, Google-Drive-style URL encoded in the QR code.
  String get url => ShareConfig.publicUrl(token);

  int get documentCount => documentIds.length;

  /// True only when the share is still usable right now (active + not expired).
  bool get isLive =>
      status == ShareStatus.active && expiresAt.isAfter(DateTime.now());

  /// Effective status, honouring the wall clock even if the DB row still says
  /// 'active' (the Edge Function flips it lazily on first access after expiry).
  ShareStatus get effectiveStatus {
    if (status == ShareStatus.active && expiresAt.isBefore(DateTime.now())) {
      return ShareStatus.expired;
    }
    return status;
  }

  /// Returns a copy with an overridden [status] (e.g. after a local revoke),
  /// keeping every other field intact.
  DocumentShare copyWith({ShareStatus? status}) {
    return DocumentShare(
      id: id,
      shareId: shareId,
      token: token,
      ownerId: ownerId,
      documentIds: documentIds,
      status: status ?? this.status,
      viewsCount: viewsCount,
      downloadsCount: downloadsCount,
      createdAt: createdAt,
      expiresAt: expiresAt,
      lastAccessedAt: lastAccessedAt,
    );
  }

  /// Convenience for the QR screen: mark this share revoked locally after the
  /// server update succeeds.
  DocumentShare copyAsRevoked() => copyWith(status: ShareStatus.revoked);

  factory DocumentShare.fromMap(Map<String, dynamic> map) {
    return DocumentShare(
      id: map['id'] as String,
      shareId: map['share_id'] as String,
      token: (map['token'] as String?) ?? map['share_id'] as String,
      ownerId: map['owner_id'] as String,
      documentIds:
          (map['document_ids'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      status: _statusFrom(map['status'] as String?),
      viewsCount: (map['views_count'] as num?)?.toInt() ?? 0,
      downloadsCount: (map['downloads_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: DateTime.parse(map['expires_at'] as String),
      lastAccessedAt: map['last_accessed_at'] == null
          ? null
          : DateTime.parse(map['last_accessed_at'] as String),
    );
  }

  static ShareStatus _statusFrom(String? raw) {
    switch (raw) {
      case 'revoked':
        return ShareStatus.revoked;
      case 'expired':
        return ShareStatus.expired;
      default:
        return ShareStatus.active;
    }
  }
}
