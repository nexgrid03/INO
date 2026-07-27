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

  /// Changes a member's role (admin/owner only, enforced by RLS).
  Future<void> updateMemberRole(String memberId, VaultRole role);

  /// Removes a member (admin/owner, or the member themselves, per RLS).
  Future<void> removeMember(String memberId);

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
    await _client.from(_vaults).update({
      'name': name.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  @override
  Future<void> deleteVault(String id) async {
    await _client.from(_vaults).delete().eq('id', id);
  }

  @override
  Future<void> updateMemberRole(String memberId, VaultRole role) async {
    await _client
        .from(_members)
        .update({'role': role.name})
        .eq('id', memberId);
  }

  @override
  Future<void> removeMember(String memberId) async {
    await _client.from(_members).delete().eq('id', memberId);
  }
}
