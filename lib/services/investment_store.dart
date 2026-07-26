import '../models/investment_models.dart';
import 'local_collection_store.dart';

/// The Investment Wallet's portfolio (device-local, per account).
///
/// Every aggregate here is derived from the holdings themselves - the store
/// never persists a total, so a figure on the dashboard can't drift out of sync
/// with the rows beneath it.
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
