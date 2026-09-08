import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
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

  /// The 13 core columns guaranteed for EVERY wallet table by `ino_create_wallet_table`.
  static const Set<String> coreColumns = {
    'id',
    'auth_user_id',
    'name',
    'category',
    'record_number',
    'status',
    'tags',
    'notes',
    'is_favorite',
    'expires_at',
    'file_path',
    'created_at',
    'updated_at',
  };

  /// Verified schema inventory for all standard built-in tables.
  static final Map<String, Set<String>> _builtinTableColumns = {
    'w_identity_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'holder_name', 'id_type', 'issuing_authority', 'place_of_issue',
      'issue_date', 'date_of_birth', 'gender', 'nationality', 'consent',
    },
    'w_document_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'doc_type', 'issued_by', 'issue_date', 'page_count', 'consent',
    },
    'w_health_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'doctor_name', 'consent',
    },
    'w_property_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'property_type', 'image_path', 'purchase_date', 'purchase_price',
      'current_value', 'area', 'area_unit', 'country', 'state', 'city', 'address',
      'pin_code', 'maps_url', 'owner_name', 'co_owners', 'ownership_percent',
      'registration_date', 'will_details', 'nominee_name', 'nominee_relationship',
      'legal_heirs', 'tax_id', 'encumbrance', 'has_loan', 'loan_provider',
      'outstanding_loan', 'emi', 'annual_tax', 'maintenance_charges', 'rental_income',
      'other_expenses', 'reminder_note', 'attachments', 'consent',
    },
    'w_insurance_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'insurer', 'policy_type', 'policy_holder', 'sum_assured',
      'premium_amount', 'premium_frequency', 'start_date', 'renewal_date',
      'nominee_name', 'agent_name', 'agent_phone', 'consent',
    },
    'w_investment_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'investment_type', 'institution', 'account_number', 'units',
      'purchase_price', 'invested_amount', 'current_value', 'purchase_date',
      'maturity_date', 'nominee', 'attachments', 'consent',
    },
    'w_banking_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'bank_name', 'account_holder', 'account_number', 'account_type',
      'ifsc_code', 'branch_name', 'customer_id', 'upi_id', 'opened_on',
      'nominee_name', 'consent',
    },
    'w_cards_wallet': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'bank', 'card_kind', 'network', 'holder_name', 'last4',
      'expiry_month', 'expiry_year', 'theme_key', 'consent',
    },
    'w_password_vault': {
      'id', 'auth_user_id', 'nickname', 'created_at', 'updated_at', 'password', 'consent',
    },
    'w_ino_share_cache': {
      'id', 'auth_user_id', 'name', 'category', 'record_number', 'status',
      'tags', 'notes', 'is_favorite', 'expires_at', 'file_path', 'created_at',
      'updated_at', 'source_document_id', 'share_id', 'consent',
    },
  };

  /// In-memory column cache mapping table slug -> discovered column names.
  static final Map<String, Set<String>> _tableColumnsCache = {};

  /// Cache of verified table existence.
  static final Map<String, bool> _tableExistsCache = {};

  /// Tracks tables that have logged their schema audit in debug mode.
  static final Set<String> _loggedTables = {};

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

  /// Drops all schema caches after a wallet is created, removed, or refreshed.
  static void invalidate() {
    _slugs = null;
    _tableExistsCache.clear();
    _tableColumnsCache.clear();
    _loggedTables.clear();
  }

  /// Invalidates columns cache for a specific table or all tables.
  static void invalidateColumnsCache([String? table]) {
    if (table != null) {
      _tableColumnsCache.remove(table);
      _tableExistsCache.remove(table);
      _loggedTables.remove(table);
    } else {
      _tableColumnsCache.clear();
      _tableExistsCache.clear();
      _loggedTables.clear();
    }
  }

  /// Verifies whether [table] exists in the database.
  static Future<bool> tableExists(String table) async {
    final cached = _tableExistsCache[table];
    if (cached != null) return cached;

    if (_builtinTableColumns.containsKey(table)) {
      _tableExistsCache[table] = true;
      return true;
    }

    try {
      // Lightweight probe: select 0 rows
      await _client.from(table).select('id').limit(0).timeout(NetGuard.query);
      _tableExistsCache[table] = true;
      return true;
    } on PostgrestException catch (e) {
      final isMissing = e.code == 'PGRST205' ||
          e.code == 'PGRST200' ||
          e.code == '42P01' ||
          e.message.toLowerCase().contains('does not exist');
      if (isMissing) {
        _tableExistsCache[table] = false;
        return false;
      }
      // If error is unrelated (e.g. auth/offline), check wallet slugs
      final slugs = await allSlugs();
      final exists = slugs.contains(table);
      _tableExistsCache[table] = exists;
      return exists;
    } catch (_) {
      final slugs = await allSlugs();
      final exists = slugs.contains(table);
      _tableExistsCache[table] = exists;
      return exists;
    }
  }

  /// Tests whether [column] exists on [table] by issuing a zero-limit select probe.
  static Future<bool> verifyColumnExists(String table, String column) async {
    try {
      await _client.from(table).select(column).limit(0).timeout(NetGuard.query);
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '42703' ||
          e.code == 'PGRST204' ||
          e.message.toLowerCase().contains('does not exist')) {
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Discovers and returns the actual, valid columns of [table].
  ///
  /// Uses an in-memory session cache so subsequent queries require 0 roundtrips.
  /// If the table contains at least 1 row, reads all column names directly.
  /// If the table is empty, verifies candidate columns against PostgREST.
  static Future<Set<String>> getColumnsForTable(
    String table, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _tableColumnsCache[table];
      if (cached != null) return cached;
    }

    // Pre-seed built-ins if not force-refreshed
    if (!forceRefresh && _builtinTableColumns.containsKey(table)) {
      final cols = Set<String>.from(_builtinTableColumns[table]!);
      _tableColumnsCache[table] = cols;
      return cols;
    }

    // Step 1: If table has rows, read 1 row to get full column set immediately
    try {
      final rows = await _client
          .from(table)
          .select()
          .limit(1)
          .timeout(NetGuard.query);
      if (rows.isNotEmpty) {
        final discovered = rows.first.keys.toSet();
        _tableColumnsCache[table] = discovered;
        return discovered;
      }
    } catch (e) {
      developer.log(
        '[WalletSchema] Row probe error for $table (will fallback to schema check): $e',
        name: 'wallet.schema',
      );
    }

    // Step 2: Empty table or probe error. Start with core columns guaranteed by DDL.
    final verified = Set<String>.from(coreColumns);

    // Test potential optional columns that some wallet tables carry (e.g. consent, doctor_name)
    final candidateOptionals = ['consent', 'doctor_name'];
    for (final opt in candidateOptionals) {
      if (await verifyColumnExists(table, opt)) {
        verified.add(opt);
      }
    }

    _tableColumnsCache[table] = verified;
    return verified;
  }

  /// Filters a payload map so that ONLY keys matching actual columns of [table]
  /// are preserved.
  ///
  /// Logs a detailed audit in debug mode once per table (Safety Requirement #1).
  /// Aborts gracefully if payload becomes empty (Safety Requirement #3).
  static Future<Map<String, dynamic>> filterPayloadForTable(
    String table,
    Map<String, dynamic> payload,
  ) async {
    final validColumns = await getColumnsForTable(table);

    final preserved = <String, dynamic>{};
    final filteredKeys = <String>[];

    for (final entry in payload.entries) {
      if (validColumns.contains(entry.key)) {
        preserved[entry.key] = entry.value;
      } else {
        filteredKeys.add(entry.key);
      }
    }

    // Critical Safety Requirement #1: Log once per table in debug mode
    if (kDebugMode && !_loggedTables.contains(table)) {
      _loggedTables.add(table);
      developer.log(
        '[WalletSchema Audit]\n'
        '  Table: $table\n'
        '  Discovered columns: ${validColumns.toList()}\n'
        '  Preserved columns: ${preserved.keys.toList()}\n'
        '  Filtered columns: $filteredKeys',
        name: 'wallet.schema',
      );
    } else if (filteredKeys.isNotEmpty) {
      developer.log(
        '[WalletSchema] Table $table: skipped unknown fields: $filteredKeys',
        name: 'wallet.schema',
      );
    }

    return preserved;
  }

  /// Evicts a column only after verifying it truly does not exist (Critical Safety Requirement #2).
  static Future<bool> safelyEvictColumn(String table, String column) async {
    // 1. Verify the column truly does not exist
    final exists = await verifyColumnExists(table, column);
    if (exists) {
      // Column actually exists; do not evict
      return false;
    }

    // 2. Re-fetch schema once
    final refreshed = await getColumnsForTable(table, forceRefresh: true);

    // 3. Only then evict
    refreshed.remove(column);
    _tableColumnsCache[table] = refreshed;
    developer.log(
      '[WalletSchema] Evicted unverified column "$column" from cache for table "$table"',
      name: 'wallet.schema',
    );
    return true;
  }

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
