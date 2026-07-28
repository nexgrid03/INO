import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_vault_models.dart';

/// Source of Family Vault data — the `public.family_vaults` and
/// `public.vault_members` tables in Supabase.
///
/// The store/screens depend only on this abstraction, so it stays the single
/// place that talks to those tables (same pattern as ReminderRepository), and
/// tests can swap in a fake. RLS scopes every read/write to the caller's
/// membership server-side; the queries here mirror that intent.
abstract class FamilyVaultRepository {
  /// The vaults the signed-in user belongs to, each paired with their role.
  Future<List<VaultSummary>> myVaults();

  /// Creates a vault owned by the signed-in user (a DB trigger adds them as the
  /// 'owner' member) and returns it.
  Future<FamilyVault> createVault(String name);

  /// The members of [vaultId], most-privileged first.
  Future<List<VaultMember>> members(String vaultId);

  /// Renames a vault (owner only, enforced by RLS).
  Future<void> renameVault(String id, String name);

  /// Deletes a vault (owner only, enforced by RLS).
  Future<void> deleteVault(String id);

  /// Changes a member's role (admin/owner only; never to owner). RPC-enforced.
  Future<void> updateMemberRole(String memberId, VaultRole role);

  /// Removes a member (admin), or leaves (self). Owner can't be removed.
  Future<void> removeMember(String memberId);

  /// Transfers ownership of [vaultId] to member [newOwnerAuthUserId] (owner only,
  /// atomic — current owner becomes admin).
  Future<void> transferOwnership(String vaultId, String newOwnerAuthUserId);

  // ---- Invitations ---------------------------------------------------------

  /// Invites someone to [vaultId] by email OR phone with [role] (admin/owner).
  Future<VaultInvitation> invite(
    String vaultId,
    VaultRole role, {
    String? email,
    String? phone,
  });

  /// All invitations for [vaultId] (admin/owner sees every status), newest first.
  Future<List<VaultInvitation>> invitationsForVault(String vaultId);

  /// Pending invitations addressed to the signed-in user (across all vaults).
  Future<List<VaultInvitation>> myPendingInvitations();

  /// Accepts an invitation addressed to the signed-in user (joins the vault).
  Future<void> acceptInvitation(String invitationId);

  /// Declines an invitation addressed to the signed-in user.
  Future<void> declineInvitation(String invitationId);

  /// Cancels (revokes) a pending invitation (admin/owner).
  Future<void> cancelInvitation(String invitationId);

  /// Re-arms a declined/expired/revoked invitation, optionally with a new role.
  Future<void> resendInvitation(String invitationId, {VaultRole? role});

  // ---- Audit + realtime ----------------------------------------------------

  /// The most recent audit-trail entries for [vaultId] (admin/owner only —
  /// RLS-scoped), newest first.
  Future<List<VaultAuditEntry>> auditLog(String vaultId, {int limit = 50});

  /// Subscribes to changes across the caller's vaults / memberships / invitations
  /// and calls [onChange] on every change (drives the live vault list + invite
  /// badge). Returns a channel to close later, or null if realtime is
  /// unavailable (e.g. tests / signed out).
  RealtimeChannel? watchMyVaults(void Function() onChange);

  /// Subscribes to a single vault's members + invitations, calling [onChange] on
  /// every change (drives the live members roster + invitations section).
  RealtimeChannel? watchVault(String vaultId, void Function() onChange);

  /// Closes a channel opened by [watchMyVaults] / [watchVault].
  Future<void> unwatch(RealtimeChannel channel);

  static FamilyVaultRepository instance = SupabaseFamilyVaultRepository();
}

class SupabaseFamilyVaultRepository implements FamilyVaultRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static const String _vaults = 'family_vaults';
  static const String _members = 'vault_members';

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<List<VaultSummary>> myVaults() async {
    final uid = _uid;
    if (uid == null) {
      // NULL USER — not signed in. Not an error; there's simply nothing to load.
      debugPrint('[FamilyVault] myVaults skipped — no signed-in user');
      return const [];
    }

    // Two independent queries instead of a PostgREST embed
    // (`vault_members.select('role, family_vaults(*)')`). The embed depends on
    // PostgREST detecting the FK relationship, which fails with a PGRST200
    // "could not find a relationship" error if the schema cache is stale or the
    // FK isn't introspected — a common, confusing cause of the load failing.
    // Reading each table directly is robust to that. RLS already scopes both
    // reads to vaults the user belongs to; the explicit eq is defense-in-depth.

    // 1) My memberships → vault_id + my role.
    debugPrint('[FamilyVault] loading memberships for uid=$uid');
    final memberRows = await _client
        .from(_members)
        .select('vault_id, role')
        .eq('auth_user_id', uid);
    debugPrint('[FamilyVault] membership rows: ${memberRows.length}');
    if (memberRows.isEmpty) return const []; // EMPTY RESPONSE → empty state

    final roleByVault = <String, VaultRole>{};
    for (final r in memberRows) {
      final vid = r['vault_id']?.toString();
      if (vid != null) roleByVault[vid] = VaultRoleX.fromName(r['role'] as String?);
    }

    // 2) The vaults themselves (RLS returns only those I'm a member of).
    final vaultRows = await _client
        .from(_vaults)
        .select()
        .order('created_at', ascending: false);
    debugPrint('[FamilyVault] vault rows: ${vaultRows.length}');

    final out = <VaultSummary>[];
    for (final row in vaultRows) {
      final vault = FamilyVault.fromRow(row);
      final role = roleByVault[vault.id];
      if (role == null) continue; // not one of my memberships
      out.add(VaultSummary(vault: vault, myRole: role));
    }
    debugPrint('[FamilyVault] myVaults resolved: ${out.length}');
    return out;
  }

  @override
  Future<FamilyVault> createVault(String name) async {
    // Create via the SECURITY DEFINER RPC create_family_vault(), which stamps
    // the owner from the SERVER's auth.uid() and never trusts a client-sent id.
    // This is what fixes the 42501 "new row violates RLS" — a direct
    // insert(owner_auth_user_id: currentUser.id) fails whenever the cached
    // client id ≠ the server's auth.uid(); the RPC removes that mismatch and
    // bypasses the table WITH CHECK entirely (see 20260730 migration).
    //
    // Best-effort: refresh a stale token first so a fresh JWT is sent (a truly
    // expired session makes auth.uid() null and the RPC raises a clear error).
    final session = _client.auth.currentSession;
    if (session != null && session.isExpired) {
      debugPrint('[FamilyVault] session expired → refreshing before create');
      try {
        await _client.auth.refreshSession();
      } catch (e) {
        debugPrint('[FamilyVault] refreshSession failed: $e');
      }
    }
    debugPrint('Current user: ${_client.auth.currentUser?.id}');
    debugPrint('[FamilyVault] createVault via RPC, name="${name.trim()}"');

    try {
      // The RPC returns the inserted family_vaults row (a JSON object).
      final res = await _client.rpc(
        'create_family_vault',
        params: {'p_name': name.trim()},
      );
      final row = (res is List)
          ? Map<String, dynamic>.from(res.first as Map)
          : Map<String, dynamic>.from(res as Map);
      debugPrint('[FamilyVault] createVault OK id=${row['id']}');
      return FamilyVault.fromRow(row);
    } on PostgrestException catch (e) {
      // Full backend error so the cause is never hidden.
      debugPrint('[FamilyVault] createVault FAILED (PostgrestException)');
      debugPrint('code: ${e.code}');
      debugPrint('message: ${e.message}');
      debugPrint('details: ${e.details}');
      debugPrint('hint: ${e.hint}');
      rethrow;
    } catch (e) {
      debugPrint('[FamilyVault] createVault FAILED: ${e.runtimeType} — $e');
      rethrow;
    }
  }

  @override
  Future<List<VaultMember>> members(String vaultId) async {
    debugPrint('[FamilyVault] loading members for vault=$vaultId');
    final rows = await _client
        .from(_members)
        .select()
        .eq('vault_id', vaultId);
    debugPrint('[FamilyVault] member rows: ${rows.length}');
    final list = [for (final r in rows) VaultMember.fromRow(r)];
    // Most-privileged first, then by name for a stable roster.
    list.sort((a, b) {
      final byRole = b.role.index.compareTo(a.role.index);
      if (byRole != 0) return byRole;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return list;
  }

  @override
  Future<void> renameVault(String id, String name) async {
    // Through an RPC (not a direct UPDATE) so the rename is server-authorized
    // (owner only) and audited (see 20260732).
    await _client.rpc('rename_family_vault',
        params: {'p_vault': id, 'p_name': name.trim()});
  }

  @override
  Future<void> deleteVault(String id) async {
    // Through an RPC so the delete is server-authorized (owner only); cascades
    // remove members, invitations, audit rows and notification events.
    await _client.rpc('delete_family_vault', params: {'p_vault': id});
  }

  @override
  Future<void> updateMemberRole(String memberId, VaultRole role) async {
    // Server-enforced: admin/owner only, never assigns 'owner'.
    await _client.rpc('set_vault_member_role',
        params: {'p_member_id': memberId, 'p_role': role.name});
  }

  @override
  Future<void> removeMember(String memberId) async {
    // Server-enforced: admin removes a member, or a member leaves; owner can't
    // be removed.
    await _client.rpc('remove_vault_member', params: {'p_member_id': memberId});
  }

  @override
  Future<void> transferOwnership(
      String vaultId, String newOwnerAuthUserId) async {
    await _client.rpc('transfer_vault_ownership', params: {
      'p_vault': vaultId,
      'p_new_owner': newOwnerAuthUserId,
    });
  }

  // ---- Invitations ---------------------------------------------------------

  @override
  Future<VaultInvitation> invite(
    String vaultId,
    VaultRole role, {
    String? email,
    String? phone,
  }) async {
    debugPrint('[FamilyVault] invite vault=$vaultId role=${role.name} '
        'email=$email phone=$phone');
    final res = await _client.rpc('invite_to_vault', params: {
      'p_vault': vaultId,
      'p_role': role.name,
      'p_email': email?.trim(),
      'p_phone': phone?.trim(),
    });
    final row = (res is List)
        ? Map<String, dynamic>.from(res.first as Map)
        : Map<String, dynamic>.from(res as Map);
    return VaultInvitation.fromRow(row);
  }

  @override
  Future<List<VaultInvitation>> invitationsForVault(String vaultId) async {
    final rows = await _client
        .from('vault_invitations')
        .select()
        .eq('vault_id', vaultId)
        .order('created_at', ascending: false);
    return [for (final r in rows) VaultInvitation.fromRow(r)];
  }

  @override
  Future<List<VaultInvitation>> myPendingInvitations() async {
    if (_uid == null) return const [];
    // RLS returns only pending invitations whose email/phone match the caller's
    // profile — so a simple filtered select is safe and sufficient.
    final rows = await _client
        .from('vault_invitations')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    final list = [for (final r in rows) VaultInvitation.fromRow(r)];
    debugPrint('[FamilyVault] my pending invitations: ${list.length}');
    return list;
  }

  @override
  Future<void> acceptInvitation(String invitationId) async {
    await _client.rpc('accept_vault_invitation',
        params: {'p_invitation_id': invitationId});
  }

  @override
  Future<void> declineInvitation(String invitationId) async {
    await _client.rpc('decline_vault_invitation',
        params: {'p_invitation_id': invitationId});
  }

  @override
  Future<void> cancelInvitation(String invitationId) async {
    await _client.rpc('cancel_vault_invitation',
        params: {'p_invitation_id': invitationId});
  }

  @override
  Future<void> resendInvitation(String invitationId, {VaultRole? role}) async {
    await _client.rpc('resend_vault_invitation', params: {
      'p_invitation_id': invitationId,
      'p_role': role?.name,
    });
  }

  // ---- Audit + realtime ----------------------------------------------------

  @override
  Future<List<VaultAuditEntry>> auditLog(String vaultId, {int limit = 50}) async {
    final rows = await _client
        .from('vault_audit_log')
        .select()
        .eq('vault_id', vaultId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) VaultAuditEntry.fromRow(r)];
  }

  @override
  RealtimeChannel? watchMyVaults(void Function() onChange) {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final channel = _client.channel('fv_all_$uid');
      for (final table in const [
        'vault_members',
        'vault_invitations',
        'family_vaults',
      ]) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => onChange(),
        );
      }
      channel.subscribe();
      debugPrint('[FamilyVault] realtime: watching all vaults');
      return channel;
    } catch (e) {
      // Realtime is a live-update nicety; a failure must never break the screen
      // (pull-to-refresh still works).
      debugPrint('[FamilyVault] watchMyVaults failed: $e');
      return null;
    }
  }

  @override
  RealtimeChannel? watchVault(String vaultId, void Function() onChange) {
    try {
      final channel = _client.channel('fv_vault_$vaultId');
      for (final table in const ['vault_members', 'vault_invitations']) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'vault_id',
            value: vaultId,
          ),
          callback: (_) => onChange(),
        );
      }
      channel.subscribe();
      debugPrint('[FamilyVault] realtime: watching vault=$vaultId');
      return channel;
    } catch (e) {
      debugPrint('[FamilyVault] watchVault failed: $e');
      return null;
    }
  }

  @override
  Future<void> unwatch(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (e) {
      debugPrint('[FamilyVault] unwatch failed: $e');
    }
  }
}
