import '../models/investment_models.dart';
import 'local_collection_store.dart';

/// The Investment Wallet's portfolio, synced to `w_investment_wallet`.
///
/// Every aggregate here is derived from the holdings themselves - the store
/// never persists a total, so a figure on the dashboard can't drift out of sync
/// with the rows beneath it.
///
/// `shared_preferences` remains the offline cache; Supabase is the source of
/// truth. See [LocalCollectionStore] for the sync and one-time upload of
/// records created before this store synced.
class InvestmentStore extends LocalCollectionStore<Investment> {
  InvestmentStore._();
  static final InvestmentStore instance = InvestmentStore._();

  @override
  String get storageKey => 'ino_investments';

  @override
  Map<String, dynamic> encode(Investment item) => item.toJson();

  @override
  Investment decode(Map<String, dynamic> json) => Investment.fromJson(json);

  @override
  String idOf(Investment item) => item.id;

  // ---- Supabase sync --------------------------------------------------------

  @override
  String get syncTable => 'w_investment_wallet';

  @override
  Investment withId(Investment item, String id) => item.copyWith(id: id);

  /// Maps an [Investment] onto its `w_investment_wallet` columns. `name`,
  /// `notes` and `is_favorite` reuse the base columns shared by every wallet
  /// table; the rest are the investment-specific ones.
  @override
  Future<Map<String, dynamic>> toRow(Investment i) async => {
        'name': i.name,
        'investment_type': i.type.name,
        'notes': i.notes,
        'is_favorite': i.isFavorite,
        'created_at': i.createdAt.toIso8601String(),
        'updated_at': i.updatedAt.toIso8601String(),
        'institution': i.institution,
        'account_number': i.accountNumber,
        'units': i.units,
        'purchase_price': i.purchasePrice,
        'invested_amount': i.investedAmount,
        'current_value': i.currentValue,
        'purchase_date': _date(i.purchaseDate),
        'maturity_date': _date(i.maturityDate),
        'nominee': i.nominee,
        'attachments': [for (final a in i.attachments) a.toJson()],
      };

  @override
  Future<Investment> fromRow(Map<String, dynamic> row) async => Investment(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? 'Investment',
        type: InvestmentTypeX.fromName(row['investment_type'] as String?),
        createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
        institution: row['institution'] as String?,
        accountNumber: row['account_number'] as String?,
        units: _num(row['units']),
        purchasePrice: _num(row['purchase_price']),
        investedAmount: _num(row['invested_amount']),
        currentValue: _num(row['current_value']),
        purchaseDate: _parseDate(row['purchase_date']),
        maturityDate: _parseDate(row['maturity_date']),
        nominee: row['nominee'] as String?,
        notes: row['notes'] as String?,
        attachments: [
          for (final a in (row['attachments'] as List?) ?? const [])
            InvestmentAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        isFavorite: (row['is_favorite'] as bool?) ?? false,
      );

  /// `date` columns reject a full timestamp, so send YYYY-MM-DD only.
  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  /// Postgres `numeric` arrives as a String over PostgREST, not a num - parsing
  /// it as `num?` would silently null every amount on the way back in.
  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Favourites first, then largest holding first.
  List<Investment> get sorted {
    final list = [...items]..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.value.compareTo(a.value);
      });
    return List.unmodifiable(list);
  }

  double get totalValue => items.fold(0.0, (s, i) => s + i.value);
  double get totalInvested => items.fold(0.0, (s, i) => s + i.invested);
  double get totalProfit => totalValue - totalInvested;

  /// Portfolio return as a fraction, or null when nothing is invested.
  double? get totalReturn {
    final base = totalInvested;
    if (base <= 0) return null;
    return totalProfit / base;
  }

  /// Value per instrument type, largest first, with each share of the total.
  /// Types the user holds nothing in are omitted.
  List<InvestmentSlice> get allocation {
    final byType = <InvestmentType, double>{};
    for (final i in items) {
      byType[i.type] = (byType[i.type] ?? 0) + i.value;
    }
    final total = byType.values.fold(0.0, (s, v) => s + v);
    final slices = [
      for (final e in byType.entries)
        InvestmentSlice(
          type: e.key,
          value: e.value,
          share: total <= 0 ? 0 : e.value / total,
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return List.unmodifiable(slices);
  }

  List<Investment> ofType(InvestmentType type) =>
      items.where((i) => i.type == type).toList();

  /// Holdings whose maturity date falls within the next [days] days, soonest
  /// first - what the dashboard's attention banner watches.
  List<Investment> maturingWithin(int days) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: days));
    final list = items
        .where((i) =>
            i.maturityDate != null &&
            i.maturityDate!.isAfter(now) &&
            i.maturityDate!.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.maturityDate!.compareTo(b.maturityDate!));
    return list;
  }

  Future<void> toggleFavorite(String id) async {
    final i = byId(id);
    if (i == null) return;
    await update(i.copyWith(isFavorite: !i.isFavorite));
  }
}
