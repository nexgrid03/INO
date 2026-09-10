import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../core/storage/shared_prefs_cache.dart';
import '../models/wallet_models.dart';
import '../repositories/wallet_tables.dart';
import 'category_store.dart';

/// The icon catalogue offered by the Create Wallet sheet.
///
/// Reuses the category catalogue on purpose: both are fixed lists of *const*
/// [IconData]s (never rebuilt from a raw code point) so Flutter can still
/// tree-shake the icon font in release builds, and the two pickers stay
/// visually consistent.
const List<CategoryIconOption> kWalletIcons = kCategoryIcons;

/// Resolves a persisted wallet icon [key] back to its const [IconData].
IconData walletIconFor(String key) => categoryIconFor(key);

/// Accent swatches offered by the Create Wallet sheet, as ARGB ints. These are
/// the same family of light, premium accents the built-in wallet cards wear
/// (see `WalletGrid._accents`) so a custom wallet never looks bolted on.
const List<int> kWalletAccentValues = [
  0xFF14B8A6, // teal
  0xFF098F90, // aqua brand
  0xFF9B6DE0, // purple
  0xFFF5704A, // coral
  0xFF10B981, // green
  0xFFF2B33D, // amber
  0xFF2BA8A9, // aqua secondary
  0xFF0D9488, // deep teal
  0xFFE0699B, // rose
  0xFF64748B, // slate
];

const String _kDefaultIconKey = 'folder';
const int _kDefaultAccent = 0xFF14B8A6;

/// A user-created wallet - a vault bucket alongside the eight built-in ones.
///
/// Identified case-insensitively by [name], which is exactly what the
/// `documents.wallet` column stores, so a custom wallet is usable everywhere a
/// document references a wallet: the add-document picker, the OCR review
/// picker, the move-document sheet and the wallet filters.
class CustomWallet {
  const CustomWallet({
    required this.name,
    required this.iconKey,
    required this.colorValue,
    this.slug,
  });

  final String name;
  final String iconKey;
  final int colorValue;
  final String? slug;

  IconData get icon => walletIconFor(iconKey);
  Color get color => Color(colorValue);

  /// Resolves the effective table slug for this wallet, ensuring existing
  /// documents remain attached even after a rename.
  String get effectiveSlug =>
      (slug != null && slug!.isNotEmpty) ? slug! : WalletTables.defaultSlugFor(name);

  /// Case-insensitive identity, used for de-dup and matching document rows.
  String get id => name.trim().toLowerCase();

  /// The read model the Wallet Hub grid and detail screen consume. The record
  /// count is filled in later by `SupabaseWalletRepository.load()`.
  WalletCategory toCategory() => WalletCategory(
        name: name,
        icon: icon,
        contents: const [],
        metric: '0',
        metricLabel: 'documents',
        gradient: [color, Color.lerp(color, Colors.white, 0.32)!],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'icon': iconKey,
        'color': colorValue,
        if (slug != null) 'slug': slug,
      };

  factory CustomWallet.fromJson(Map<String, dynamic> j) => CustomWallet(
        name: (j['name'] as String).trim(),
        iconKey: j['icon'] as String? ?? _kDefaultIconKey,
        colorValue: (j['color'] as num?)?.toInt() ?? _kDefaultAccent,
        slug: j['slug'] as String?,
      );
}

/// Persistent store of user-created wallets. Backed by `shared_preferences` so
/// custom wallets survive a restart, and a [ChangeNotifier] so the hub grid and
/// every wallet picker rebuild the instant one is added or removed.
///
/// Mirrors [CategoryStore] deliberately - same load / add / remove / clear
/// contract, same never-throw behaviour when the plugin is absent (tests).
class CustomWalletStore extends ChangeNotifier {
  CustomWalletStore._();
  static final CustomWalletStore instance = CustomWalletStore._();

  static const String _key = 'custom_wallets';

  /// A custom wallet name may not collide with a built-in one. Kept here (not
  /// imported from the repository) so the store has no dependency on it.
  static const List<String> builtInNames = [
    'Identity Wallet',
    'Document Wallet',
    'Property Wallet',
    'Insurance Wallet',
    'Health Wallet',
    'Investment Wallet',
    'Banking Wallet',
    'Password Vault',
  ];

  final List<CustomWallet> _wallets = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  String? _currentUid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Hydrates custom wallets from disk, and reconciles with Supabase when signed in.
  Future<void> load() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final raw = p.getStringList(_key) ?? const [];
      _wallets
        ..clear()
        ..addAll(
          raw.map((s) =>
              CustomWallet.fromJson(jsonDecode(s) as Map<String, dynamic>)),
        );
    } catch (_) {
      // No plugin (tests) / corrupt data → treat as empty, never throw.
    }
    _loaded = true;
    notifyListeners();

    // Reconcile with Supabase for the signed-in user (reinstall / cross-device restore)
    final uid = _currentUid();
    if (uid != null) {
      await syncFromRemote(uid);
    }
  }

  /// Restores any custom wallets created by [userId] that are missing from local storage.
  Future<void> syncFromRemote(String userId) async {
    try {
      final rows = await Supabase.instance.client
          .from('wallets')
          .select('slug, label, icon_key, color_value')
          .eq('kind', 'custom')
          .eq('created_by', userId)
          .timeout(NetGuard.query);

      var changed = false;
      for (final r in rows) {
        final label = (r['label'] as String?)?.trim();
        final slug = (r['slug'] as String?)?.trim();
        if (label == null || label.isEmpty) continue;
        if (byName(label) == null && (slug == null || bySlug(slug) == null)) {
          _wallets.add(
            CustomWallet(
              name: label,
              iconKey: (r['icon_key'] as String?) ?? _kDefaultIconKey,
              colorValue:
                  (r['color_value'] as num?)?.toInt() ?? _kDefaultAccent,
              slug: slug,
            ),
          );
          changed = true;
        }
      }

      if (changed) {
        await _persist();
        notifyListeners();
      }
    } catch (_) {
      // Best-effort; network/offline errors keep existing local cache intact.
    }
  }

  /// The user's wallets, in creation order.
  List<CustomWallet> get all => List.unmodifiable(_wallets);

  bool get isEmpty => _wallets.isEmpty;

  /// The custom wallets as hub read models, ready to append after the built-ins.
  List<WalletCategory> get categories => [
        for (final w in _wallets) w.toCategory(),
      ];

  CustomWallet? byName(String name) {
    final id = name.trim().toLowerCase();
    for (final w in _wallets) {
      if (w.id == id) return w;
    }
    return null;
  }

  CustomWallet? bySlug(String slug) {
    for (final w in _wallets) {
      if (w.slug == slug) return w;
    }
    return null;
  }

  /// Resolves the table slug for a wallet name, if known.
  String? slugFor(String name) => byName(name)?.effectiveSlug;

  /// True when [name] is one of the user's own wallets (so it can be deleted).
  bool isCustom(String name) => byName(name) != null;

  /// True when [name] is already taken - by a built-in wallet or a custom one.
  bool exists(String name) {
    final id = name.trim().toLowerCase();
    for (final n in builtInNames) {
      if (n.toLowerCase() == id) return true;
    }
    return byName(name) != null;
  }

  /// Adds a wallet. If one with the same (case-insensitive) name already
  /// exists, returns that one instead of duplicating.
  ///
  /// Provisions the wallet's TABLE first and lets a failure propagate: since
  /// every wallet owns a table, a wallet without one looks fine in the grid but
  /// fails on the first document saved into it. Better to refuse up front than
  /// to hand back a wallet that cannot hold anything.
  Future<CustomWallet> add(CustomWallet wallet) async {
    final existing = byName(wallet.name);
    if (existing != null) return existing;
    String? slug = wallet.slug;
    try {
      slug ??= await WalletTables.createCustomWallet(
        wallet.name,
        iconKey: wallet.iconKey,
        colorValue: wallet.colorValue,
      );
    } on AssertionError {
      // Supabase uninitialized (unit tests) -> fallback to default slug
      slug ??= WalletTables.defaultSlugFor(wallet.name);
    }
    final walletWithSlug = CustomWallet(
      name: wallet.name,
      iconKey: wallet.iconKey,
      colorValue: wallet.colorValue,
      slug: slug,
    );
    _wallets.add(walletWithSlug);
    notifyListeners();
    await _persist();
    return walletWithSlug;
  }

  /// Renames an existing custom wallet.
  ///
  /// Keeps the wallet's icon, accent colour, table slug, and order in
  /// the catalogue intact, updating ONLY the display name.
  Future<CustomWallet> rename(String oldName, String newName) async {
    final trimmedNew = newName.trim();
    if (trimmedNew.isEmpty) {
      throw ArgumentError('Wallet name cannot be empty');
    }
    final existing = byName(oldName);
    if (existing == null) {
      throw StateError('Wallet "$oldName" not found');
    }
    if (existing.name == trimmedNew) {
      return existing;
    }

    // Validation: ensure new name does not collide with built-in or another custom wallet
    final duplicate = byName(trimmedNew);
    if (duplicate != null && duplicate.id != existing.id) {
      throw StateError('A wallet named "$trimmedNew" already exists');
    }
    for (final builtIn in builtInNames) {
      if (builtIn.toLowerCase() == trimmedNew.toLowerCase()) {
        throw StateError('Cannot use built-in wallet name "$trimmedNew"');
      }
    }

    final index = _wallets.indexOf(existing);
    final updated = CustomWallet(
      name: trimmedNew,
      iconKey: existing.iconKey,
      colorValue: existing.colorValue,
      slug: existing.effectiveSlug,
    );

    if (index != -1) {
      _wallets[index] = updated;
    } else {
      _wallets.add(updated);
    }

    notifyListeners();
    await _persist();

    // Best-effort update to Supabase registry for signed-in user
    try {
      final uid = _currentUid();
      if (uid != null && updated.slug != null) {
        await Supabase.instance.client
            .from('wallets')
            .update({'label': trimmedNew})
            .eq('slug', updated.slug!)
            .eq('created_by', uid)
            .timeout(NetGuard.mutation);
      }
    } catch (_) {
      // Best-effort; local persistence preserves the rename regardless.
    }

    return updated;
  }

  /// Removes a custom wallet by name. Documents filed under it are NOT touched
  /// - they keep their `wallet` value and resurface if the wallet is re-created,
  /// and remain findable through global search either way.
  Future<void> remove(String name) async {
    final id = name.trim().toLowerCase();
    final before = _wallets.length;
    _wallets.removeWhere((w) => w.id == id);
    if (_wallets.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setStringList(
          _key, [for (final w in _wallets) jsonEncode(w.toJson())]);
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  /// Drops the user's wallets (in-memory + persisted) so the next account starts
  /// from just the built-ins. Custom wallets are user-created content stored
  /// under a GLOBAL key, so they MUST be cleared on sign-out ([SessionReset]).
  Future<void> clear() async {
    _wallets.clear();
    _loaded = false;
    notifyListeners();
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.remove(_key);
    } catch (_) {
      // Best-effort.
    }
  }
}
