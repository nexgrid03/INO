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
