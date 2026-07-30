import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vault_item.dart';

/// The ONLY place that reads/writes the `vault_items` and `vault_meta` tables.
///
/// It deals purely in database rows and ciphertext — encryption/decryption is
/// the [VaultController]'s job. Every call is implicitly scoped to the signed-in
/// user by Row-Level Security (`auth.uid() = user_id`).
class VaultRepository {
  VaultRepository._();
  static final VaultRepository instance = VaultRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  static const String _itemsTable = 'vault_items';
  static const String _metaTable = 'vault_meta';

  /// The signed-in user's id (throws if called while logged out).
  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Vault accessed while signed out.');
    }
    return id;
  }

  // --- Vault meta (KDF params + verifier) -----------------------------------

  /// Returns the user's vault metadata, or null if the vault isn't set up yet.
  Future<VaultMeta?> fetchMeta() async {
    final row = await _client
        .from(_metaTable)
        .select()
        .eq('user_id', _uid)
        .maybeSingle();
    return row == null ? null : VaultMeta.fromMap(row);
  }

  /// Creates the vault metadata row when the master password is first set.
  Future<VaultMeta> createMeta({
    required String saltB64,
    required String verifierB64,
    required int iterations,
  }) async {
    final row = await _client
        .from(_metaTable)
        .insert({
          'user_id': _uid,
          'kdf_salt': saltB64,
          'verifier': verifierB64,
          'iterations': iterations,
        })
        .select()
        .single();
    return VaultMeta.fromMap(row);
  }

  // --- Vault items ----------------------------------------------------------

  /// All of the user's entries, newest first. Rows carry the encrypted
  /// `secret_enc` blob plus clear metadata.
  Future<List<Map<String, dynamic>>> fetchItems() async {
    final rows = await _client
        .from(_itemsTable)
        .select()
        .eq('user_id', _uid)
        .order('updated_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Inserts an entry and returns the stored row.
  Future<Map<String, dynamic>> insertItem({
    required String title,
    required String secretEnc,
    String? url,
    required String category,
    required bool favorite,
  }) async {
    return _client
        .from(_itemsTable)
        .insert({
          'user_id': _uid,
          'title': title,
          'secret_enc': secretEnc,
          'url': url,
          'category': category,
          'favorite': favorite,
        })
        .select()
        .single();
  }

  /// Updates an entry and returns the fresh row.
  Future<Map<String, dynamic>> updateItem({
    required String id,
    required String title,
    required String secretEnc,
    String? url,
    required String category,
    required bool favorite,
  }) async {
    return _client
        .from(_itemsTable)
        .update({
          'title': title,
          'secret_enc': secretEnc,
          'url': url,
          'category': category,
          'favorite': favorite,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', _uid)
        .select()
        .single();
  }

  /// Deletes an entry by id.
  Future<void> deleteItem(String id) async {
    await _client.from(_itemsTable).delete().eq('id', id).eq('user_id', _uid);
  }
}
