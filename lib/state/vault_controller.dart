import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vault_item.dart';
import '../repositories/vault_repository.dart';
import '../services/vault_crypto_service.dart';
import '../services/vault_key_store.dart';

/// Lifecycle of the vault for the current session.
enum VaultStatus { loading, needsSetup, locked, unlocked, error }

/// Coordinates the Password Vault: master-password setup/unlock, the in-memory
/// key, and CRUD over encrypted entries. A single [ChangeNotifier] the UI
/// listens to via [instance]; there's exactly one vault per signed-in user.
class VaultController extends ChangeNotifier {
  VaultController._();
  static final VaultController instance = VaultController._();

  final VaultRepository _repo = VaultRepository.instance;
  final VaultCryptoService _crypto = VaultCryptoService.instance;
  final VaultKeyStore _keyStore = VaultKeyStore.instance;

  VaultStatus _status = VaultStatus.loading;
  VaultStatus get status => _status;

  String? _error;
  String? get error => _error;

  final List<VaultItem> _items = [];

  String _query = '';
  String get query => _query;

  VaultMeta? _meta;
  SecretKey? _key; // present only while unlocked

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// Entries filtered by the current search [query], favorites first.
  List<VaultItem> get items {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? List<VaultItem>.from(_items)
        : _items
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.username.toLowerCase().contains(q) ||
                (e.url ?? '').toLowerCase().contains(q))
            .toList();
    list.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  int get count => _items.length;

  // --- Session lifecycle ----------------------------------------------------

  /// Loads vault metadata and decides the initial state: needs setup, locked,
  /// or (if a key is still cached from this session) already unlocked.
  Future<void> initialize() async {
    _setStatus(VaultStatus.loading);
    try {
      final uid = _userId;
      if (uid == null) {
        _fail('You must be signed in to use the vault.');
        return;
      }
      _meta = await _repo.fetchMeta();
      if (_meta == null) {
        _setStatus(VaultStatus.needsSetup);
        return;
      }
      final cached = await _keyStore.readKey(uid);
      if (cached != null) {
        _key = cached;
        await _loadItems();
        _setStatus(VaultStatus.unlocked);
      } else {
        _setStatus(VaultStatus.locked);
      }
    } catch (e) {
      _fail('Could not open the vault. $e');
    }
  }

  /// First-time setup: derive a key from [masterPassword], seal a verifier, and
  /// persist the metadata. Leaves the vault unlocked.
  Future<void> setupMasterPassword(String masterPassword) async {
    final uid = _userId;
    if (uid == null) {
      _fail('You must be signed in to use the vault.');
      return;
    }
    _setStatus(VaultStatus.loading);
    try {
      final salt = _crypto.generateSalt();
      final key = await _crypto.deriveKey(masterPassword, salt);
      final verifier =
          await _crypto.encrypt(VaultMeta.verifierPlaintext, key);
      _meta = await _repo.createMeta(
        saltB64: salt,
        verifierB64: verifier,
        iterations: VaultCryptoService.defaultIterations,
      );
      _key = key;
      await _keyStore.cacheKey(uid, key);
      _items.clear();
      _setStatus(VaultStatus.unlocked);
    } catch (e) {
      _fail('Could not create the vault. $e');
    }
  }

  /// Attempts to unlock with [masterPassword]. Returns true on success; on a
  /// wrong password it returns false and leaves the vault locked.
  Future<bool> unlock(String masterPassword) async {
    final uid = _userId;
    final meta = _meta;
    if (uid == null || meta == null) {
      _fail('Vault is not ready.');
      return false;
    }
    _setStatus(VaultStatus.loading);
    try {
      final key = await _crypto.deriveKey(
        masterPassword,
        meta.salt,
        iterations: meta.iterations,
      );
      // Verify by decrypting the stored verifier; wrong key throws.
      final check = await _crypto.decrypt(meta.verifier, key);
      if (check != VaultMeta.verifierPlaintext) {
        _setStatus(VaultStatus.locked);
        return false;
      }
      _key = key;
      await _keyStore.cacheKey(uid, key);
      await _loadItems();
      _setStatus(VaultStatus.unlocked);
      return true;
    } on SecretBoxAuthenticationError {
      // Wrong master password.
      _setStatus(VaultStatus.locked);
      return false;
    } catch (e) {
      _fail('Could not unlock the vault. $e');
      return false;
    }
  }

  /// Locks the vault: forgets the in-memory key and wipes the cached one.
  Future<void> lock() async {
    final uid = _userId;
    _key = null;
    _items.clear();
    if (uid != null) await _keyStore.clear(uid);
    _setStatus(VaultStatus.locked);
  }

  // --- CRUD -----------------------------------------------------------------

  Future<void> addItem({
    required String title,
    required String username,
    required String password,
    String? url,
    String? notes,
    required VaultCategory category,
    bool favorite = false,
  }) async {
    final key = _requireKey();
    final secret = await _crypto.encrypt(
      _encodeSecret(username, password, notes),
      key,
    );
    final row = await _repo.insertItem(
      title: title.trim(),
      secretEnc: secret,
      url: _clean(url),
      category: category.name,
      favorite: favorite,
    );
    _items.insert(0, await _rowToItem(row));
    notifyListeners();
  }

  Future<void> updateItem(
    VaultItem original, {
    required String title,
    required String username,
    required String password,
    String? url,
    String? notes,
    required VaultCategory category,
    required bool favorite,
  }) async {
    final key = _requireKey();
    final secret = await _crypto.encrypt(
      _encodeSecret(username, password, notes),
      key,
    );
    final row = await _repo.updateItem(
      id: original.id,
      title: title.trim(),
      secretEnc: secret,
      url: _clean(url),
      category: category.name,
      favorite: favorite,
    );
    final updated = await _rowToItem(row);
    final i = _items.indexWhere((e) => e.id == original.id);
    if (i >= 0) {
      _items[i] = updated;
    } else {
      _items.insert(0, updated);
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(VaultItem item) async {
    await updateItem(
      item,
      title: item.title,
      username: item.username,
      password: item.password,
      url: item.url,
      notes: item.notes,
      category: item.category,
      favorite: !item.favorite,
    );
  }

  Future<void> deleteItem(String id) async {
    await _repo.deleteItem(id);
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  // --- Internals ------------------------------------------------------------

  Future<void> _loadItems() async {
    final rows = await _repo.fetchItems();
    _items
      ..clear()
      ..addAll(await Future.wait(rows.map(_rowToItem)));
  }

  Future<VaultItem> _rowToItem(Map<String, dynamic> row) async {
    final key = _requireKey();
    final secret = _decodeSecret(await _crypto.decrypt(
      row['secret_enc'] as String,
      key,
    ));
    return VaultItem(
      id: row['id'] as String,
      title: row['title'] as String,
      username: secret.$1,
      password: secret.$2,
      notes: secret.$3,
      url: row['url'] as String?,
      category: VaultCategory.fromId(row['category'] as String?),
      favorite: (row['favorite'] as bool?) ?? false,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  String _encodeSecret(String username, String password, String? notes) {
    return jsonEncode({
      'u': username,
      'p': password,
      if (notes != null && notes.trim().isNotEmpty) 'n': notes.trim(),
    });
  }

  (String, String, String?) _decodeSecret(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return (
      (map['u'] as String?) ?? '',
      (map['p'] as String?) ?? '',
      map['n'] as String?,
    );
  }

  String? _clean(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  SecretKey _requireKey() {
    final key = _key;
    if (key == null) {
      throw StateError('Vault is locked.');
    }
    return key;
  }

  void _setStatus(VaultStatus status) {
    _status = status;
    if (status != VaultStatus.error) _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _status = VaultStatus.error;
    notifyListeners();
  }
}
