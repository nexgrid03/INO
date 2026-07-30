import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A member's role in a Family Vault, in ascending order of privilege so
/// `index` comparisons express "at least this powerful". The permission getters
/// are the single source of truth the UI and (defense-in-depth) checks read —
/// the authoritative gate is RLS on the server.
enum VaultRole { viewer, editor, admin, owner }

extension VaultRoleX on VaultRole {
  String get label {
    switch (this) {
      case VaultRole.owner:
        return 'Owner';
      case VaultRole.admin:
        return 'Admin';
      case VaultRole.editor:
        return 'Editor';
      case VaultRole.viewer:
        return 'Viewer';
    }
  }

  /// A one-line description of what the role can do (shown in the role picker).
  String get description {
    switch (this) {
      case VaultRole.owner:
        return 'Full control, including deleting the vault';
      case VaultRole.admin:
        return 'Manage members and documents';
      case VaultRole.editor:
        return 'Add and edit documents';
      case VaultRole.viewer:
        return 'View documents only';
    }
  }

  Color get color {
    switch (this) {
      case VaultRole.owner:
        return AppColors.primaryGreen;
      case VaultRole.admin:
        return const Color(0xFF8B6CEF);
      case VaultRole.editor:
        return const Color(0xFF2563EB);
      case VaultRole.viewer:
        return const Color(0xFF64748B);
    }
  }

  IconData get icon {
    switch (this) {
      case VaultRole.owner:
        return Icons.workspace_premium_rounded;
      case VaultRole.admin:
        return Icons.admin_panel_settings_rounded;
      case VaultRole.editor:
        return Icons.edit_rounded;
      case VaultRole.viewer:
        return Icons.visibility_rounded;
    }
  }

  // ---- Permissions (mirror the server's RLS intent) ------------------------

  /// Every role can view the vault's documents.
  bool get canView => true;

  /// Editors and up can add / edit documents.
  bool get canEditDocuments => index >= VaultRole.editor.index;

  /// Admins and the owner can invite / remove members and change roles.
  bool get canManageMembers => index >= VaultRole.admin.index;

  /// Only the owner can rename or delete the vault, or assign the owner role.
  bool get canManageVault => this == VaultRole.owner;

  /// The three roles an owner/admin may ASSIGN to others (never `owner`).
  static const assignable = [VaultRole.viewer, VaultRole.editor, VaultRole.admin];

  static VaultRole fromName(String? name) {
    switch (name) {
      case 'owner':
        return VaultRole.owner;
      case 'admin':
        return VaultRole.admin;
      case 'editor':
        return VaultRole.editor;
      default:
        return VaultRole.viewer;
    }
  }
}

/// A Family Vault (the `public.family_vaults` row).
class FamilyVault {
  const FamilyVault({
    required this.id,
    required this.name,
    required this.ownerAuthUserId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String ownerAuthUserId;
  final DateTime createdAt;

  factory FamilyVault.fromRow(Map<String, dynamic> row) => FamilyVault(
        id: row['id'].toString(),
        name: (row['name'] as String?)?.trim().isNotEmpty == true
            ? (row['name'] as String).trim()
            : 'Family Vault',
        ownerAuthUserId: (row['owner_auth_user_id'] as String?) ?? '',
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}

/// One membership row (`public.vault_members`), with the display info
/// denormalized onto the row (co-members can't read each other's profiles).
class VaultMember {
  const VaultMember({
    required this.id,
    required this.vaultId,
    required this.authUserId,
    required this.role,
    this.displayName,
    this.email,
    this.phone,
    required this.joinedAt,
  });

  final String id;
  final String vaultId;
  final String authUserId;
  final VaultRole role;
  final String? displayName;
  final String? email;
  final String? phone;
  final DateTime joinedAt;

  /// A never-empty label for the member (name → email → phone → "Member").
  String get label {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e;
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) return p;
    return 'Member';
  }

  /// A one/two-letter avatar initial from [label].
  String get initial {
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  /// True if [query] matches this member's name, email or phone (used by the
  /// members search field). An empty query matches everything.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (displayName ?? '').toLowerCase().contains(q) ||
        (email ?? '').toLowerCase().contains(q) ||
        (phone ?? '').toLowerCase().contains(q) ||
        role.label.toLowerCase().contains(q);
  }

  factory VaultMember.fromRow(Map<String, dynamic> row) => VaultMember(
        id: row['id'].toString(),
        vaultId: row['vault_id'].toString(),
        authUserId: (row['auth_user_id'] as String?) ?? '',
        role: VaultRoleX.fromName(row['role'] as String?),
        displayName: row['display_name'] as String?,
        email: row['email'] as String?,
        phone: row['phone'] as String?,
        joinedAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}

/// A vault paired with the signed-in user's role in it — what the vault LIST
/// needs (each list row shows the vault plus the current user's own role).
class VaultSummary {
  const VaultSummary({required this.vault, required this.myRole});

  final FamilyVault vault;
  final VaultRole myRole;
}

/// The lifecycle state of an invitation (`public.vault_invitations.status`).
enum InvitationStatus { pending, accepted, declined, revoked, expired }

extension InvitationStatusX on InvitationStatus {
  String get label {
    switch (this) {
      case InvitationStatus.pending:
        return 'Pending';
      case InvitationStatus.accepted:
        return 'Accepted';
      case InvitationStatus.declined:
        return 'Declined';
      case InvitationStatus.revoked:
        return 'Cancelled';
      case InvitationStatus.expired:
        return 'Expired';
    }
  }

  Color get color {
    switch (this) {
      case InvitationStatus.pending:
        return const Color(0xFFE0A100);
      case InvitationStatus.accepted:
        return AppColors.primaryGreen;
      case InvitationStatus.declined:
      case InvitationStatus.revoked:
        return const Color(0xFF64748B);
      case InvitationStatus.expired:
        return AppColors.critical;
    }
  }

  static InvitationStatus fromName(String? name) {
    switch (name) {
      case 'accepted':
        return InvitationStatus.accepted;
      case 'declined':
        return InvitationStatus.declined;
      case 'revoked':
        return InvitationStatus.revoked;
      case 'expired':
        return InvitationStatus.expired;
      default:
        return InvitationStatus.pending;
    }
  }
}

/// One invitation row (`public.vault_invitations`). Carries the DENORMALIZED
/// vault name + inviter name so an invitee (not yet a member) can render the
/// invitation card without reading family_vaults / users (both owner-scoped).
class VaultInvitation {
  const VaultInvitation({
    required this.id,
    required this.vaultId,
    required this.role,
    required this.status,
    this.email,
    this.phone,
    this.vaultName,
    this.invitedByName,
    this.createdAt,
    this.expiresAt,
    this.updatedAt,
    this.acceptedAt,
  });

  final String id;
  final String vaultId;
  final VaultRole role;
  final InvitationStatus status;
  final String? email;
  final String? phone;
  final String? vaultName;
  final String? invitedByName;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;

  /// The invited contact (email preferred, else phone).
  String get target {
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e;
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) return p;
    return '—';
  }

  bool get isPending => status == InvitationStatus.pending;

  /// True once [expiresAt] is in the past (the server also flips the status on
  /// accept, but this lets the UI show "expired" without a round-trip).
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory VaultInvitation.fromRow(Map<String, dynamic> row) => VaultInvitation(
        id: row['id'].toString(),
        vaultId: row['vault_id'].toString(),
        role: VaultRoleX.fromName(row['role'] as String?),
        status: InvitationStatusX.fromName(row['status'] as String?),
        email: row['email'] as String?,
        phone: row['phone'] as String?,
        vaultName: row['vault_name'] as String?,
        invitedByName: row['invited_by_name'] as String?,
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal(),
        expiresAt:
            DateTime.tryParse(row['expires_at']?.toString() ?? '')?.toLocal(),
        updatedAt:
            DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal(),
        acceptedAt:
            DateTime.tryParse(row['accepted_at']?.toString() ?? '')?.toLocal(),
      );

  /// True if [query] matches the target contact, role or vault name (used by the
  /// invitation search field). An empty query matches everything.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return target.toLowerCase().contains(q) ||
        role.label.toLowerCase().contains(q) ||
        (vaultName ?? '').toLowerCase().contains(q);
  }
}

/// One audit-trail entry (`public.vault_audit_log`). An immutable record of a
/// membership / invitation / ownership action, shown in the vault's Activity
/// section. The server is the sole writer.
class VaultAuditEntry {
  const VaultAuditEntry({
    required this.id,
    required this.vaultId,
    required this.action,
    this.actorName,
    this.targetType,
    this.targetLabel,
    this.metadata = const {},
    required this.createdAt,
  });

  final String id;
  final String vaultId;

  /// The raw action code, e.g. `invite_sent`, `role_changed`.
  final String action;
  final String? actorName;
  final String? targetType;
  final String? targetLabel;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  /// A human sentence for the row, e.g. "Ravi invited asha@x.com as Editor".
  String get summary {
    final who = (actorName?.trim().isNotEmpty == true) ? actorName!.trim() : 'Someone';
    final what = targetLabel ?? '';
    switch (action) {
      case 'invite_sent':
        return '$who invited $what$_roleSuffix';
      case 'invite_accepted':
        return '$what accepted the invitation';
      case 'invite_declined':
        return '$what declined the invitation';
      case 'invite_cancelled':
        return '$who cancelled the invite to $what';
      case 'invite_resent':
        return '$who resent the invite to $what';
      case 'role_changed':
        final from = metadata['from'];
        final to = metadata['to'];
        return '$who changed $what\'s role'
            '${from != null && to != null ? ' from $from to $to' : ''}';
      case 'member_removed':
        return '$who removed $what';
      case 'member_left':
        return '$what left the vault';
      case 'ownership_transferred':
        return '$who transferred ownership to $what';
      case 'vault_renamed':
        final to = metadata['to'];
        return '$who renamed the vault${to != null ? ' to "$to"' : ''}';
      default:
        return '$who · ${action.replaceAll('_', ' ')}'
            '${what.isNotEmpty ? ' · $what' : ''}';
    }
  }

  String get _roleSuffix {
    final r = metadata['role'];
    return r == null ? '' : ' as ${VaultRoleX.fromName(r.toString()).label}';
  }

  IconData get icon {
    switch (action) {
      case 'invite_sent':
      case 'invite_resent':
        return Icons.outgoing_mail;
      case 'invite_accepted':
        return Icons.how_to_reg_rounded;
      case 'invite_declined':
      case 'invite_cancelled':
        return Icons.unsubscribe_rounded;
      case 'role_changed':
        return Icons.tune_rounded;
      case 'member_removed':
      case 'member_left':
        return Icons.person_remove_rounded;
      case 'ownership_transferred':
        return Icons.workspace_premium_rounded;
      case 'vault_renamed':
        return Icons.drive_file_rename_outline_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  factory VaultAuditEntry.fromRow(Map<String, dynamic> row) => VaultAuditEntry(
        id: row['id'].toString(),
        vaultId: row['vault_id'].toString(),
        action: (row['action'] as String?) ?? '',
        actorName: row['actor_name'] as String?,
        targetType: row['target_type'] as String?,
        targetLabel: row['target_label'] as String?,
        metadata: row['metadata'] is Map
            ? Map<String, dynamic>.from(row['metadata'] as Map)
            : const {},
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}

/// A document shared into a Family Vault (`public.vault_documents`).
///
/// The display fields are DENORMALIZED on purpose. The source document lives in
/// an owner-scoped wallet table whose RLS restricts it to its owner, so a
/// co-member genuinely cannot read it - a row that joined to the original would
/// list but never render. Everything needed to show and open the file therefore
/// travels on this row.
class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.vaultId,
    required this.sharedBy,
    required this.objectPath,
    required this.name,
    this.category,
    this.sizeBytes,
    this.contentType,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String vaultId;

  /// Who contributed it. An editor may withdraw only their own contributions;
  /// admins and the owner may remove anything.
  final String sharedBy;

  /// The object name in the `documents` storage bucket. Access to it is gated
  /// by a storage policy that re-checks vault membership on every read, which
  /// is what makes removing a member revoke downloads instantly.
  final String objectPath;

  final String name;
  final String? category;
  final int? sizeBytes;
  final String? contentType;
  final String? note;
  final DateTime createdAt;

  /// The file extension, lower-cased, derived from the stored object name.
  String get extension {
    final dot = objectPath.lastIndexOf('.');
    if (dot < 0 || dot == objectPath.length - 1) return '';
    return objectPath.substring(dot + 1).toLowerCase();
  }

  bool get isImage => const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'}
      .contains(extension);

  bool get isPdf => extension == 'pdf';

  /// "2.4 MB" - what the list row shows. Empty when the size is unknown.
  String get sizeLabel {
    final b = sizeBytes;
    if (b == null || b <= 0) return '';
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).round()} KB';
    return '$b B';
  }

  /// Whether [uid] may withdraw this document, given their [role] in the vault.
  /// Mirrors `remove_vault_document()`; the authoritative check is server-side.
  bool canBeRemovedBy(String? uid, VaultRole role) =>
      (uid != null && sharedBy == uid) || role.canManageMembers;

  factory VaultDocument.fromRow(Map<String, dynamic> row) => VaultDocument(
        id: row['id'].toString(),
        vaultId: row['vault_id'].toString(),
        sharedBy: row['shared_by']?.toString() ?? '',
        objectPath: (row['object_path'] as String?) ?? '',
        name: (row['name'] as String?) ?? 'Document',
        category: row['category'] as String?,
        sizeBytes: (row['size_bytes'] as num?)?.toInt(),
        contentType: row['content_type'] as String?,
        note: row['note'] as String?,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}
