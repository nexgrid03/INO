import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/dashboard_models.dart';

/// Fetches LIVE gold & silver rates and merges them into the market quote list.
///
/// Uses two FREE, KEYLESS public APIs (no signup, no API key):
///   • gold-api.com  → live spot price in USD per troy ounce (XAU gold, XAG silver)
///   • frankfurter   → USD→INR exchange rate (ECB data)
/// then converts to ₹/gram (gold) and ₹/kg (silver) for the Indian UI.
///
/// Petrol/Diesel stay on their fallback values for now. Everything is
/// best-effort: no network or an API error simply leaves each quote at its
/// fallback value — the Market card never breaks.
class MarketRatesService {
  MarketRatesService._();
  static final MarketRatesService instance = MarketRatesService._();

  static const _timeout = Duration(seconds: 8);
  static const double _gramsPerTroyOunce = 31.1034768;

  /// Diagnostic: the outcome of the last [fetchLive] call, surfaced on the
  /// Markets screen so failures are visible without reading the console.
  static String lastStatus = 'not fetched yet';
  String _err = '';

  /// Returns [fallback] with the Gold & Silver entries replaced by live rates.
  Future<List<MarketQuote>> fetchLive(List<MarketQuote> fallback) async {
    _err = '';
    try {
      // Metal spot prices + FX rate in parallel so it's a single quick round.
      final results = await Future.wait([
        _spotUsdPerOunce('XAU'),
        _spotUsdPerOunce('XAG'),
        _usdToInr(),
      ]);
      final goldUsd = results[0];
      final silverUsd = results[1];
      final usdInr = results[2];

      lastStatus = 'gold=$goldUsd silver=$silverUsd fx=$usdInr'
          '${_err.isEmpty ? '' : ' | ERR: $_err'}';
      debugPrint('Live rates fetched → $lastStatus');

      // Without the FX rate we can't convert to rupees → keep fallbacks.
      if (usdInr == null) return fallback;

      return [
        for (final q in fallback)
          if (q.label == 'Gold 24K' && goldUsd != null)
            q.copyWith(
              price: _inr(goldUsd * usdInr / _gramsPerTroyOunce),
              unit: '/ gram',
            )
          else if (q.label == 'Silver' && silverUsd != null)
            q.copyWith(
              // per gram → per kilogram for the silver quote.
              price: _inr(silverUsd * usdInr / _gramsPerTroyOunce * 1000),
              unit: '/ kg',
            )
          else
            q,
      ];
    } catch (e) {
      lastStatus = 'exception: $e';
      debugPrint('Market rates failed: $e');
      return fallback;
    }
  }

  /// Live spot MID price in USD per troy ounce for `XAU` (gold) / `XAG` (silver)
  /// from Swissquote's public quotes feed (keyless), or null on any failure.
  Future<double?> _spotUsdPerOunce(String symbol) async {
    try {
      final res = await http.get(
        Uri.parse('https://forex-data-feed.swissquote.com/public-quotes/'
            'bboquotes/instrument/$symbol/USD'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        _err += '$symbol=HTTP${res.statusCode}; ';
        return null;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isEmpty) {
        _err += '$symbol=empty; ';
        return null;
      }
      final prices = (list.first as Map<String, dynamic>)['spreadProfilePrices']
          as List<dynamic>?;
      if (prices == null || prices.isEmpty) {
        _err += '$symbol=noprices; ';
        return null;
      }
      final p = prices.first as Map<String, dynamic>;
      final bid = (p['bid'] as num?)?.toDouble();
      final ask = (p['ask'] as num?)?.toDouble();
      if (bid == null || ask == null || bid <= 0) {
        _err += '$symbol=nobidask; ';
        return null;
      }
      return (bid + ask) / 2; // mid price
    } catch (e) {
      _err += '$symbol=$e; ';
      debugPrint('Spot $symbol failed: $e');
      return null;
    }
  }

  /// Live USD→INR exchange rate (ECB data via frankfurter, keyless).
  Future<double?> _usdToInr() async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://api.frankfurter.dev/v1/latest?base=USD&symbols=INR'))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        _err += 'FX=HTTP${res.statusCode}; ';
        return null;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final rate = (json['rates']?['INR'] as num?)?.toDouble();
      return (rate != null && rate > 0) ? rate : null;
    } catch (e) {
      _err += 'FX=$e; ';
      debugPrint('FX USD->INR failed: $e');
      return null;
    }
  }

  /// Indian-grouped rupee string, e.g. 92300 → "₹92,300", 1234567 → "₹12,34,567".
  String _inr(double value) {
    var s = value.round().toString();
    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);

    if (s.length > 3) {
      final last3 = s.substring(s.length - 3);
      var head = s.substring(0, s.length - 3);
      final groups = <String>[];
      while (head.length > 2) {
        groups.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
      if (head.isNotEmpty) groups.insert(0, head);
      s = '${groups.join(',')},$last3';
    }
    return '₹${negative ? '-' : ''}$s';
  }
}
