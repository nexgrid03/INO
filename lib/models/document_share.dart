import '../config/share_config.dart';
import '../l10n/app_localizations.dart';

/// Lifecycle of a share, mirroring the `document_shares.status` column.
enum ShareStatus { active, expired, revoked }

/// The expiry options offered on the Share Configuration screen.
enum ShareDuration { tenMinutes, oneHour, twentyFourHours, sevenDays }

extension ShareDurationX on ShareDuration {
  /// Translation key for the label shown in the picker.
  String get labelKey {
    switch (this) {
      case ShareDuration.tenMinutes:
        return 'dur10Minutes';
      case ShareDuration.oneHour:
        return 'dur1Hour';
      case ShareDuration.twentyFourHours:
        return 'dur24Hours';
      case ShareDuration.sevenDays:
        return 'dur7Days';
    }
  }

  /// Human label shown in the picker, in the active language.
  String label(AppLocalizations l10n) => l10n.t(labelKey);

  /// Time-to-live in seconds - sent to the `create_document_share` RPC.
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
    this.hasPassword = false,
    this.isViewOnly = false,
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
  final bool hasPassword;
  final bool isViewOnly;

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
      hasPassword: hasPassword,
      isViewOnly: isViewOnly,
    );
  }

  /// Convenience for the QR screen: mark this share revoked locally after the
  /// server update succeeds.
  DocumentShare copyAsRevoked() => copyWith(status: ShareStatus.revoked);

  factory DocumentShare.fromMap(Map<dynamic, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    final rawDocs = map['document_ids'];
    List<String> parsedDocIds = const [];
    if (rawDocs is List) {
      parsedDocIds = rawDocs.map((e) => e.toString()).toList();
    } else if (rawDocs is String) {
      final clean = rawDocs.replaceAll('{', '').replaceAll('}', '').trim();
      if (clean.isNotEmpty) {
        parsedDocIds = clean
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }

    final id = map['id']?.toString() ?? '';
    final shareId = map['share_id']?.toString() ??
        (id.isNotEmpty ? id : 'share_${DateTime.now().millisecondsSinceEpoch}');
    final token = map['token']?.toString() ?? shareId;

    DateTime parsedCreated;
    try {
      parsedCreated = DateTime.parse(map['created_at']?.toString() ?? '');
    } catch (_) {
      parsedCreated = DateTime.now();
    }

    DateTime parsedExpires;
    try {
      parsedExpires = DateTime.parse(map['expires_at']?.toString() ?? '');
    } catch (_) {
      parsedExpires = DateTime.now().add(const Duration(hours: 24));
    }

    DateTime? parsedLastAccessed;
    if (map['last_accessed_at'] != null) {
      try {
        parsedLastAccessed =
            DateTime.parse(map['last_accessed_at']?.toString() ?? '');
      } catch (_) {}
    }

    return DocumentShare(
      id: id,
      shareId: shareId,
      token: token,
      ownerId: map['owner_id']?.toString() ?? '',
      documentIds: parsedDocIds,
      status: _statusFrom(map['status']?.toString()),
      viewsCount: (map['views_count'] as num?)?.toInt() ?? 0,
      downloadsCount: (map['downloads_count'] as num?)?.toInt() ?? 0,
      createdAt: parsedCreated,
      expiresAt: parsedExpires,
      lastAccessedAt: parsedLastAccessed,
      hasPassword:
          (map['has_password'] as bool?) ?? (map['password_hash'] != null),
      isViewOnly: (map['is_view_only'] as bool?) ??
          (map['view_only'] as bool?) ??
          false,
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
