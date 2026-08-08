import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';

/// Resolves a wallet label ("Property Wallet") to the Postgres table holding
/// its records ("w_property_wallet").
///
/// Since the 20260727 migration every wallet owns its own table instead of
/// sharing one wide `documents` table, because each wallet stores a different
/// shape of record. The old table survives as a READ-ONLY view unioning them
/// all, which is what cross-wallet reads (search, dashboards, export) use.
///
/// [slugFor] is the client-side twin of the database's `public.ino_wallet_slug()`.
/// The two MUST stay in step: the app writes to the table that function created.
class WalletTables {
  WalletTables._();

  /// The read-only union view. Use for anything that spans wallets; never write.
  static const String documentsView = 'documents';

  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9]+');
  static final RegExp _edgeUnderscores = RegExp(r'^_+|_+$');

  /// "My Pets 🐾" -> "w_my_pets". Mirrors `ino_wallet_slug()` exactly: lowercase,
  /// runs of non-alphanumerics collapse to `_`, edge underscores dropped, capped
  /// at 40 characters, then prefixed.
  static String slugFor(String walletLabel) {
    final squashed =
        walletLabel.trim().toLowerCase().replaceAll(_nonAlnum, '_');
    final trimmed = squashed.replaceAll(_edgeUnderscores, '');
    final capped = trimmed.length <= 40 ? trimmed : trimmed.substring(0, 40);
    return 'w_$capped';
  }

  static SupabaseClient get _client => Supabase.instance.client;

  /// Cached `public.wallets` registry. Wallet tables are schema objects, so this
  /// changes only when someone creates a wallet - cheap to hold, wasteful to
  /// re-fetch on every read.
  static List<String>? _slugs;

  /// Every wallet table that exists, from the registry. Falls back to an empty
  /// list when signed out or offline; callers treat that as "nothing to do".
  static Future<List<String>> allSlugs() async {
    final cached = _slugs;
    if (cached != null) return cached;
    try {
      final rows = await _client
          .from('wallets')
          .select('slug')
          .limit(NetGuard.maxRows)
          .timeout(NetGuard.query);
      final slugs = [for (final r in rows) r['slug'] as String];
      _slugs = slugs;
      return slugs;
    } catch (_) {
      return const [];
    }
  }

  /// Drops the cache after a wallet is created or removed.
  static void invalidate() => _slugs = null;

  /// Creates the table behind a user-made wallet and returns its slug.
  ///
  /// The RPC is `security definer` (it creates schema objects) and validates the
  /// name server-side, so an invalid name throws rather than reaching the DDL.
  static Future<String> createCustomWallet(
    String name, {
    String iconKey = 'folder',
    int? colorValue,
  }) async {
    final slug = await _client.rpc('create_custom_wallet', params: {
      'p_name': name,
      'p_icon': iconKey,
      'p_color': ?colorValue,
    }) as String;
    invalidate();
    return slug;
  }

  /// Deletes the signed-in user's rows in a custom wallet WITHOUT dropping the
  /// table - another account may have created a wallet with the same name and
  /// therefore shares it. RLS scopes the delete to the caller.
  static Future<int> clearCustomWallet(String slug) async {
    final deleted =
        await _client.rpc('clear_custom_wallet', params: {'p_slug': slug});
    return (deleted as num?)?.toInt() ?? 0;
  }
}
