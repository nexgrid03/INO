/// Best-effort, LABEL-AWARE extraction of ITR-relevant fields from raw receipt /
/// payment-screenshot OCR text.
///
/// Deliberately conservative — every field is nullable and only returned when a
/// confident, context-appropriate pattern matches, so the Add screen only
/// *pre-fills* (never overwrites blindly, never fills garbage). Pure Dart +
/// regex → unit-testable without a device.
///
/// The cardinal rule after the "Transaction ID read as the amount" bug: a long
/// reference code (Transaction ID / UTR, e.g. "T2607251037436024") must NEVER
/// flow into the amount. Amounts are identified by their ₹/Rs/INR symbol or an
/// amount/paid/total label AND validated by [parseAmount]; IDs are extracted
/// separately and kept as strings exactly as printed.
class ReceiptData {
  const ReceiptData({
    this.amount,
    this.date,
    this.gstNumber,
    this.vendorName,
    this.transactionId,
  });

  final double? amount;
  final DateTime? date;
  final String? gstNumber;
  final String? vendorName;

  /// A payment reference code (Transaction ID / UTR / order id), kept verbatim
  /// as a string — never numeric.
  final String? transactionId;

  bool get isEmpty =>
      amount == null &&
      date == null &&
      gstNumber == null &&
      vendorName == null &&
      transactionId == null;
}

class ReceiptParser {
  const ReceiptParser._();

  // GSTIN: 2 digit state + 5 letters + 4 digits + 1 letter + 1 alnum + 'Z' + 1 alnum.
  static final _gstRe = RegExp(
      r'\b(\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d])\b',
      caseSensitive: false);

  // A money-like token: 1,234.56 / 1234 / 12.00. Digits + optional thousands
  // separators + at most two decimals.
  static final _amountRe = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)');

  // A money token immediately preceded by a currency marker (₹ / Rs / INR).
  static final _currencyRe = RegExp(
      r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);

  // Transaction-ID / UTR / reference, captured AFTER its label so we never
  // confuse it with an amount. The code itself is 8–30 alphanumerics.
  static final _txnIdLabelRe = RegExp(
    r'(?:upi\s*(?:transaction\s*)?(?:id|ref(?:erence)?(?:\s*no)?)'
    r'|transaction\s*(?:id|no|ref(?:erence)?)'
    r'|txn\s*(?:id|no)?'
    r'|utr(?:\s*(?:no|number))?'
    r'|ref(?:erence)?\s*(?:id|no|number)'
    r'|order\s*id)'
    r'\s*[:#\-]?\s*([A-Za-z0-9]{8,30})',
    caseSensitive: false,
  );

  // Unlabelled fallbacks: a PhonePe-style "T" + 12–22 digits, or a bare 12–22
  // digit run. These lengths are ID territory — far longer than any amount.
  static final _phonePeIdRe = RegExp(r'\bT\d{12,22}\b', caseSensitive: false);
  static final _longDigitsRe = RegExp(r'\b\d{12,22}\b');

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
      transactionId: _transactionId(text),
    );
  }

  // ─────────────────────────── amount ───────────────────────────

  /// Parses a token into a money amount the ₹ input accepts, or **null** if the
  /// token is not a plausible amount. This is the guard rail that stops a
  /// Transaction ID / UTR from ever becoming the amount. Rejects:
  ///   • anything that isn't a plain decimal number (so "T2607…" / alphanumeric
  ///     IDs never pass),
  ///   • more than 2 decimal places,
  ///   • more than 9 total digits (a real receipt amount is < 100 crore; IDs
  ///     are 12–22 digits),
  ///   • non-finite / scientific-notation / non-positive results.
  /// On success returns the value rounded to paise (≤ 2 decimals).
  static double? parseAmount(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Drop currency symbols/words and thousands separators / spaces.
    s = s.replaceAll(RegExp(r'(?:₹|rs\.?|inr)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[,\s]'), '');
    // Only a plain decimal number is acceptable — this single check rejects any
    // token containing letters (IDs like "T2607251037436024") or extra dots.
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(s)) return null;
    // Digit-count ceiling: IDs are long, amounts are not.
    final digits = s.replaceAll('.', '');
    if (digits.length > 9) return null;
    final v = double.tryParse(s);
    if (v == null || !v.isFinite || v <= 0) return null;
    final rounded = double.parse(v.toStringAsFixed(2));
    if (!rounded.isFinite || rounded <= 0 || rounded >= 1000000000) return null;
    return rounded;
  }

  /// Finds the amount by CONTEXT, not by size. Priority:
  ///   1. a ₹/Rs/INR-tagged value on an amount/paid/total line,
  ///   2. any ₹/Rs/INR-tagged value anywhere,
  ///   3. a plain number on an amount/paid/total line that is NOT a
  ///      reference/ID line.
  /// Every candidate must pass [parseAmount]. There is deliberately NO
  /// "largest bare number" fallback (that was the bug) — if nothing matches with
  /// context, we return null and the screen leaves the field blank with a hint.
  static double? _amount(String text) {
    double? labelledCurrency;
    double? anyCurrency;
    double? labelledPlain;

    for (final line in text.split('\n')) {
      final low = line.toLowerCase();
      final amountCtx = low.contains('total') ||
          low.contains('grand') ||
          low.contains('amount') ||
          low.contains('paid') ||
          low.contains('received') ||
          low.contains('debited') ||
          low.contains('credited');
      final idCtx = _looksLikeIdLine(low);

      for (final m in _currencyRe.allMatches(line)) {
        final v = parseAmount(m.group(1));
        if (v == null) continue;
        if (anyCurrency == null || v > anyCurrency) anyCurrency = v;
        labelledCurrency ??= amountCtx ? v : null;
      }

      // Plain (untagged) numbers are trusted ONLY on an amount line that isn't
      // also a reference/ID line — so "Txn No 2607…" never yields an amount.
      if (amountCtx && !idCtx) {
        for (final m in _amountRe.allMatches(line)) {
          final v = parseAmount(m.group(1));
          if (v == null) continue;
          labelledPlain ??= v;
        }
      }
    }
    return labelledCurrency ?? anyCurrency ?? labelledPlain;
  }

  static bool _looksLikeIdLine(String low) =>
      low.contains('transaction id') ||
      low.contains('transaction no') ||
      low.contains('txn') ||
      low.contains('utr') ||
      low.contains('ref') ||
      low.contains('order id') ||
      low.contains('upi');

  // ─────────────────────────── transaction id ───────────────────────────

  /// Extracts a payment reference code as a STRING, exactly as printed — never
  /// numeric, never with a decimal inserted. Prefers a labelled code; falls
  /// back to a PhonePe-style `T…` code or a long (12–22) digit run.
  static String? _transactionId(String text) {
    final labelled = _txnIdLabelRe.firstMatch(text);
    if (labelled != null) return labelled.group(1);
    final phonePe = _phonePeIdRe.firstMatch(text);
    if (phonePe != null) return phonePe.group(0);
    final longRun = _longDigitsRe.firstMatch(text);
    return longRun?.group(0);
  }

  // ─────────────────────────── gstin / date / vendor ───────────────────────────

  static String? _gst(String text) {
    final m = _gstRe.firstMatch(text);
    return m?.group(1)?.toUpperCase();
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
