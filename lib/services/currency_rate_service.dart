import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/currency.dart';
import '../utils/indian_number_format.dart';

/// One converted value, ready to display.
class CurrencyConversion {
  const CurrencyConversion({
    required this.currency,
    required this.value,
    required this.display,
  });

  /// The target currency.
  final Currency currency;

  /// The high-precision converted amount (unrounded).
  final double value;

  /// [value] formatted with its currency symbol and grouping. Never format a
  /// converted amount in a widget - read this.
  final String display;
}

/// The single source of truth for currency conversion maths.
///
/// Every rate is "units of the currency per 1 USD", so any pair converts
/// through USD in one step:
///
///   amount × (perUsd[to] / perUsd[from])
///
/// Rates come from two layers:
///  1. **live** - [fetch] pulls ECB reference rates from frankfurter (free,
///     keyless, already used by [MarketRatesService] for USD→INR). Covers the
///     ~30 majors the ECB publishes;
///  2. **baseline** - [ratesPerUsd], a shipped table covering EVERY currency in
///     [Currencies.all], used offline and for the currencies the feed omits
///     (PKR, AED, KES …).
///
/// Either way a rate is only ever *indicative*, so the Currency Converter also
/// lets the user type today's exact rate over the pair - the maths here never
/// assumes the table is right.
class CurrencyRateService {
  CurrencyRateService._();

  /// Shared instance. Holds the fetched rates, so it's a singleton rather than a
  /// const value; the user's rate override lives in the screen that owns it.
  static final CurrencyRateService instance = CurrencyRateService._();

  static const _endpoint = 'https://api.frankfurter.dev/v1/latest?base=USD';
  static const _timeout = Duration(seconds: 8);

  /// Live rates per USD, by ISO code - empty until a [fetch] succeeds.
  final Map<String, double> _live = {};

  DateTime? _fetchedAt;

  /// When the live rates last arrived, or null if they never did.
  DateTime? get fetchedAt => _fetchedAt;

  /// True once a live fetch has landed (the UI can then say so).
  bool get isLive => _live.isNotEmpty;

  /// Whether BOTH sides of a pair are covered by the live feed - the only case
  /// where the pair rate can honestly be called live.
  bool isLivePair(Currency from, Currency to) =>
      _live.containsKey(from.code) && _live.containsKey(to.code);

  /// Units of each currency per 1 USD - the offline baseline. Covers every entry
  /// in [Currencies.all]: a currency without a rate here can't be converted when
  /// the feed is unavailable or doesn't list it, so keep the two lists in step
  /// (there's a test that asserts exactly that).
  ///
  /// The currencies the ECB publishes are seeded from that feed; the rest are
  /// approximations (the pegged Gulf currencies are exact by definition, the
  /// floating ones drift). The editable rate field is how a user gets exact.
  static const Map<String, double> ratesPerUsd = {
    'USD': 1,

    // South Asia. NPR and BTN are pegged to the rupee, so [perUsd] re-derives
    // them from INR whenever a live INR rate is available.
    'INR': 96.5,
    'PKR': 279,
    'BDT': 120,
    'LKR': 295,
    'NPR': 154.4, // 1.60 NPR per INR (fixed peg)
    'BTN': 96.5, // at par with INR (fixed peg)
    'MVR': 15.4,
    'AFN': 70,

    // Global majors.
    'EUR': 0.879,
    'GBP': 0.751,
    'JPY': 163.8,
    'CNY': 6.77,
    'CHF': 0.818,
    'AUD': 1.431,
    'CAD': 1.409,
    'NZD': 1.728,
    'SGD': 1.291,
    'HKD': 7.843,

    // Gulf & Middle East (most are USD-pegged).
    'AED': 3.6725,
    'SAR': 3.75,
    'QAR': 3.64,
    'KWD': 0.307,
    'BHD': 0.376,
    'OMR': 0.3845,
    'ILS': 3.054,
    'JOD': 0.709,

    // Asia-Pacific.
    'MYR': 4.091,
    'THB': 33.69,
    'IDR': 17929,
    'PHP': 61.84,
    'VND': 25400,
    'KRW': 1461,
    'TWD': 32.5,
    'MMK': 2100,
    'KHR': 4050,
    'LAK': 21800,
    'KZT': 500,

    // Europe.
    'SEK': 9.717,
    'NOK': 9.57,
    'DKK': 6.571,
    'PLN': 3.793,
    'CZK': 21.226,
    'HUF': 318.1,
    'RON': 4.601,
    'UAH': 41.5,
    'RUB': 92,
    'TRY': 47.35,

    // Americas.
    'BRL': 5.083,
    'MXN': 17.48,
    'ARS': 1030,
    'CLP': 950,
    'COP': 4200,
    'PEN': 3.75,

    // Africa.
    'ZAR': 16.85,
    'NGN': 1550,
    'EGP': 49,
    'KES': 129,
    'GHS': 15.2,
    'TZS': 2650,
    'UGX': 3680,
    'MAD': 9.9,
    'ETB': 125,
  };

  /// Currencies with a FIXED peg to the Indian rupee, and how many of them one
  /// rupee buys. The ECB feed doesn't carry them, but the peg means a live INR
  /// rate gives their live rate for free - without this they'd silently drift
  /// away from the INR they're pegged to.
  static const Map<String, double> _inrPegged = {
    'NPR': 1.60, // Nepal: 1 INR = 1.60 NPR
    'BTN': 1.00, // Bhutan: at par with INR
  };

  /// The rate for one currency against the USD - live if we have it, derived
  /// from a live INR rate for the rupee-pegged currencies, else the shipped
  /// baseline, else null (a currency we simply can't convert).
  double? perUsd(String code) {
    final live = _live[code];
    if (live != null && live > 0) return live;

    final peg = _inrPegged[code];
    final liveInr = _live['INR'];
    if (peg != null && liveInr != null && liveInr > 0) return liveInr * peg;

    return ratesPerUsd[code];
  }

  /// How many units of [to] one unit of [from] buys, or 0 when either currency
  /// has no rate (never throws - a missing rate reads as "can't convert").
  double rate(Currency from, Currency to) {
    if (from.code == to.code) return 1;
    final f = perUsd(from.code);
    final t = perUsd(to.code);
    if (f == null || t == null || f <= 0) return 0;
    return t / f;
  }

  /// Converts [amount] from [from] to [to]. Pass [rateOverride] to use a rate
  /// the user typed in (today's exact rate) instead of the table.
  double convert(
    double amount,
    Currency from,
    Currency to, {
    double? rateOverride,
  }) {
    if (amount == 0) return 0;
    final r = rateOverride ?? rate(from, to);
    return amount * r;
  }

  /// [amount] of [from] converted into every currency in [Currencies.all], in
  /// registry order. Excludes [from] itself unless [includeSource] is set, skips
  /// any currency without a rate, and drops [excludeCode] (used to leave out a
  /// currency that's already shown elsewhere).
  List<CurrencyConversion> convertToAll(
    double amount,
    Currency from, {
    bool includeSource = false,
    String? excludeCode,
  }) {
    final out = <CurrencyConversion>[];
    for (final c in Currencies.all) {
      if (!includeSource && c.code == from.code) continue;
      if (c.code == excludeCode) continue;
      if (perUsd(c.code) == null) continue;
      final v = convert(amount, from, c);
      out.add(CurrencyConversion(currency: c, value: v, display: format(v, c)));
    }
    return out;
  }

  /// Decimal places for a converted amount: small values need cents to stay
  /// meaningful ($1.16), large ones read better whole (₹8,650).
  int decimalsFor(double value) {
    final abs = value.abs();
    if (abs == 0) return 2;
    if (abs >= 10000) return 0;
    if (abs >= 1) return 2;
    // Sub-unit results (e.g. 1 IDR in USD) would round to 0.00 - keep enough
    // places to show something.
    return abs >= 0.01 ? 4 : 6;
  }

  /// A converted amount with its currency symbol and grouping style.
  String format(double value, Currency currency) =>
      money(value, currency, decimals: decimalsFor(value));

  /// The pair rate as a display string, e.g. "1 USD = 86.50 INR". Rates need
  /// more precision than amounts (0.0116 USD per INR), so they use their own
  /// formatting rather than [format].
  String rateLine(Currency from, Currency to, {double? rateOverride}) {
    final r = rateOverride ?? rate(from, to);
    return '1 ${from.code} = ${formatRate(r)} ${to.code}';
  }

  /// A rate with enough significant digits to be usable in both directions
  /// (86.5 → "86.5", 0.011561 → "0.011561"), trailing zeros stripped.
  String formatRate(double r) {
    if (r == 0 || r.isNaN || r.isInfinite) return '0';
    final abs = r.abs();
    final int decimals;
    if (abs >= 1000) {
      decimals = 2;
    } else if (abs >= 1) {
      decimals = 4;
    } else if (abs >= 0.01) {
      decimals = 6;
    } else {
      decimals = 8;
    }
    var s = r.toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// A plain-text block for "Copy All", e.g.
  ///
  ///   1000 INR =
  ///   USD 11.56
  ///   EUR 10.64
  ///   …
  String asCopyText(double amount, Currency from, {String? excludeCode}) {
    final buffer = StringBuffer('${formatRate(amount)} ${from.code} =\n');
    for (final c in convertToAll(amount, from, excludeCode: excludeCode)) {
      buffer.writeln('${c.currency.code} ${c.display}');
    }
    return buffer.toString().trimRight();
  }

  /// Pulls live ECB reference rates (keyless, no signup) and keeps them in
  /// memory for the rest of the session. Returns true when rates landed.
  ///
  /// Best-effort by design: no network, a slow endpoint or a malformed payload
  /// simply leaves the baseline table in charge - conversion never breaks and
  /// the UI just keeps saying the rates are indicative.
  Future<bool> fetch() async {
    try {
      final res = await http.get(Uri.parse(_endpoint)).timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('FX rates: HTTP ${res.statusCode}');
        return false;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final rates = json['rates'] as Map<String, dynamic>?;
      if (rates == null || rates.isEmpty) return false;

      final fresh = <String, double>{};
      rates.forEach((code, value) {
        final r = (value as num?)?.toDouble();
        if (r != null && r > 0) fresh[code] = r;
      });
      if (fresh.isEmpty) return false;
      // The feed is USD-based, so it never lists USD itself.
      fresh['USD'] = 1;

      _live
        ..clear()
        ..addAll(fresh);
      _fetchedAt = DateTime.now();
      debugPrint('FX rates: ${_live.length} live rates (${json['date']})');
      return true;
    } catch (e) {
      debugPrint('FX rates failed: $e');
      return false;
    }
  }

  /// Test hook: forget the live rates so the baseline is back in charge.
  @visibleForTesting
  void resetLiveRates() {
    _live.clear();
    _fetchedAt = null;
  }

  /// Test hook: stand in for a successful [fetch] without touching the network.
  @visibleForTesting
  void applyLiveRatesForTest(Map<String, double> rates) {
    _live
      ..clear()
      ..addAll(rates);
    _fetchedAt = DateTime(2026, 7, 26);
  }
}
