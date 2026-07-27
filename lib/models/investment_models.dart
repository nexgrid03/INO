import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Models backing the Investment Wallet - a portfolio register covering every
/// instrument the app supports, from equities to PPF.
///
/// Values are plain doubles in the user's active currency. Returns are always
/// *derived* from invested vs current value - never stored - so a holding can
/// never display a profit that contradicts its own numbers.

enum InvestmentType {
  stocks,
  mutualFunds,
  etf,
  bonds,
  fixedDeposit,
  gold,
  crypto,
  ppf,
  nps,
  sip,
  realEstate,
  other,
}

extension InvestmentTypeX on InvestmentType {
  String get label => switch (this) {
        InvestmentType.stocks => 'Stocks',
        InvestmentType.mutualFunds => 'Mutual Funds',
        InvestmentType.etf => 'ETFs',
        InvestmentType.bonds => 'Bonds',
        InvestmentType.fixedDeposit => 'Fixed Deposits',
        InvestmentType.gold => 'Gold',
        InvestmentType.crypto => 'Crypto',
        InvestmentType.ppf => 'PPF',
        InvestmentType.nps => 'NPS',
        InvestmentType.sip => 'SIPs',
        InvestmentType.realEstate => 'Real Estate',
        InvestmentType.other => 'Custom',
      };

  /// Short label for chips and the allocation legend.
  String get shortLabel => switch (this) {
        InvestmentType.mutualFunds => 'Mutual Funds',
        InvestmentType.fixedDeposit => 'FD',
        InvestmentType.realEstate => 'Real Estate',
        _ => label,
      };

  IconData get icon => switch (this) {
        InvestmentType.stocks => Icons.show_chart_rounded,
        InvestmentType.mutualFunds => Icons.pie_chart_rounded,
        InvestmentType.etf => Icons.stacked_line_chart_rounded,
        InvestmentType.bonds => Icons.receipt_long_rounded,
        InvestmentType.fixedDeposit => Icons.savings_rounded,
        InvestmentType.gold => Icons.workspace_premium_rounded,
        InvestmentType.crypto => Icons.currency_bitcoin_rounded,
        InvestmentType.ppf => Icons.account_balance_rounded,
        InvestmentType.nps => Icons.elderly_rounded,
        InvestmentType.sip => Icons.autorenew_rounded,
        InvestmentType.realEstate => Icons.home_work_rounded,
        InvestmentType.other => Icons.category_rounded,
      };

  /// Allocation colour. Teal-family first (the brand), then the supporting
  /// accents already used across the app - no new palette is introduced.
  Color get color => switch (this) {
        InvestmentType.stocks => const Color(0xFF4383EA),
        InvestmentType.mutualFunds => AppColors.primaryGreen,
        InvestmentType.etf => const Color(0xFF55C2C8),
        InvestmentType.bonds => const Color(0xFF9B6DE0),
        InvestmentType.fixedDeposit => const Color(0xFF64748B),
        InvestmentType.gold => AppColors.gold,
        InvestmentType.crypto => const Color(0xFFF5704A),
        InvestmentType.ppf => const Color(0xFF37C08A),
        InvestmentType.nps => const Color(0xFF0891B2),
        InvestmentType.sip => const Color(0xFF7FD3D8),
        InvestmentType.realEstate => const Color(0xFFB45309),
        InvestmentType.other => const Color(0xFF94A3B8),
      };

  /// Whether a maturity date is meaningful for this instrument.
  bool get hasMaturity => switch (this) {
        InvestmentType.fixedDeposit ||
        InvestmentType.bonds ||
        InvestmentType.ppf ||
        InvestmentType.nps =>
          true,
        _ => false,
      };

  static InvestmentType fromName(String? name) =>
      InvestmentType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => InvestmentType.other,
      );
}

/// A file attached to a holding (statement, certificate, contract note).
class InvestmentAttachment {
  const InvestmentAttachment({
    required this.id,
    required this.name,
    this.path,
    this.linkedDocumentId,
  });

  final String id;
  final String name;
  final String? path;
  final String? linkedDocumentId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (path != null) 'path': path,
        if (linkedDocumentId != null) 'documentId': linkedDocumentId,
      };

  factory InvestmentAttachment.fromJson(Map<String, dynamic> j) =>
      InvestmentAttachment(
        id: j['id']?.toString() ?? '',
        name: (j['name'] as String?) ?? '',
        path: j['path'] as String?,
        linkedDocumentId: j['documentId'] as String?,
      );
}

/// One holding in the portfolio.
class Investment {
  const Investment({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.accountNumber,
    this.units,
    this.purchasePrice,
    this.investedAmount,
    this.currentValue,
    this.purchaseDate,
    this.maturityDate,
    this.nominee,
    this.notes,
    this.attachments = const [],
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final InvestmentType type;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String? institution; // broker / AMC / bank
  /// Stored as entered; always displayed masked (see [maskedAccount]).
  final String? accountNumber;
  final double? units;
  final double? purchasePrice; // per unit
  final double? investedAmount; // total cost
  final double? currentValue;
  final DateTime? purchaseDate;
  final DateTime? maturityDate;
  final String? nominee;
  final String? notes;
  final List<InvestmentAttachment> attachments;
  final bool isFavorite;

  /// What was put in: the explicit invested amount, else units × unit price.
  double get invested {
    final a = investedAmount;
    if (a != null) return a;
    final u = units;
    final p = purchasePrice;
    if (u != null && p != null) return u * p;
    return 0;
  }

  /// What it's worth now (falls back to the invested amount when the user
  /// hasn't updated a valuation yet - never an invented gain).
  double get value => currentValue ?? invested;

  /// Absolute profit/loss.
  double get profit => value - invested;

  /// Profit as a fraction of the amount invested, or null when nothing was
  /// invested (an undefined return, not a zero one).
  double? get returnPercent {
    final base = invested;
    if (base <= 0) return null;
    return profit / base;
  }

  bool get isUp => profit >= 0;

  /// Only ever the last 4 characters - the rest is never rendered.
  String? get maskedAccount {
    final a = accountNumber?.trim();
    if (a == null || a.isEmpty) return null;
    final tail = a.length <= 4 ? a : a.substring(a.length - 4);
    return '•••• $tail';
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        type.label.toLowerCase().contains(q) ||
        (institution ?? '').toLowerCase().contains(q) ||
        (nominee ?? '').toLowerCase().contains(q) ||
        (notes ?? '').toLowerCase().contains(q);
  }

  Investment copyWith({
    /// Only set when adopting the database's uuid after the record is first
    /// uploaded (see LocalCollectionStore.withId). Never change an id otherwise.
    String? id,
    String? name,
    InvestmentType? type,
    DateTime? updatedAt,
    String? institution,
    String? accountNumber,
    double? units,
    double? purchasePrice,
    double? investedAmount,
    double? currentValue,
    DateTime? purchaseDate,
    DateTime? maturityDate,
    String? nominee,
    String? notes,
    List<InvestmentAttachment>? attachments,
    bool? isFavorite,
  }) {
    return Investment(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      institution: institution ?? this.institution,
      accountNumber: accountNumber ?? this.accountNumber,
      units: units ?? this.units,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      investedAmount: investedAmount ?? this.investedAmount,
      currentValue: currentValue ?? this.currentValue,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      maturityDate: maturityDate ?? this.maturityDate,
      nominee: nominee ?? this.nominee,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'institution': institution,
        'accountNumber': accountNumber,
        'units': units,
        'purchasePrice': purchasePrice,
        'investedAmount': investedAmount,
        'currentValue': currentValue,
        'purchaseDate': purchaseDate?.toIso8601String(),
        'maturityDate': maturityDate?.toIso8601String(),
        'nominee': nominee,
        'notes': notes,
        'attachments': [for (final a in attachments) a.toJson()],
        'isFavorite': isFavorite,
      };

  factory Investment.fromJson(Map<String, dynamic> j) {
    double? num_(Object? v) => (v as num?)?.toDouble();
    DateTime? date(Object? v) => DateTime.tryParse(v as String? ?? '');
    return Investment(
      id: j['id']?.toString() ?? '',
      name: (j['name'] as String?) ?? 'Investment',
      type: InvestmentTypeX.fromName(j['type'] as String?),
      createdAt: date(j['createdAt']) ?? DateTime.now(),
      updatedAt: date(j['updatedAt']) ?? DateTime.now(),
      institution: j['institution'] as String?,
      accountNumber: j['accountNumber'] as String?,
      units: num_(j['units']),
      purchasePrice: num_(j['purchasePrice']),
      investedAmount: num_(j['investedAmount']),
      currentValue: num_(j['currentValue']),
      purchaseDate: date(j['purchaseDate']),
      maturityDate: date(j['maturityDate']),
      nominee: j['nominee'] as String?,
      notes: j['notes'] as String?,
      attachments: [
        for (final a in (j['attachments'] as List?) ?? const [])
          InvestmentAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      isFavorite: (j['isFavorite'] as bool?) ?? false,
    );
  }
}

/// One slice of the allocation donut - a type and what it's worth.
class InvestmentSlice {
  const InvestmentSlice({
    required this.type,
    required this.value,
    required this.share,
  });

  final InvestmentType type;
  final double value;

  /// 0..1 share of the portfolio.
  final double share;
}
