import '../models/card_models.dart';
import 'local_collection_store.dart';

/// The Banking Wallet's saved cards (device-local, per account).
///
/// What is stored is deliberately not enough to transact: a label, the bank,
/// the holder's name, the network and the **last four digits only**. There is
/// no CVV field and no full card number anywhere in the app.
class CardStore extends LocalCollectionStore<SavedCard> {
  CardStore._();
  static final CardStore instance = CardStore._();

  @override
  String get storageKey => 'ino_cards';

  @override
  Map<String, dynamic> encode(SavedCard item) => item.toJson();

  @override
  SavedCard decode(Map<String, dynamic> json) => SavedCard.fromJson(json);

  @override
  String idOf(SavedCard item) => item.id;

  /// Favourites first, then most recently added.
  List<SavedCard> get sorted {
    final list = [...items]..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return List.unmodifiable(list);
  }

  int countOf(CardKind kind) => items.where((c) => c.kind == kind).length;

  /// Cards past their expiry month, or within 60 days of it.
  List<SavedCard> get needingAttention =>
      items.where((c) => c.isExpired || c.isExpiringSoon).toList();

  Future<void> toggleFavorite(String id) async {
    final c = byId(id);
    if (c == null) return;
    await update(c.copyWith(isFavorite: !c.isFavorite));
  }
}

/// How the card list can be ordered.
enum CardSort { recent, bank, expiry, name }

extension CardSortX on CardSort {
  String get label => switch (this) {
        CardSort.recent => 'Recently added',
        CardSort.bank => 'Bank (A–Z)',
        CardSort.expiry => 'Expiring first',
        CardSort.name => 'Name (A–Z)',
      };

  /// Applies this ordering. Favourites always float to the top first, so a
  /// pinned card never disappears down the stack after a re-sort.
  List<SavedCard> apply(List<SavedCard> cards) {
    final list = [...cards];
    int byFavorite(SavedCard a, SavedCard b) =>
        a.isFavorite == b.isFavorite ? 0 : (a.isFavorite ? -1 : 1);
    list.sort((a, b) {
      final f = byFavorite(a, b);
      if (f != 0) return f;
      switch (this) {
        case CardSort.recent:
          return b.createdAt.compareTo(a.createdAt);
        case CardSort.bank:
          return a.bank.toLowerCase().compareTo(b.bank.toLowerCase());
        case CardSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case CardSort.expiry:
          // Cards without an expiry sort last rather than pretending to be soon.
          final ae = a.expiryYear == null || a.expiryMonth == null
              ? null
              : DateTime(a.expiryYear!, a.expiryMonth!);
          final be = b.expiryYear == null || b.expiryMonth == null
              ? null
              : DateTime(b.expiryYear!, b.expiryMonth!);
          if (ae == null && be == null) return 0;
          if (ae == null) return 1;
          if (be == null) return -1;
          return ae.compareTo(be);
      }
    });
    return list;
  }
}
