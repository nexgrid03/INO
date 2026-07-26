import 'package:flutter/material.dart';

/// Models backing the Banking Wallet's saved cards.
///
/// SECURITY: a card is stored as an *identifier*, never as a usable instrument.
/// Only the last four digits are ever captured or persisted - there is no field
/// for the full PAN, and no field for the CVV anywhere in this app. Nothing
/// here can be used to transact.

enum CardKind { debit, credit, prepaid, forex }

extension CardKindX on CardKind {
  String get label => switch (this) {
        CardKind.debit => 'Debit',
        CardKind.credit => 'Credit',
        CardKind.prepaid => 'Prepaid',
        CardKind.forex => 'Forex',
      };

  static CardKind fromName(String? name) => CardKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => CardKind.debit,
      );
}

enum CardNetwork { visa, mastercard, rupay, amex, discover, diners, other }

extension CardNetworkX on CardNetwork {
  String get label => switch (this) {
        CardNetwork.visa => 'VISA',
        CardNetwork.mastercard => 'Mastercard',
        CardNetwork.rupay => 'RuPay',
        CardNetwork.amex => 'Amex',
        CardNetwork.discover => 'Discover',
        CardNetwork.diners => 'Diners Club',
        CardNetwork.other => 'Other',
      };

  static CardNetwork fromName(String? name) => CardNetwork.values.firstWhere(
        (n) => n.name == name,
        orElse: () => CardNetwork.other,
      );
}

/// The face colours a card can wear. Deliberately a fixed set of two-stop
/// gradients in the app's existing colour families, so the wallet reads as one
/// designed stack rather than arbitrary user colours.
class CardSkin {
  const CardSkin(this.key, this.name, this.top, this.bottom);

  final String key;
  final String name;
  final Color top;
  final Color bottom;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [top, bottom],
      );
}

const List<CardSkin> kCardSkins = [
  CardSkin('ocean', 'Ocean', Color(0xFF3B9BE8), Color(0xFF2F6FD0)),
  CardSkin('midnight', 'Midnight', Color(0xFF1E2A44), Color(0xFF16233C)),
  CardSkin('emerald', 'Emerald', Color(0xFF3FBE86), Color(0xFF2E9E9B)),
  CardSkin('teal', 'Teal', Color(0xFF30ACB3), Color(0xFF1E7F92)),
  CardSkin('violet', 'Violet', Color(0xFF8B6BE2), Color(0xFF5F46B8)),
  CardSkin('sunset', 'Sunset', Color(0xFFF5804A), Color(0xFFE05563)),
  CardSkin('graphite', 'Graphite', Color(0xFF5A6675), Color(0xFF36404E)),
  CardSkin('gold', 'Gold', Color(0xFFE0A100), Color(0xFFB57B12)),
];

CardSkin cardSkinFor(String? key) {
  for (final t in kCardSkins) {
    if (t.key == key) return t;
  }
  return kCardSkins.first;
}

/// A saved card. [last4] is the ONLY part of the number that exists here.
class SavedCard {
  const SavedCard({
    required this.id,
    required this.name,
    required this.bank,
    required this.kind,
    required this.network,
    required this.holderName,
    required this.last4,
    required this.createdAt,
    required this.updatedAt,
    this.expiryMonth,
    this.expiryYear,
    this.themeKey = 'ocean',
    this.notes,
    this.isFavorite = false,
  });

  final String id;

  /// A label the user recognises, e.g. "Travel card".
  final String name;
  final String bank;
  final CardKind kind;
  final CardNetwork network;
  final String holderName;

  /// Exactly four digits. Never the full card number.
  final String last4;

  final int? expiryMonth; // 1..12
  final int? expiryYear; // four digits
  final String themeKey;
  final String? notes;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  CardSkin get theme => cardSkinFor(themeKey);

  /// "09 / 28" - blank when the user didn't record an expiry.
  String get expiryLabel {
    final m = expiryMonth;
    final y = expiryYear;
    if (m == null || y == null) return '--/--';
    return '${m.toString().padLeft(2, '0')} / ${(y % 100).toString().padLeft(2, '0')}';
  }

  /// The masked number rendered on the card face.
  String get maskedNumber => '•••• •••• •••• $last4';

  /// True once the recorded expiry month has passed.
  bool get isExpired {
    final m = expiryMonth;
    final y = expiryYear;
    if (m == null || y == null) return false;
    final now = DateTime.now();
    // A card is valid through the last day of its expiry month.
    final endOfMonth = DateTime(y, m + 1, 0);
    return endOfMonth.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// True when the card expires within the next 60 days.
  bool get isExpiringSoon {
    final m = expiryMonth;
    final y = expiryYear;
    if (m == null || y == null || isExpired) return false;
    final endOfMonth = DateTime(y, m + 1, 0);
    return endOfMonth.difference(DateTime.now()).inDays <= 60;
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        bank.toLowerCase().contains(q) ||
        holderName.toLowerCase().contains(q) ||
        network.label.toLowerCase().contains(q) ||
        kind.label.toLowerCase().contains(q) ||
        last4.contains(q);
  }

  SavedCard copyWith({
    String? name,
    String? bank,
    CardKind? kind,
    CardNetwork? network,
    String? holderName,
    String? last4,
    int? expiryMonth,
    int? expiryYear,
    String? themeKey,
    String? notes,
    bool? isFavorite,
    DateTime? updatedAt,
  }) {
    return SavedCard(
      id: id,
      name: name ?? this.name,
      bank: bank ?? this.bank,
      kind: kind ?? this.kind,
      network: network ?? this.network,
      holderName: holderName ?? this.holderName,
      last4: last4 ?? this.last4,
      expiryMonth: expiryMonth ?? this.expiryMonth,
      expiryYear: expiryYear ?? this.expiryYear,
      themeKey: themeKey ?? this.themeKey,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bank': bank,
        'kind': kind.name,
        'network': network.name,
        'holderName': holderName,
        'last4': last4,
        'expiryMonth': expiryMonth,
        'expiryYear': expiryYear,
        'themeKey': themeKey,
        'notes': notes,
        'isFavorite': isFavorite,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SavedCard.fromJson(Map<String, dynamic> j) {
    // Defensive: an older/corrupt entry must never surface more than 4 digits.
    final raw = (j['last4'] as String?) ?? '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return SavedCard(
      id: j['id']?.toString() ?? '',
      name: (j['name'] as String?) ?? 'Card',
      bank: (j['bank'] as String?) ?? '',
      kind: CardKindX.fromName(j['kind'] as String?),
      network: CardNetworkX.fromName(j['network'] as String?),
      holderName: (j['holderName'] as String?) ?? '',
      last4: digits.length <= 4
          ? digits.padLeft(digits.length, '0')
          : digits.substring(digits.length - 4),
      expiryMonth: (j['expiryMonth'] as num?)?.toInt(),
      expiryYear: (j['expiryYear'] as num?)?.toInt(),
      themeKey: (j['themeKey'] as String?) ?? 'ocean',
      notes: j['notes'] as String?,
      isFavorite: (j['isFavorite'] as bool?) ?? false,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
