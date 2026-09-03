import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/family_vault_repository.dart';
import '../models/family_vault_models.dart';

/// The single source of truth for the user's Family Vaults — a notify-on-change
/// store backed by [FamilyVaultRepository] (Supabase). Mirrors the
/// ReminderStore/NotesStore shape: hydrate once, expose loading/error state,
/// and re-arm on sign-out via [clear] (wired into SessionReset).
class FamilyVaultStore extends ChangeNotifier {
  FamilyVaultStore._();
  static final FamilyVaultStore instance = FamilyVaultStore._();

  final List<VaultSummary> _vaults = [];
  bool _loaded = false;
  bool _loading = false;
  String? _loadError;

  /// Pending invitations addressed to the signed-in user — drives the badge and
  /// the "You've been invited" cards. Cached so the badge shows offline.
  final List<VaultInvitation> _pendingInvites = [];

  /// Realtime channel for live updates to the vault list + invite badge, and a
  /// short debounce so a burst of row changes triggers a single refresh.
  RealtimeChannel? _channel;
  Timer? _debounce;

  List<VaultSummary> get vaults => List.unmodifiable(_vaults);
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  bool get isEmpty => _vaults.isEmpty;
  String? get loadError => _loadError;

  List<VaultInvitation> get pendingInvites => List.unmodifiable(_pendingInvites);
  int get pendingInviteCount => _pendingInvites.length;

  /// Join requests waiting on THIS user's decision (they own/admin the
  /// family), and the user's own outgoing requests still waiting on an owner.
  final List<VaultJoinRequest> _incomingRequests = [];
  final List<VaultJoinRequest> _myRequests = [];
  List<VaultJoinRequest> get incomingJoinRequests =>
      List.unmodifiable(_incomingRequests);
  List<VaultJoinRequest> get myJoinRequests => List.unmodifiable(_myRequests);

  /// Everything that needs the user's attention on the Family Vault home.
  int get pendingActionCount =>
      _pendingInvites.length + _incomingRequests.length;

  String? _uid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool get _remote => _uid() != null;

  /// Hydrates the vault list once. Safe to call from a screen's initState.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await _load();
  }

  /// Pull-to-refresh.
  Future<void> reload() async {
    if (_loading) return;
    await _load();
  }

  Future<void> _load() async {
    if (!_remote) {
      // Signed out / tests → nothing to fetch.
      _loaded = true;
      return;
    }
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final data = await FamilyVaultRepository.instance.myVaults();
      _vaults
        ..clear()
        ..addAll(data);
      debugPrint('[FamilyVault] store loaded ${_vaults.length} vault(s)');
    } catch (e, st) {
      _loadError = _messageFor(e);
      // Log the exact failure category so the cause is unambiguous in the
      // console: missing table / RLS / bad query / network.
      debugPrint('[FamilyVault] load FAILED: ${e.runtimeType} — $e');
      if (e is PostgrestException) {
        debugPrint('[FamilyVault]   code=${e.code} details=${e.details} '
            'hint=${e.hint}');
      }
      debugPrint('$st');
    }
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  /// Turns a load failure into a specific, actionable message (and makes the
  /// "server not set up yet" case obvious rather than a generic network error).
  String _messageFor(Object e) {
    if (e is PostgrestException) {
      final code = e.code ?? '';
      final msg = e.message.toLowerCase();
      // 42P01 = undefined_table; PGRST205 = table missing from schema cache;
      // PGRST200 = relationship (embed) not found. All mean the Family Vault
      // schema hasn't been applied to this project yet.
      if (code == '42P01' ||
          code == 'PGRST205' ||
          code == 'PGRST200' ||
          msg.contains('does not exist') ||
          msg.contains('could not find')) {
        return 'Family Vault isn\'t set up on the server yet. '
            'Run the 20260728 migration, then try again.';
      }
      // 42501 = insufficient_privilege (an RLS/grant problem).
      if (code == '42501' || msg.contains('permission')) {
        return 'You don\'t have access to load family vaults right now.';
      }
    }
    return 'Couldn\'t load your family vaults. Check your connection.';
  }

  /// Creates a vault, prepends it to the list, and returns it. Rethrows on
  /// failure so the caller can show an error (the list is left unchanged).
  Future<FamilyVault> create(String name) async {
    final vault = await FamilyVaultRepository.instance.createVault(name);
    // The creator is always the owner (DB trigger guarantees the membership).
    _vaults.insert(0, VaultSummary(vault: vault, myRole: VaultRole.owner));
    notifyListeners();
    return vault;
  }

  /// Renames a vault in place (optimistic; rethrows + reloads on failure).
  Future<void> rename(String id, String name) async {
    final i = _vaults.indexWhere((v) => v.vault.id == id);
    if (i == -1) return;
    final previous = _vaults[i];
    _vaults[i] = VaultSummary(
      vault: FamilyVault(
        id: previous.vault.id,
        name: name.trim(),
        ownerAuthUserId: previous.vault.ownerAuthUserId,
        createdAt: previous.vault.createdAt,
      ),
      myRole: previous.myRole,
    );
    notifyListeners();
    try {
      await FamilyVaultRepository.instance.renameVault(id, name);
    } catch (e) {
      _vaults[i] = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Deletes a vault (owner only). Optimistic, with rollback + rethrow.
  Future<void> delete(String id) async {
    final i = _vaults.indexWhere((v) => v.vault.id == id);
    if (i == -1) return;
    final removed = _vaults.removeAt(i);
    notifyListeners();
    try {
      await FamilyVaultRepository.instance.deleteVault(id);
    } catch (e) {
      _vaults.insert(i.clamp(0, _vaults.length), removed);
      notifyListeners();
      rethrow;
    }
  }

  // ---- Invitations ---------------------------------------------------------

  /// Refreshes the signed-in user's pending invitations (badge + cards). Called
  /// on app open / login and after accept/decline. Never throws — a badge that
  /// can't refresh must not break the app.
  Future<void> refreshPendingInvitations() async {
    if (!_remote) return;
    try {
      final invites =
          await FamilyVaultRepository.instance.myPendingInvitations();
      _pendingInvites
        ..clear()
        ..addAll(invites);
      notifyListeners();
    } catch (e) {
      debugPrint('[FamilyVault] refreshPendingInvitations failed: $e');
    }
    await refreshJoinRequests();
  }

  /// Refreshes both directions of join requests. Never throws (see above);
  /// a failure here (e.g. the migration not applied yet) leaves the last
  /// known lists in place.
  Future<void> refreshJoinRequests() async {
    if (!_remote) return;
    try {
      final results = await Future.wait([
        FamilyVaultRepository.instance.incomingJoinRequests(),
        FamilyVaultRepository.instance.myJoinRequests(),
      ]);
      _incomingRequests
        ..clear()
        ..addAll(results[0]);
      _myRequests
        ..clear()
        ..addAll(results[1]);
      notifyListeners();
    } catch (e) {
      debugPrint('[FamilyVault] refreshJoinRequests failed: $e');
    }
  }

  /// Sends a request to join [vaultId] and shows it under "your requests".
  /// Rethrows so the sheet can explain a rejection (already a member, …).
  Future<VaultJoinRequest> requestToJoin(String vaultId) async {
    final req = await FamilyVaultRepository.instance.requestToJoin(vaultId);
    _myRequests.insert(0, req);
    notifyListeners();
    return req;
  }

  /// Approves an incoming request (owner/admin) with [role], then reloads the
  /// vault list so the new member count is right. Rethrows.
  Future<void> approveJoinRequest(String requestId, VaultRole role) async {
    await FamilyVaultRepository.instance.approveJoinRequest(requestId, role);
    _incomingRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
    await refreshJoinRequests();
  }

  /// Declines an incoming request. Rethrows.
  Future<void> declineJoinRequest(String requestId) async {
    await FamilyVaultRepository.instance.declineJoinRequest(requestId);
    _incomingRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
  }

  /// Withdraws one of the user's own pending requests. Rethrows.
  Future<void> cancelJoinRequest(String requestId) async {
    await FamilyVaultRepository.instance.cancelJoinRequest(requestId);
    _myRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
  }

  /// Accepts an invitation, then refreshes vaults (a new membership appeared)
  /// and the pending list. Rethrows on failure.
  Future<void> acceptInvitation(String invitationId) async {
    await FamilyVaultRepository.instance.acceptInvitation(invitationId);
    _pendingInvites.removeWhere((i) => i.id == invitationId);
    notifyListeners();
    await _load();
    await refreshPendingInvitations();
  }

  /// Declines an invitation and drops it from the pending list. Rethrows.
  Future<void> declineInvitation(String invitationId) async {
    await FamilyVaultRepository.instance.declineInvitation(invitationId);
    _pendingInvites.removeWhere((i) => i.id == invitationId);
    notifyListeners();
  }

  // ---- Realtime ------------------------------------------------------------

  /// Opens a realtime subscription so the vault list and invite badge update
  /// live when memberships / invitations / vaults change on the server (e.g. an
  /// admin invites you, or you're removed elsewhere). Safe to call repeatedly —
  /// it no-ops if already subscribed. Idempotent + failure-tolerant.
  void startRealtime() {
    if (_channel != null || !_remote) return;
    _channel = FamilyVaultRepository.instance.watchMyVaults(_onRealtimeChange);
  }

  /// Debounced so a burst of row changes (e.g. a transfer touches several rows)
  /// collapses into one refresh of the list + pending invitations.
  ///
  /// If a reload is already running when the timer fires, the refresh is
  /// re-armed rather than dropped or stacked: heavy membership churn therefore
  /// costs at most one reload at a time, with one trailing reload for the
  /// final state - never a reload-per-event storm.
  void _onRealtimeChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), () async {
      if (_loading) {
        _onRealtimeChange();
        return;
      }
      await reload();
      await refreshPendingInvitations();
    });
  }

  /// Tears down the realtime subscription (sign-out / dispose).
  void stopRealtime() {
    _debounce?.cancel();
    _debounce = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) FamilyVaultRepository.instance.unwatch(ch);
  }

  /// Drops the in-memory cache and re-arms the loader so the next signed-in
  /// account loads its OWN vaults. Called from SessionReset on sign-out.
  void clear() {
    stopRealtime();
    _vaults.clear();
    _pendingInvites.clear();
    _incomingRequests.clear();
    _myRequests.clear();
    _loaded = false;
    _loading = false;
    _loadError = null;
    notifyListeners();
  }

  @visibleForTesting
  void reset() => clear();
}
