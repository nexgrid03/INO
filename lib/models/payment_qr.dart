/// Parsing for scanned QR codes, and specifically for the **payment** QRs this
/// app has to recognise before it can offer "open with Google Pay / PhonePe /…".
///
/// Two payment encodings matter in India and both are handled here:
///
///  1. **UPI deep links** - `upi://pay?pa=<vpa>&pn=<name>&am=<amount>&cu=INR`.
///     This is what a personal "my UPI QR" (the kind saved in Home → My QR)
///     contains, and what every UPI app understands.
///
///  2. **EMVCo / BharatQR** - the numeric TLV blob printed on most *merchant*
///     standees. It is not a URI at all; the VPA is buried in a nested
///     tag-length-value structure. Shop counters overwhelmingly use this form,
///     so ignoring it would mean the feature only ever worked on personal QRs.
///     [PaymentQrParser] pulls the VPA/name/amount out and rebuilds a canonical
///     `upi://pay` URI from them.
///
/// Everything is normalised to a `upi://pay` URI on the way out. That is the
/// point: a QR minted by one app (`gpay://`, `phonepe://`, …) must still be
/// payable with whichever app the user actually chooses, so app-specific
/// schemes are rewritten rather than passed through.
library;

/// What a scanned QR turned out to be, which decides what the scanner does next.
enum ScannedQrKind {
  /// A UPI/BharatQR payment request → offer the payment-app picker.
  payment,

  /// An INO secure-share link (`/s/<token>` or `/v/<token>`) → open in-app.
  inoShare,

  /// Any other http(s) link → offer to open it in the browser.
  link,

  /// Anything else (plain text, an unknown scheme) → show it, offer to copy.
  text,
}

/// A scanned QR, classified. [payment] is non-null exactly when [kind] is
/// [ScannedQrKind.payment].
class ScannedQr {
  const ScannedQr({required this.raw, required this.kind, this.payment});

  /// The exact string decoded from the QR, untouched.
  final String raw;

  final ScannedQrKind kind;

  /// The parsed payment request, when this is a payment QR.
  final PaymentRequest? payment;

  bool get isPayment => kind == ScannedQrKind.payment;

  /// Classifies [raw]. Payment detection runs FIRST, because a BharatQR blob is
  /// otherwise indistinguishable from junk text and a `upi://` URI would
  /// otherwise fall through to the generic-link branch.
  static ScannedQr classify(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return ScannedQr(raw: raw, kind: ScannedQrKind.text);

    final payment = PaymentQrParser.parse(value);
    if (payment != null) {
      return ScannedQr(
          raw: value, kind: ScannedQrKind.payment, payment: payment);
    }

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      // `/s/<token>` and `/v/<token>` are INO's own share links - those belong
      // in the in-app viewer, not a browser.
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final i = segs.lastIndexOf('s') >= 0 ? segs.lastIndexOf('s') : -1;
      final v = segs.lastIndexOf('v');
      final isShare = (i >= 0 && i + 1 < segs.length) ||
          (v >= 0 && v + 1 < segs.length);
      return ScannedQr(
        raw: value,
        kind: isShare ? ScannedQrKind.inoShare : ScannedQrKind.link,
      );
    }
    if (uri != null && uri.scheme == 'ino') {
      return ScannedQr(raw: value, kind: ScannedQrKind.inoShare);
    }
    return ScannedQr(raw: value, kind: ScannedQrKind.text);
  }
}

/// A payment request extracted from a QR, normalised to UPI terms.
class PaymentRequest {
  const PaymentRequest({
    required this.payeeAddress,
    required this.uri,
    this.payeeName,
    this.amount,
    this.currency,
    this.note,
    this.merchantCode,
    this.transactionRef,
  });

  /// The payee VPA (`pa`), e.g. `merchant@okhdfcbank`. Always non-empty - a
  /// request without one is not a payment request and is never constructed.
  final String payeeAddress;

  /// The canonical `upi://pay?…` URI handed to whichever app the user picks.
  /// Rebuilt by the parser rather than echoed, so an app-specific source scheme
  /// can still be paid with a different app.
  final String uri;

  /// Payee display name (`pn`), when the QR carries one.
  final String? payeeName;

  /// The requested amount (`am`) as it appeared, e.g. `"250.00"`. Null for an
  /// open QR where the payer types the amount in their UPI app.
  final String? amount;

  /// Currency code (`cu`), normally `INR`.
  final String? currency;

  /// Free-text note / transaction description (`tn`).
  final String? note;

  /// Merchant category code (`mc`) - present on merchant QRs, absent on
  /// person-to-person ones.
  final String? merchantCode;

  /// Transaction reference (`tr`), used by merchants to reconcile a payment.
  final String? transactionRef;

  /// [amount] as a number, or null when the QR left the amount open (or carried
  /// something unparseable).
  double? get amountValue {
    final a = amount;
    if (a == null || a.isEmpty) return null;
    return double.tryParse(a);
  }

  /// True when the payer chooses the amount themselves in their UPI app.
  bool get isOpenAmount => amountValue == null;

  /// True when this looks like a merchant (rather than person-to-person) QR.
  bool get isMerchant =>
      (merchantCode != null && merchantCode!.isNotEmpty) ||
      (transactionRef != null && transactionRef!.isNotEmpty);

  /// What to show as the payee: the name when present, else the VPA.
  String get displayName =>
      (payeeName != null && payeeName!.trim().isNotEmpty)
          ? payeeName!.trim()
          : payeeAddress;
}

/// Turns a raw QR payload into a [PaymentRequest], or null when it isn't a
/// payment QR at all.
class PaymentQrParser {
  PaymentQrParser._();

  /// URI schemes that carry UPI payment parameters. `upi` is the standard;
  /// the rest are app-specific QRs that still hold the same `pa`/`pn`/`am`
  /// query, so they are accepted and rewritten to `upi://pay`.
  static const Set<String> _upiSchemes = {
    'upi',
    'gpay', 'tez', // Google Pay
    'phonepe',
    'paytmmp', 'paytm',
    'bhim',
    'credpay',
  };

  /// The query keys UPI defines. Anything else in the source QR is dropped when
  /// the canonical URI is rebuilt, so a hostile QR can't smuggle extra
  /// parameters into the payment app.
  static const List<String> _passThroughKeys = [
    'pa', 'pn', 'am', 'mam', 'cu', 'tn', 'mc', 'tid', 'tr', 'url', 'mode',
    'orgid', 'sign',
  ];

  /// Parses [raw], returning null when it is not a payment QR.
  static PaymentRequest? parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return _parseUpiUri(value) ?? _parseEmvCo(value);
  }

  // ---- UPI deep links -------------------------------------------------------

  static PaymentRequest? _parseUpiUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (!_upiSchemes.contains(uri.scheme.toLowerCase())) return null;

    // `upi://pay?…`, `gpay://upi/pay?…` and `phonepe://pay?…` all put the
    // parameters in the query, so the host/path only has to look like a pay
    // action - not match exactly.
    final target = '${uri.host}/${uri.path}'.toLowerCase();
    final looksLikePay =
        target.contains('pay') || uri.queryParameters.containsKey('pa');
    if (!looksLikePay) return null;

    final q = uri.queryParameters;
    final pa = (q['pa'] ?? '').trim();
    if (!_isPlausibleVpa(pa)) return null;

    return _build(
      payeeAddress: pa,
      payeeName: q['pn'],
      amount: q['am'],
      currency: q['cu'],
      note: q['tn'],
      merchantCode: q['mc'],
      transactionRef: q['tr'],
      extra: {
        for (final k in _passThroughKeys)
          if (k != 'pa' && q[k] != null && q[k]!.isNotEmpty) k: q[k]!,
      },
    );
  }

  /// A VPA is `handle@provider`. Deliberately loose - providers keep adding new
  /// handles - but strict enough that arbitrary text can't masquerade as one.
  static bool _isPlausibleVpa(String vpa) {
    if (vpa.isEmpty || vpa.length > 255) return false;
    final at = vpa.indexOf('@');
    if (at <= 0 || at != vpa.lastIndexOf('@')) return false;
    if (at == vpa.length - 1) return false;
    return RegExp(r'^[A-Za-z0-9._\-]+@[A-Za-z0-9.\-]+$').hasMatch(vpa);
  }

  // ---- EMVCo / BharatQR -----------------------------------------------------

  /// EMVCo QRs are a flat run of `IILLvalue` triples: a 2-digit id, a 2-digit
  /// length, then that many characters. They always begin with `000201`
  /// (payload format indicator `01`).
  ///
  /// The UPI VPA lives inside one of the "merchant account information"
  /// templates (ids 26-51), which is itself a run of TLVs where sub-id `00` is
  /// the scheme name (`upi`) and sub-id `01` is the address.
  static PaymentRequest? _parseEmvCo(String value) {
    if (!value.startsWith('0002')) return null;
    final root = _readTlv(value);
    if (root.isEmpty) return null;

    String? vpa;
    for (var id = 26; id <= 51 && vpa == null; id++) {
      final template = root[id.toString().padLeft(2, '0')];
      if (template == null) continue;
      final sub = _readTlv(template);
      final guid = (sub['00'] ?? '').toLowerCase();
      final address = sub['01'];
      // Accept the template when it declares itself UPI, or when its address
      // sub-tag simply looks like a VPA (some issuers omit the GUID).
      if (address != null &&
          (guid == 'upi' || _isPlausibleVpa(address.trim()))) {
        if (_isPlausibleVpa(address.trim())) vpa = address.trim();
      }
    }
    if (vpa == null) return null;

    // 53 is a numeric ISO-4217 code; UPI wants the alphabetic one.
    final currency = switch (root['53']) {
      '356' => 'INR',
      null => null,
      _ => null,
    };
    final amount = root['54'];

    return _build(
      payeeAddress: vpa,
      payeeName: root['59'],
      amount: amount != null && amount.isNotEmpty ? amount : null,
      currency: currency ?? 'INR',
      // 62 is "additional data"; sub-tag 08 is the human-readable purpose.
      note: root['62'] != null ? _readTlv(root['62']!)['08'] : null,
      merchantCode: root['52'],
      transactionRef: root['62'] != null ? _readTlv(root['62']!)['05'] : null,
      extra: const {},
    );
  }

  /// Reads one level of EMVCo tag-length-value pairs into `{id: value}`.
  /// Returns an empty map on any malformed length, rather than guessing.
  static Map<String, String> _readTlv(String data) {
    final out = <String, String>{};
    var i = 0;
    while (i + 4 <= data.length) {
      final id = data.substring(i, i + 2);
      final lenText = data.substring(i + 2, i + 4);
      final len = int.tryParse(lenText);
      if (len == null || len < 0) return out;
      final start = i + 4;
      final end = start + len;
      if (end > data.length) return out;
      out[id] = data.substring(start, end);
      i = end;
    }
    return out;
  }

  // ---- Canonical URI --------------------------------------------------------

  static PaymentRequest _build({
    required String payeeAddress,
    required Map<String, String> extra,
    String? payeeName,
    String? amount,
    String? currency,
    String? note,
    String? merchantCode,
    String? transactionRef,
  }) {
    String? clean(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final name = clean(payeeName);
    final amt = clean(amount);
    final cur = clean(currency) ?? 'INR';
    final tn = clean(note);
    final mc = clean(merchantCode);
    final tr = clean(transactionRef);

    // Rebuild rather than echo, so an app-specific scheme becomes payable by
    // ANY UPI app and unknown query keys are dropped.
    final params = <String, String>{
      ...extra,
      'pa': payeeAddress,
      'pn': ?name,
      'am': ?amt,
      'cu': cur,
      'tn': ?tn,
      'mc': ?mc,
      'tr': ?tr,
    };

    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: params,
    ).toString();

    return PaymentRequest(
      payeeAddress: payeeAddress,
      uri: uri,
      payeeName: name,
      amount: amt,
      currency: cur,
      note: tn,
      merchantCode: mc,
      transactionRef: tr,
    );
  }
}
