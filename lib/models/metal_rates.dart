import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Immutable snapshot of live precious-metal rates, normalised to Indian
/// rupees **per gram** (the unit the UI shows), with provenance so the UI can
/// render "LIVE" / "Last updated".
///
/// Built from raw spot USD/oz + USD→INR FX via [MetalRates.fromSpot], which
/// applies the troy-ounce → gram conversion automatically (the "bonus"
/// requirement — no manual conversion at the call site).
@immutable
class MetalRates {
  const MetalRates({
    required this.goldPerGram,
    required this.silverPerGram,
    required this.currency,
    required this.timestamp,
    required this.source,
  });

  /// ₹ per gram of 24K (pure) gold.
  final double goldPerGram;

  /// ₹ per gram of silver.
  final double silverPerGram;

  /// ISO currency code — always `INR` for the Indian UI.
  final String currency;

  /// When these rates were fetched (stored in UTC).
  final DateTime timestamp;

  /// Human-readable provenance, e.g. `swissquote + frankfurter`.
  final String source;

  /// 1 troy ounce = 31.1034768 grams.
  static const double gramsPerTroyOunce = 31.1034768;

  /// Builds rupee-per-gram rates from raw spot USD/oz prices and the USD→INR
  /// exchange rate. Conversion: `usdPerOunce × usdToInr ÷ gramsPerTroyOunce`.
  factory MetalRates.fromSpot({
    required double goldUsdPerOunce,
    required double silverUsdPerOunce,
    required double usdToInr,
    required DateTime timestamp,
    required String source,
  }) {
    double perGram(double usdPerOunce) =>
        usdPerOunce * usdToInr / gramsPerTroyOunce;
    return MetalRates(
      goldPerGram: perGram(goldUsdPerOunce),
      silverPerGram: perGram(silverUsdPerOunce),
      currency: 'INR',
      timestamp: timestamp,
      source: source,
    );
  }

  /// 22K gold is 22/24 of pure — a common Indian retail reference.
  double get gold22kPerGram => goldPerGram * 22 / 24;

  Map<String, dynamic> toJson() => {
    'goldPerGram': goldPerGram,
    'silverPerGram': silverPerGram,
    'currency': currency,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'source': source,
  };

  factory MetalRates.fromJson(Map<String, dynamic> json) => MetalRates(
    goldPerGram: (json['goldPerGram'] as num).toDouble(),
    silverPerGram: (json['silverPerGram'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'INR',
    timestamp: DateTime.parse(json['timestamp'] as String),
    source: json['source'] as String? ?? 'unknown',
  );

  String encode() => jsonEncode(toJson());

  static MetalRates decode(String raw) =>
      MetalRates.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetalRates &&
          other.goldPerGram == goldPerGram &&
          other.silverPerGram == silverPerGram &&
          other.currency == currency &&
          other.timestamp == timestamp &&
          other.source == source;

  @override
  int get hashCode =>
      Object.hash(goldPerGram, silverPerGram, currency, timestamp, source);

  @override
  String toString() =>
      'MetalRates(gold=₹${goldPerGram.toStringAsFixed(2)}/g, '
      'silver=₹${silverPerGram.toStringAsFixed(2)}/g, at $timestamp)';
}
