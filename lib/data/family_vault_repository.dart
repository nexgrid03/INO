import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../core/net/stream_download.dart';
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

  /// Invites an existing INO user by phone number, name or email. The server
  /// resolves [query] against the users table; a [VaultUserNotFound] means
  /// nobody has an INO account under that identifier, [VaultUserAmbiguous]
  /// means several users share that name.
  Future<VaultInvitation> inviteUser(String vaultId, VaultRole role, String query);

  // ---- Join requests -------------------------------------------------------

  /// Families whose name matches [name] exactly (case-insensitive).
  Future<List<FamilyMatch>> searchFamilies(String name);

  /// Asks to join [vaultId]; every owner/admin of that family is notified.
  Future<VaultJoinRequest> requestToJoin(String vaultId);

  /// Pending requests addressed to families the caller can manage.
  Future<List<VaultJoinRequest>> incomingJoinRequests();

  /// The caller's own pending requests.
  Future<List<VaultJoinRequest>> myJoinRequests();

  /// Approves a request (owner/admin), adding the requester with [role].
  Future<void> approveJoinRequest(String requestId, VaultRole role);

  /// Declines a request (owner/admin).
  Future<void> declineJoinRequest(String requestId);

  /// Withdraws the caller's own pending request.
  Future<void> cancelJoinRequest(String requestId);

  // ---- Co-owners -----------------------------------------------------------

  /// Makes [memberId] an owner too (caller must be an owner). Co-owners can
  /// invite, approve joins, add documents and rename; only the primary owner
  /// can delete or transfer.
  Future<void> promoteToOwner(String memberId);

  // ---- Shared documents ----------------------------------------------------

  /// Every document shared into [vaultId], newest first.
  ///
  /// RLS returns rows only while the caller holds a live membership, so this
  /// comes back empty the moment they are removed — no client-side filtering
  /// is involved and none is trusted.
  Future<List<VaultDocument>> documents(String vaultId);

  /// Shares a document the caller already owns into [vaultId]. Requires editor
  /// or above; the server rejects anything less.
  Future<VaultDocument> shareDocument({
    required String vaultId,
    required String objectPath,
    required String name,
    String? category,
    int? sizeBytes,
    String? contentType,
    String? sourceTable,
    String? sourceId,
    String? note,
  });

  /// Withdraws a shared document. Editors may remove only what they shared;
  /// admins and the owner may remove anything.
  Future<void> removeDocument(String documentId);

  /// A short-lived URL for opening/downloading a shared document.
  ///
  /// The URL is minted against the storage layer, where a policy re-checks
  /// vault membership on every read — so this throws for a removed member even
  /// if they somehow still had the row, and previously-issued URLs stop
  /// resolving too.
  Future<String> documentUrl(VaultDocument doc, {int expiresInSeconds = 900});

  /// The raw bytes of a shared document, for in-app preview.
  Future<Uint8List> downloadDocument(VaultDocument doc);

  /// Streams a shared document straight to [dest] on disk, without holding the
  /// whole file in memory. Use this whenever the end state is a file (opening
  /// in an external app, saving); [downloadDocument] is only for previews that
  /// genuinely need the bytes.
  Future<void> downloadDocumentToFile(VaultDocument doc, File dest);

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

    debugPrint('[FamilyVault] loading myVaults for uid=$uid');
    final results = await Future.wait([
      _client
          .from(_members)
          .select('vault_id, role')
          .eq('auth_user_id', uid)
          .limit(NetGuard.maxRows)
          .timeout(NetGuard.query),
      _client
          .from(_vaults)
          .select()
          .order('created_at', ascending: false)
          .limit(NetGuard.maxRows)
          .timeout(NetGuard.query),
    ]);

    final memberRows = results[0] as List<dynamic>;
    final vaultRows = results[1] as List<dynamic>;

    debugPrint('[FamilyVault] membership rows: ${memberRows.length}, vault rows: ${vaultRows.length}');
    if (memberRows.isEmpty || vaultRows.isEmpty) return const [];

    final roleByVault = <String, VaultRole>{};
    for (final r in memberRows) {
      final vid = r['vault_id']?.toString();
      if (vid != null) roleByVault[vid] = VaultRoleX.fromName(r['role'] as String?);
    }

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
      ).timeout(NetGuard.mutation);
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
        .eq('vault_id', vaultId)
        .limit(NetGuard.maxRows)
        .timeout(NetGuard.query);
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
        params: {'p_vault': id, 'p_name': name.trim()}).timeout(NetGuard.mutation);
  }

  @override
  Future<void> deleteVault(String id) async {
    // Through an RPC so the delete is server-authorized (owner only); cascades
    // remove members, invitations, audit rows and notification events.
    await _client
        .rpc('delete_family_vault', params: {'p_vault': id})
        .timeout(NetGuard.mutation);
  }

  @override
  Future<void> updateMemberRole(String memberId, VaultRole role) async {
    // Server-enforced: admin/owner only, never assigns 'owner'.
    await _client.rpc('set_vault_member_role', params: {
      'p_member_id': memberId,
      'p_role': role.name,
    }).timeout(NetGuard.mutation);
  }

  @override
  Future<void> removeMember(String memberId) async {
    // Server-enforced: admin removes a member, or a member leaves; owner can't
    // be removed.
    await _client
        .rpc('remove_vault_member', params: {'p_member_id': memberId})
        .timeout(NetGuard.mutation);
  }

  @override
  Future<void> transferOwnership(
      String vaultId, String newOwnerAuthUserId) async {
    await _client.rpc('transfer_vault_ownership', params: {
      'p_vault': vaultId,
      'p_new_owner': newOwnerAuthUserId,
    }).timeout(NetGuard.mutation);
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
    }).timeout(NetGuard.mutation);
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
        .order('created_at', ascending: false)
        .limit(NetGuard.maxRows)
        .timeout(NetGuard.query);
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
        .order('created_at', ascending: false)
        .limit(NetGuard.maxRows)
        .timeout(NetGuard.query);
    final list = [for (final r in rows) VaultInvitation.fromRow(r)];
    debugPrint('[FamilyVault] my pending invitations: ${list.length}');
    return list;
  }

  @override
  Future<void> acceptInvitation(String invitationId) async {
    await _client.rpc('accept_vault_invitation',
        params: {'p_invitation_id': invitationId}).timeout(NetGuard.mutation);
  }

  @override
  Future<void> declineInvitation(String invitationId) async {
    await _client.rpc('decline_vault_invitation',
        params: {'p_invitation_id': invitationId}).timeout(NetGuard.mutation);
  }

  @override
  Future<void> cancelInvitation(String invitationId) async {
    await _client.rpc('cancel_vault_invitation',
        params: {'p_invitation_id': invitationId}).timeout(NetGuard.mutation);
  }

  @override
  Future<void> resendInvitation(String invitationId, {VaultRole? role}) async {
    await _client.rpc('resend_vault_invitation', params: {
      'p_invitation_id': invitationId,
      'p_role': role?.name,
    }).timeout(NetGuard.mutation);
  }

  @override
  Future<VaultInvitation> inviteUser(
      String vaultId, VaultRole role, String query) async {
    debugPrint('[FamilyVault] inviteUser vault=$vaultId role=${role.name}');
    try {
      final res = await _client.rpc('invite_ino_user_to_vault', params: {
        'p_vault': vaultId,
        'p_role': role.name,
        'p_query': query.trim(),
      }).timeout(NetGuard.mutation);
      final row = (res is List)
          ? Map<String, dynamic>.from(res.first as Map)
          : Map<String, dynamic>.from(res as Map);
      return VaultInvitation.fromRow(row);
    } on PostgrestException catch (e) {
      // The RPC signals the two "who is this?" outcomes with specific codes
      // + hints so the sheet can word them properly.
      if (e.code == 'P0002' || e.hint == 'USER_NOT_FOUND') {
        throw VaultUserNotFound(query.trim(), e.message);
      }
      if (e.code == 'P0003' || e.hint == 'MULTIPLE_USERS') {
        throw VaultUserAmbiguous(query.trim(), e.message);
      }
      rethrow;
    }
  }

  // ---- Join requests -------------------------------------------------------

  static const String _joinRequests = 'vault_join_requests';

  @override
  Future<List<FamilyMatch>> searchFamilies(String name) async {
    final res = await _client
        .rpc('search_families', params: {'p_name': name.trim()})
        .timeout(NetGuard.query);
    final rows = (res as List?) ?? const [];
    return [
      for (final r in rows)
        FamilyMatch.fromRow(Map<String, dynamic>.from(r as Map))
    ];
  }

  @override
  Future<VaultJoinRequest> requestToJoin(String vaultId) async {
    final res = await _client.rpc('request_to_join_family', params: {
      'p_vault': vaultId,
    }).timeout(NetGuard.mutation);
    final row = (res is List)
        ? Map<String, dynamic>.from(res.first as Map)
        : Map<String, dynamic>.from(res as Map);
    return VaultJoinRequest.fromRow(row);
  }

  @override
  Future<List<VaultJoinRequest>> incomingJoinRequests() async {
    final uid = _uid;
    if (uid == null) return const [];
    // RLS returns rows for vaults the caller administers plus their own
    // requests; drop the latter so these are strictly "for me to decide".
    final rows = await _client
        .from(_joinRequests)
        .select()
        .eq('status', 'pending')
        .neq('requester_auth_user_id', uid)
        .order('created_at', ascending: false)
        .limit(NetGuard.maxRows)
        .timeout(NetGuard.query);
    return [for (final r in rows) VaultJoinRequest.fromRow(r)];
  }

  @override
  Future<List<VaultJoinRequest>> myJoinRequests() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from(_joinRequests)
        .select()
        .eq('status', 'pending')
        .eq('requester_auth_user_id', uid)
        .order('created_at', ascending: false)
        .limit(NetGuard.maxRows)
        .timeout(NetGuard.query);
    return [for (final r in rows) VaultJoinRequest.fromRow(r)];
  }

  @override
  Future<void> approveJoinRequest(String requestId, VaultRole role) async {
    await _client.rpc('approve_join_request', params: {
      'p_request': requestId,
      'p_role': role.name,
    }).timeout(NetGuard.mutation);
  }

  @override
  Future<void> declineJoinRequest(String requestId) async {
    await _client
        .rpc('decline_join_request', params: {'p_request': requestId})
        .timeout(NetGuard.mutation);
  }

  @override
  Future<void> cancelJoinRequest(String requestId) async {
    await _client
        .rpc('cancel_join_request', params: {'p_request': requestId})
        .timeout(NetGuard.mutation);
  }

  // ---- Co-owners -----------------------------------------------------------

  @override
  Future<void> promoteToOwner(String memberId) async {
    await _client.rpc('promote_vault_member_to_owner', params: {
      'p_member_id': memberId,
    }).timeout(NetGuard.mutation);
  }

  // ---- Shared documents ----------------------------------------------------

  static const String _documents = 'vault_documents';

  /// The bucket shared files live in. Same bucket as personal documents - a
  /// share does NOT copy the file, it grants read access to the original, which
  /// is what lets removal revoke access instead of leaving stray copies behind.
  static const String _bucket = 'documents';

  @override
  Future<List<VaultDocument>> documents(String vaultId) async {
    final rows = await _client
        .from(_documents)
        .select()
        .eq('vault_id', vaultId)
        .order('created_at', ascending: false)
        .limit(NetGuard.maxRows)
        .timeout(NetGuard.query);
    debugPrint('[FamilyVault] vault $vaultId documents: ${rows.length}');
    return [for (final r in rows) VaultDocument.fromRow(r)];
  }

  @override
  Future<VaultDocument> shareDocument({
    required String vaultId,
    required String objectPath,
    required String name,
    String? category,
    int? sizeBytes,
    String? contentType,
    String? sourceTable,
    String? sourceId,
    String? note,
  }) async {
    // Via the SECURITY DEFINER RPC rather than a direct insert: it makes the
    // editor check server-side and stamps `shared_by` from auth.uid(), so a
    // client cannot attribute a share to someone else.
    final row = await _client.rpc('share_document_to_vault', params: {
      'p_vault': vaultId,
      'p_object_path': objectPath,
      'p_name': name,
      'p_category': category,
      'p_size_bytes': sizeBytes,
      'p_content_type': contentType,
      'p_source_table': sourceTable,
      'p_source_id': sourceId,
      'p_note': note,
    }).timeout(NetGuard.mutation);
    return VaultDocument.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> removeDocument(String documentId) async {
    await _client.rpc('remove_vault_document', params: {
      'p_document': documentId,
    }).timeout(NetGuard.mutation);
  }

  @override
  Future<String> documentUrl(VaultDocument doc,
      {int expiresInSeconds = 900}) async {
    // Deliberately short-lived. The storage policy re-checks membership on
    // every read, so a removed member is cut off immediately regardless - but a
    // narrow window also limits how long a URL that leaves the app stays useful.
    return _client.storage
        .from(_bucket)
        .createSignedUrl(doc.objectPath, expiresInSeconds)
        .timeout(NetGuard.query);
  }

  @override
  Future<Uint8List> downloadDocument(VaultDocument doc) => _client.storage
      .from(_bucket)
      .download(doc.objectPath)
      .timeout(NetGuard.storage);

  @override
  Future<void> downloadDocumentToFile(VaultDocument doc, File dest) async {
    // Same short-lived signed URL as documentUrl - the storage policy re-checks
    // membership on every read, so a removed member is cut off here too.
    final url = await documentUrl(doc, expiresInSeconds: 600);
    await streamUrlToFile(
      url,
      dest,
      onError: (code) => StorageException(
          'Download failed (HTTP $code) for ${doc.objectPath}'),
    );
  }

  // ---- Audit + realtime ----------------------------------------------------

  @override
  Future<List<VaultAuditEntry>> auditLog(String vaultId, {int limit = 50}) async {
    final rows = await _client
        .from('vault_audit_log')
        .select()
        .eq('vault_id', vaultId)
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(NetGuard.query);
    return [for (final r in rows) VaultAuditEntry.fromRow(r)];
  }

  @override
  RealtimeChannel? watchMyVaults(void Function() onChange) {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final channel = _client.channel('fv_all_$uid');
      // The vault-list + invite badge only change when MY membership rows
      // change, so filter that stream server-side instead of waking this
      // client for every member row in every vault (a membership-churn storm
      // used to fan out to every connected device). Vault renames/deletes and
      // invitations (matched by email/phone, not uid) stay unfiltered.
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'vault_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'auth_user_id',
          value: uid,
        ),
        callback: (_) => onChange(),
      );
      for (final table in const [
        'vault_invitations',
        'family_vaults',
        'vault_join_requests',
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

/// Turns a Family Vault failure into something the user - or you, reading a bug
/// report - can act on.
///
/// This exists because the first version of the share sheets showed
/// "you may no longer have permission" for EVERY failure. That was actively
/// misleading: the most common cause is that the vault-documents migration has
/// not been applied yet, so the RPC does not exist, and the message sent an
/// Owner hunting for a permissions problem they did not have. Each
/// distinguishable cause now says what it actually is.
String describeVaultError(Object e) {
  if (e is PostgrestException) {
    final code = e.code ?? '';
    final message = e.message.toLowerCase();

    // PGRST202: the function isn't in PostgREST's schema cache. Two distinct
    // causes, and the second is easy to miss: either the migration was never
    // applied, OR it was applied through the SQL editor and PostgREST is still
    // serving a snapshot taken before it. The second case looks exactly like
    // the first from here - the function genuinely exists in the database - so
    // the message has to name both rather than send the reader hunting for a
    // migration they already ran.
    //
    // Matched NARROWLY, on PostgREST's own code and phrasing. An earlier
    // version also matched any message containing "does not exist", which
    // catches half the errors Postgres can raise - a missing column, a missing
    // relation, a bad cast - and reported every one of them as an unapplied
    // migration. That masked the real fault and sent the reader to re-run a
    // migration that was already applied. Breadth in an error matcher is not
    // helpfulness; it is a wrong answer delivered confidently.
    if (code == 'PGRST202' || message.contains('could not find the function')) {
      return 'Sharing is not available yet. Apply the vault-documents '
          'migration, then reload the API schema cache '
          "(run: notify pgrst, 'reload schema'). [$code]";
    }
    // Raised deliberately by share_document_to_vault() for a non-editor.
    if (code == '42501' || message.contains('only editors')) {
      return 'You need editor access in this vault to add documents.';
    }
    if (code == '23505') {
      return 'That document is already in this vault.';
    }
    // Anything else: show the real code, message, details and hint rather than
    // inventing a cause. An unexplained failure the user can quote beats a
    // wrong guess - and Postgres' `hint` is very often the actual fix.
    final parts = <String>[
      'Could not share (${e.code ?? 'error'})',
      e.message,
      if ((e.details ?? '').toString().trim().isNotEmpty)
        'Details: ${e.details}',
      if ((e.hint ?? '').trim().isNotEmpty) 'Hint: ${e.hint}',
    ];
    return parts.join('\n');
  }

  if (e is StorageException) {
    return 'Upload failed: ${e.message}';
  }

  final text = e.toString();
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('ClientException')) {
    return 'No connection. Check your internet and try again.';
  }
  return 'Could not share: $text';
}

/// The identifier given to [FamilyVaultRepository.inviteUser] matches no INO
/// account. The person has to install the app and sign up before they can be
/// invited.
class VaultUserNotFound implements Exception {
  const VaultUserNotFound(this.query, this.message);
  final String query;
  final String message;
  @override
  String toString() => message;
}

/// Several INO users share the name given to [FamilyVaultRepository.inviteUser];
/// the inviter should use a phone number or email instead.
class VaultUserAmbiguous implements Exception {
  const VaultUserAmbiguous(this.query, this.message);
  final String query;
  final String message;
  @override
  String toString() => message;
}
