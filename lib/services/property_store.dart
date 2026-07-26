import '../models/property_models.dart';
import 'local_collection_store.dart';

/// The Property Wallet's register of properties (device-local, per account).
class PropertyStore extends LocalCollectionStore<Property> {
  PropertyStore._();
  static final PropertyStore instance = PropertyStore._();

  @override
  String get storageKey => 'ino_properties';

  @override
  Map<String, dynamic> encode(Property item) => item.toJson();

  @override
  Property decode(Map<String, dynamic> json) => Property.fromJson(json);

  @override
  String idOf(Property item) => item.id;

  /// Favourites first, then most recently updated.
  List<Property> get sorted {
    final list = [...items]..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return List.unmodifiable(list);
  }

  /// Total portfolio value across every property (current estimate, else the
  /// purchase price). Properties marked Sold are excluded - they're history.
  double get totalValue => items
      .where((p) => p.status != PropertyStatus.sold)
      .fold(0.0, (s, p) => s + p.portfolioValue);

  /// What was paid in total, for the same set of properties.
  double get totalInvested => items
      .where((p) => p.status != PropertyStatus.sold)
      .fold(0.0, (s, p) => s + (p.purchasePrice ?? 0));

  /// Portfolio-level appreciation, or null when no purchase price is recorded.
  double? get totalAppreciation {
    final invested = totalInvested;
    if (invested <= 0) return null;
    return (totalValue - invested) / invested;
  }

  /// Monthly rental income across rented / leased properties.
  double get monthlyRent =>
      items.fold(0.0, (s, p) => s + (p.rentalIncome ?? 0));

  /// Total outstanding loan across every property.
  double get totalLoan =>
      items.fold(0.0, (s, p) => s + (p.hasLoan ? (p.outstandingLoan ?? 0) : 0));

  int countOf(PropertyStatus status) =>
      items.where((p) => p.status == status).length;

  Future<void> toggleFavorite(String id) async {
    final p = byId(id);
    if (p == null) return;
    await update(p.copyWith(isFavorite: !p.isFavorite));
  }
}
