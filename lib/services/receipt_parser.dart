/// Best-effort extraction of ITR-relevant fields from raw receipt OCR text.
///
/// Deliberately conservative — every field is nullable and only returned when a
/// confident pattern matches, so the Add screen only *pre-fills* (never
/// overwrites blindly). Pure Dart + regex → unit-testable without a device.
class ReceiptData {
  const ReceiptData({this.amount, this.date, this.gstNumber, this.vendorName});

  final double? amount;
  final DateTime? date;
  final String? gstNumber;
  final String? vendorName;

  bool get isEmpty =>
      amount == null && date == null && gstNumber == null && vendorName == null;
}

class ReceiptParser {
  const ReceiptParser._();

  // GSTIN: 2 digit state + 5 letters + 4 digits + 1 letter + 1 alnum + 'Z' + 1 alnum.
  static final _gstRe = RegExp(
      r'\b(\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d])\b',
      caseSensitive: false);

  // Amounts like 1,234.56 / 1234 / 12.00 near a currency symbol or total word.
  static final _amountRe =
      RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)');
  static final _currencyRe = RegExp(
      r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);

  static final _dMonY = RegExp(
      r'\b(\d{1,2})\s*[-/ ]\s*'
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*[-/, ]?\s*(\d{2,4})\b',
      caseSensitive: false);
  static final _dmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');

  static const _monthMap = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static ReceiptData parse(String text) {
    return ReceiptData(
      amount: _amount(text),
      date: _date(text),
      gstNumber: _gst(text),
      vendorName: _vendor(text),
    );
  }

  static String? _gst(String text) {
    final m = _gstRe.firstMatch(text);
    return m?.group(1)?.toUpperCase();
  }

  static double? _amount(String text) {
    // Prefer an amount on a line mentioning a total; otherwise the largest
    // currency-tagged amount; otherwise the largest bare money-like number.
    double? totalLine;
    double? maxCurrency;
    for (final line in text.split('\n')) {
      final low = line.toLowerCase();
      final isTotal = low.contains('total') ||
          low.contains('grand') ||
          low.contains('amount') ||
          low.contains('paid');
      for (final m in _currencyRe.allMatches(line)) {
        final v = _num(m.group(1));
        if (v == null) continue;
        if (maxCurrency == null || v > maxCurrency) maxCurrency = v;
        if (isTotal) totalLine = v;
      }
    }
    if (totalLine != null) return totalLine;
    if (maxCurrency != null) return maxCurrency;

    double? maxBare;
    for (final m in _amountRe.allMatches(text)) {
      final raw = m.group(1)!;
      if (!raw.contains('.') && raw.replaceAll(',', '').length < 3) continue;
      final v = _num(raw);
      if (v != null && (maxBare == null || v > maxBare)) maxBare = v;
    }
    return maxBare;
  }

  static DateTime? _date(String text) {
    final m1 = _dMonY.firstMatch(text);
    if (m1 != null) {
      final day = int.tryParse(m1.group(1)!);
      final mon = _monthMap[m1.group(2)!.toLowerCase().substring(0, 3)];
      final year = _year(m1.group(3)!);
      if (day != null && mon != null && year != null) {
        return _safe(year, mon, day);
      }
    }
    final m2 = _dmy.firstMatch(text);
    if (m2 != null) {
      final day = int.tryParse(m2.group(1)!);
      final mon = int.tryParse(m2.group(2)!);
      final year = _year(m2.group(3)!);
      if (day != null && mon != null && year != null && mon <= 12 && day <= 31) {
        return _safe(year, mon, day);
      }
    }
    return null;
  }

  static String? _vendor(String text) {
    // The vendor is usually near the top — the first line that is mostly
    // letters and not a header like "TAX INVOICE" / "RECEIPT".
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.length < 3 || line.length > 40) continue;
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
      if (letters < line.length * 0.6) continue;
      final low = line.toLowerCase();
      if (low.contains('invoice') ||
          low.contains('receipt') ||
          low.contains('bill') ||
          low.contains('gstin') ||
          low.contains('tax')) {
        continue;
      }
      return line;
    }
    return null;
  }

  static double? _num(String? s) =>
      s == null ? null : double.tryParse(s.replaceAll(',', ''));

  static int? _year(String s) {
    final y = int.tryParse(s);
    if (y == null) return null;
    if (y < 100) return 2000 + y;
    return y;
  }

  static DateTime? _safe(int y, int m, int d) {
    try {
      final dt = DateTime(y, m, d);
      if (dt.month != m || dt.day != d) return null; // overflow guard
      return dt;
    } catch (_) {
      return null;
    }
  }
}
