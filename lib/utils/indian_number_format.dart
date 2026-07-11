// Indian-style number & currency formatting (lakhs / crores).
//
// Centralised so every calculator renders money the same way — never format a
// rupee value inline in a widget.

/// Groups an integer/decimal the Indian way: the last three digits, then in
/// pairs — e.g. 10920000 → "1,09,20,000", 5000 → "5,000".
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

/// Rupee string with the ₹ symbol and Indian grouping — e.g. "₹1,09,20,000".
String rupees(num value, {int decimals = 0}) =>
    '₹${indianGroup(value, decimals: decimals)}';

/// Abbreviated rupees in Indian words — ₹1.09 Cr / ₹25.00 L / ₹5,000.
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
