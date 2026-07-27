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

  List<VaultSummary> get vaults => List.unmodifiable(_vaults);
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  bool get isEmpty => _vaults.isEmpty;
  String? get loadError => _loadError;

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

  /// Drops the in-memory cache and re-arms the loader so the next signed-in
  /// account loads its OWN vaults. Called from SessionReset on sign-out.
  void clear() {
    _vaults.clear();
    _loaded = false;
    _loading = false;
    _loadError = null;
    notifyListeners();
  }

  @visibleForTesting
  void reset() => clear();
}
