import 'package:flutter/foundation.dart';

/// A gold-price quote (per gram of 24K), with provenance so the UI can show
/// whether it's a live rate or a local placeholder the user can edit.
class GoldPrice {
  const GoldPrice({
    required this.pricePerGram24k,
    required this.isLive,
    this.asOf,
  });

  /// ₹ per gram of pure (24K) gold.
  final double pricePerGram24k;

  /// True once a real feed is wired; false for the editable placeholder.
  final bool isLive;

  final DateTime? asOf;
}

/// Source of the current gold price.
///
/// INO has no live bullion feed yet, so this ships a **placeholder** the user
/// can override with today's rate. The structure is deliberately feed-ready:
/// swap [fetch] for a real API call (and flip [GoldPrice.isLive]) later without
/// touching the calculator UI. Exposed as a [ChangeNotifier] so screens can
/// react if the rate is refreshed.
class GoldPriceService extends ChangeNotifier {
  GoldPriceService._();
  static final GoldPriceService instance = GoldPriceService._();

  // A realistic recent placeholder (₹/g, 24K). Not a live rate — the Gold
  // calculator lets the user type today's price over it.
  double _pricePerGram24k = 7350;

  // When a real bullion feed is wired (in [fetch]), set these from the response.
  GoldPrice get current => GoldPrice(
        pricePerGram24k: _pricePerGram24k,
        isLive: false,
        asOf: null,
      );

  /// Overrides the working price (e.g. the user typed today's rate).
  void setPricePerGram24k(double value) {
    if (value <= 0 || value == _pricePerGram24k) return;
    _pricePerGram24k = value;
    notifyListeners();
  }

  /// Placeholder for a future live fetch. Today it just echoes the current
  /// (placeholder) value; wire a real endpoint here and set `_isLive = true`.
  Future<GoldPrice> fetch() async => current;
}
