import 'dart:math';

import '../models/password_models.dart';
import 'local_collection_store.dart';

/// The Password Vault's credentials (device-local, per account).
///
/// SECURITY NOTE - read before extending this:
/// entries never leave the device and are never uploaded, and the vault screen
/// is gated behind the app's biometric [VaultGuard]. They are, however, stored
/// in `shared_preferences`, which is app-private but **not encrypted at rest**;
/// a rooted/jailbroken device or a full device backup could read it. Moving
/// this to the platform keystore (`flutter_secure_storage`) is the intended
/// hardening step and only [persist]/[decode] would change.
class PasswordStore extends LocalCollectionStore<PasswordEntry> {
  PasswordStore._();
  static final PasswordStore instance = PasswordStore._();

  @override
  String get storageKey => 'ino_passwords';

  @override
  Map<String, dynamic> encode(PasswordEntry item) => item.toJson();

  @override
  PasswordEntry decode(Map<String, dynamic> json) =>
      PasswordEntry.fromJson(json);

  @override
  String idOf(PasswordEntry item) => item.id;

  /// Favourites first, then A–Z by title (a password manager reads best
  /// alphabetically - "recent" is available as an explicit filter instead).
  List<PasswordEntry> get sorted {
    final list = [...items]..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return List.unmodifiable(list);
  }

  /// The five most recently added credentials, newest first.
  List<PasswordEntry> get recentlyAdded {
    final list = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(5).toList();
  }

  List<PasswordEntry> get favorites =>
      items.where((e) => e.isFavorite).toList();

  /// Categories the user actually has credentials in, in enum order.
  List<PasswordCategory> get usedCategories {
    final used = items.map((e) => e.category).toSet();
    return [
      for (final c in PasswordCategory.values)
        if (used.contains(c)) c,
    ];
  }

  int countIn(PasswordCategory category) =>
      items.where((e) => e.category == category).length;

  /// How many entries score below [PasswordStrength.good] - the vault's own
  /// health signal.
  int get weakCount => items
      .where((e) =>
          e.strength == PasswordStrength.weak ||
          e.strength == PasswordStrength.fair)
      .length;

  /// Passwords reused across more than one entry (compared exactly). Returns
  /// the number of entries involved, which is what the health card reports.
  int get reusedCount {
    final counts = <String, int>{};
    for (final e in items) {
      if (e.password.isEmpty) continue;
      counts[e.password] = (counts[e.password] ?? 0) + 1;
    }
    return counts.entries
        .where((e) => e.value > 1)
        .fold(0, (s, e) => s + e.value);
  }

  Future<void> toggleFavorite(String id) async {
    final e = byId(id);
    if (e == null) return;
    await update(e.copyWith(isFavorite: !e.isFavorite));
  }
}

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

/// Options for [generatePassword].
class PasswordRecipe {
  const PasswordRecipe({
    this.length = 16,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
  });

  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool digits;
  final bool symbols;

  PasswordRecipe copyWith({
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
  }) =>
      PasswordRecipe(
        length: length ?? this.length,
        lowercase: lowercase ?? this.lowercase,
        uppercase: uppercase ?? this.uppercase,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
      );

  /// At least one class must stay on - the UI enforces this too.
  bool get isValid => lowercase || uppercase || digits || symbols;
}

const _lower = 'abcdefghijkmnopqrstuvwxyz'; // no 'l'
const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no 'I', 'O'
const _digits = '23456789'; // no '0', '1'
const _symbols = '!@#\$%^&*()-_=+[]{};:,.?';

/// A cryptographically-seeded random password matching [recipe].
///
/// Uses `Random.secure()` (the platform CSPRNG), guarantees at least one
/// character from every enabled class, and omits look-alike characters
/// (0/O, 1/l/I) so a generated password can still be typed by hand.
String generatePassword([PasswordRecipe recipe = const PasswordRecipe()]) {
  final pools = <String>[
    if (recipe.lowercase) _lower,
    if (recipe.uppercase) _upper,
    if (recipe.digits) _digits,
    if (recipe.symbols) _symbols,
  ];
  if (pools.isEmpty) return '';

  final rng = Random.secure();
  final length = recipe.length.clamp(pools.length, 64);
  final chars = <String>[
    // One from each enabled class first, so the recipe is always honoured.
    for (final pool in pools) pool[rng.nextInt(pool.length)],
  ];
  final all = pools.join();
  while (chars.length < length) {
    chars.add(all[rng.nextInt(all.length)]);
  }
  chars.shuffle(rng); // the guaranteed characters must not sit in a fixed order
  return chars.join();
}
