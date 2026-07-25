// Number & currency formatting.
//
// Centralised so every calculator renders money the same way - never format a
// money value inline in a widget. Indian grouping (lakhs / crores) is the
// default for ₹ and the other South-Asian currencies; everything else groups
// western-style via [money].

import '../models/currency.dart';

/// Groups an integer/decimal the Indian way: the last three digits, then in
/// pairs - e.g. 10920000 → "1,09,20,000", 5000 → "5,000".
String indianGroup(num value, {int decimals = 0}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
  final decPart = dot == -1 ? '' : fixed.substring(dot + 1);

  String grouped;
  if (intPart.length <= 3) {
    grouped = intPart;
  } else {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final chunks = <String>[];
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) chunks.insert(0, rest);
    grouped = '${chunks.join(',')},$last3';
  }

  final out = decPart.isEmpty ? grouped : '$grouped.$decPart';
  return negative ? '-$out' : out;
}

/// Rupee string with the ₹ symbol and Indian grouping - e.g. "₹1,09,20,000".
String rupees(num value, {int decimals = 0}) =>
    '₹${indianGroup(value, decimals: decimals)}';

/// Abbreviated rupees in Indian words - ₹1.09 Cr / ₹25.00 L / ₹5,000.
String rupeesWords(num value) {
  final negative = value < 0;
  final v = value.abs();
  final String out;
  if (v >= 10000000) {
    out = '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  } else if (v >= 100000) {
    out = '₹${(v / 100000).toStringAsFixed(2)} L';
  } else {
    out = rupees(v);
  }
  return negative ? '-$out' : out;
}

/// Groups an integer/decimal western-style in threes - e.g. 10920000 →
/// "10,920,000".
String westernGroup(num value, {int decimals = 0}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
  final decPart = dot == -1 ? '' : fixed.substring(dot + 1);

  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }

  final out = decPart.isEmpty ? '$buf' : '$buf.$decPart';
  return negative ? '-$out' : out;
}

/// Money in [currency]: its symbol + the grouping style it uses -
/// e.g. "₹1,09,20,000" (INR) vs "$10,920,000" (USD).
String money(num value, Currency currency, {int decimals = 0}) {
  final grouped = currency.indianGrouping
      ? indianGroup(value, decimals: decimals)
      : westernGroup(value, decimals: decimals);
  return '${currency.symbol}$grouped';
}

/// Abbreviated money - lakh/crore words for Indian-grouping currencies
/// (₹1.09 Cr), K/M/B for the rest ($10.92M).
String moneyWords(num value, Currency currency) {
  final negative = value < 0;
  final v = value.abs();
  final String out;
  if (currency.indianGrouping) {
    if (v >= 10000000) {
      out = '${currency.symbol}${(v / 10000000).toStringAsFixed(2)} Cr';
    } else if (v >= 100000) {
      out = '${currency.symbol}${(v / 100000).toStringAsFixed(2)} L';
    } else {
      out = money(v, currency);
    }
  } else {
    if (v >= 1000000000) {
      out = '${currency.symbol}${(v / 1000000000).toStringAsFixed(2)}B';
    } else if (v >= 1000000) {
      out = '${currency.symbol}${(v / 1000000).toStringAsFixed(2)}M';
    } else if (v >= 10000) {
      out = '${currency.symbol}${(v / 1000).toStringAsFixed(2)}K';
    } else {
      out = money(v, currency);
    }
  }
  return negative ? '-$out' : out;
}
