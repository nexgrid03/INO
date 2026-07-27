import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  0xFF2FB6A6, // teal
  0xFF4383EA, // blue
  0xFF9B6DE0, // purple
  0xFFF5704A, // coral
  0xFF37C08A, // green
  0xFFF2B33D, // amber
  0xFF4E7FE0, // indigo-blue
  0xFF30ACB3, // brand teal
  0xFFE0699B, // rose
  0xFF64748B, // slate
];

const String _kDefaultIconKey = 'folder';
const int _kDefaultAccent = 0xFF2FB6A6;

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
  });

  final String name;
  final String iconKey;
  final int colorValue;

  IconData get icon => walletIconFor(iconKey);
  Color get color => Color(colorValue);

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

  Map<String, dynamic> toJson() =>
      {'name': name, 'icon': iconKey, 'color': colorValue};

  factory CustomWallet.fromJson(Map<String, dynamic> j) => CustomWallet(
        name: (j['name'] as String).trim(),
        iconKey: j['icon'] as String? ?? _kDefaultIconKey,
        colorValue: (j['color'] as num?)?.toInt() ?? _kDefaultAccent,
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

  /// Hydrates custom wallets from disk. Safe to call once at startup.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
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
    await WalletTables.createCustomWallet(
      wallet.name,
      iconKey: wallet.iconKey,
      colorValue: wallet.colorValue,
    );
    _wallets.add(wallet);
    notifyListeners();
    await _persist();
    return wallet;
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
      final p = await SharedPreferences.getInstance();
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
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {
      // Best-effort.
    }
  }
}
