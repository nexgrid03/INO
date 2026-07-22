import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A selectable icon for a document category.
///
/// Kept as a fixed catalogue of *const* [IconData]s — never reconstructed from a
/// raw code point — so Flutter can still tree-shake the icon font in release
/// builds. We persist the stable [key], and resolve back to the const icon.
class CategoryIconOption {
  const CategoryIconOption(this.key, this.icon);
  final String key;
  final IconData icon;
}

/// The icon catalogue offered by the category picker.
const List<CategoryIconOption> kCategoryIcons = [
  CategoryIconOption('badge', Icons.badge_rounded),
  CategoryIconOption('account_balance', Icons.account_balance_rounded),
  CategoryIconOption('gavel', Icons.gavel_rounded),
  CategoryIconOption('health', Icons.favorite_rounded),
  CategoryIconOption('home', Icons.home_work_rounded),
  CategoryIconOption('person', Icons.person_rounded),
  CategoryIconOption('folder', Icons.folder_rounded),
  CategoryIconOption('school', Icons.school_rounded),
  CategoryIconOption('work', Icons.work_rounded),
  CategoryIconOption('receipt', Icons.receipt_long_rounded),
  CategoryIconOption('shield', Icons.shield_rounded),
  CategoryIconOption('car', Icons.directions_car_rounded),
  CategoryIconOption('card', Icons.credit_card_rounded),
  CategoryIconOption('star', Icons.star_rounded),
  CategoryIconOption('description', Icons.description_rounded),
  CategoryIconOption('flight', Icons.flight_rounded),
];

/// Colour swatches offered by the category picker, as ARGB ints (const, so we
/// build [Color] from them without touching the deprecated `Color.value`).
const List<int> kCategoryColorValues = [
  0xFF16A34A, // green
  0xFF0A9186, // teal
  0xFF2563EB, // blue
  0xFF7C3AED, // violet
  0xFFDB2777, // pink
  0xFFF59E0B, // amber
  0xFFEA580C, // orange
  0xFFDC2626, // red
  0xFF0891B2, // cyan
  0xFF475569, // slate
];

const String _kDefaultIconKey = 'folder';
const int _kDefaultColor = 0xFF16A34A;

/// Resolves a persisted icon [key] back to its const [IconData].
IconData categoryIconFor(String key) {
  for (final o in kCategoryIcons) {
    if (o.key == key) return o.icon;
  }
  return Icons.folder_rounded;
}

/// A document category — either one of the built-in defaults or a user-created
/// custom one. Identified case-insensitively by [name] (which is what the
/// `documents.category` column stores).
class DocumentCategory {
  const DocumentCategory({
    required this.name,
    required this.iconKey,
    required this.colorValue,
    this.builtIn = false,
  });

  final String name;
  final String iconKey;
  final int colorValue;
  final bool builtIn;

  IconData get icon => categoryIconFor(iconKey);
  Color get color => Color(colorValue);

  /// Case-insensitive identity, used for de-dup and matching document rows.
  String get id => name.trim().toLowerCase();

  Map<String, dynamic> toJson() =>
      {'name': name, 'icon': iconKey, 'color': colorValue};

  factory DocumentCategory.fromJson(Map<String, dynamic> j) => DocumentCategory(
        name: (j['name'] as String).trim(),
        iconKey: j['icon'] as String? ?? _kDefaultIconKey,
        colorValue: (j['color'] as num?)?.toInt() ?? _kDefaultColor,
      );
}

/// Persistent store of document categories: the built-in set plus any custom
/// categories the user creates. Backed by `shared_preferences` so custom
/// categories survive an app restart, and a [ChangeNotifier] so pickers and
/// filter chips rebuild the instant one is added.
///
/// Categories are keyed by name (the same string stored on each document row),
/// so a custom category is immediately usable everywhere documents reference a
/// category — the add-document picker, the OCR review picker and wallet filters.
class CategoryStore extends ChangeNotifier {
  CategoryStore._();
  static final CategoryStore instance = CategoryStore._();

  static const String _key = 'custom_document_categories';

  /// Always-present defaults (not deletable). Order is intentional.
  static const List<DocumentCategory> builtIns = [
    DocumentCategory(
        name: 'Identity',
        iconKey: 'badge',
        colorValue: 0xFF2563EB,
        builtIn: true),
    DocumentCategory(
        name: 'Financial',
        iconKey: 'account_balance',
        colorValue: 0xFF16A34A,
        builtIn: true),
    DocumentCategory(
        name: 'Legal', iconKey: 'gavel', colorValue: 0xFF7C3AED, builtIn: true),
    DocumentCategory(
        name: 'Medical',
        iconKey: 'health',
        colorValue: 0xFFDC2626,
        builtIn: true),
    DocumentCategory(
        name: 'Property',
        iconKey: 'home',
        colorValue: 0xFFEA580C,
        builtIn: true),
    DocumentCategory(
        name: 'Personal',
        iconKey: 'person',
        colorValue: 0xFF0A9186,
        builtIn: true),
    DocumentCategory(
        name: 'Other',
        iconKey: 'folder',
        colorValue: 0xFF475569,
        builtIn: true),
  ];

  final List<DocumentCategory> _custom = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Hydrates custom categories from disk. Safe to call once at startup; the
  /// built-ins are always available even before this runs (e.g. in tests).
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_key) ?? const [];
      _custom
        ..clear()
        ..addAll(
          raw.map((s) => DocumentCategory.fromJson(
              jsonDecode(s) as Map<String, dynamic>)),
        );
    } catch (_) {
      // No plugin (tests) / corrupt data → treat as empty, never throw.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Built-ins first, then custom categories in creation order.
  List<DocumentCategory> get all => [...builtIns, ..._custom];

  List<DocumentCategory> get custom => List.unmodifiable(_custom);

  List<String> get names => [for (final c in all) c.name];

  DocumentCategory? byName(String name) {
    final id = name.trim().toLowerCase();
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool exists(String name) => byName(name) != null;

  /// Adds a custom category. If one with the same (case-insensitive) name
  /// already exists, returns that existing category instead of duplicating.
  Future<DocumentCategory> add(DocumentCategory category) async {
    final existing = byName(category.name);
    if (existing != null) return existing;
    _custom.add(category);
    notifyListeners();
    await _persist();
    return category;
  }

  /// Removes a custom category by name (built-ins are ignored).
  Future<void> remove(String name) async {
    final id = name.trim().toLowerCase();
    final before = _custom.length;
    _custom.removeWhere((c) => c.id == id);
    if (_custom.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
          _key, [for (final c in _custom) jsonEncode(c.toJson())]);
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  /// Drops the user's custom categories (in-memory + persisted) so the next
  /// account starts from just the built-ins. Custom categories are user-created
  /// content stored under a GLOBAL key, so they MUST be cleared on sign-out.
  /// Called from [SessionReset]. Built-ins are unaffected (they're const).
  Future<void> clear() async {
    _custom.clear();
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
