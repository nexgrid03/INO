import '../models/expense_models.dart';
import 'ocr_service.dart';
import 'receipt_parser.dart';

/// Everything a receipt scan can suggest for the Add Transaction form. Every
/// field is nullable — OCR only ever *suggests*, so the screen fills whatever
/// came back and leaves the rest to the user.
class ReceiptScanResult {
  const ReceiptScanResult({
    this.amount,
    this.date,
    this.vendorName,
    this.gstNumber,
    this.direction,
  });

  final double? amount;
  final DateTime? date;
  final String? vendorName;

  /// A GSTIN parsed from the receipt, offered as the Transaction ID.
  final String? gstNumber;

  /// The money direction inferred from the receipt text (e.g. a bank SMS/UPI
  /// screenshot saying "debited" / "credited"), or null when ambiguous.
  final TransactionDirection? direction;

  bool get isEmpty =>
      amount == null &&
      date == null &&
      vendorName == null &&
      gstNumber == null &&
      direction == null;

  static const empty = ReceiptScanResult();
}

/// The one reusable place that turns a receipt/screenshot file into structured
/// form suggestions — the equivalent of a `useReceiptScan()` hook.
///
/// It runs the existing on-device OCR ([OcrService], ML Kit — no cloud/API key
/// needed) and the existing regex extractor ([ReceiptParser]) for
/// amount/date/vendor/GSTIN, then adds a light direction inference from the raw
/// text. All parsing is defensive: a scan that reads nothing returns
/// [ReceiptScanResult.empty] and never throws, so the caller can fall back to
/// manual entry.
class ReceiptScanService {
  ReceiptScanService._();
  static final ReceiptScanService instance = ReceiptScanService._();

  /// Scans the image at [path] and returns structured suggestions. Throws only
  /// on an OCR engine failure (caught by the caller to show the "couldn't read
  /// the receipt" toast); an unreadable-but-successful scan returns empty.
  Future<ReceiptScanResult> scan(String path) async {
    final extraction = await OcrService.instance.extract(path);
    final text = extraction.rawText;
    final data = ReceiptParser.parse(text);
    return ReceiptScanResult(
      amount: data.amount,
      date: data.date,
      vendorName: data.vendorName,
      gstNumber: data.gstNumber,
      direction: _inferDirection(text),
    );
  }

  /// Infers credited vs. debited from bank/UPI receipt wording. Conservative —
  /// returns null unless one direction clearly dominates, so it never
  /// overrides the user's context-based default on a guess.
  static TransactionDirection? _inferDirection(String text) {
    final t = text.toLowerCase();
    const creditWords = [
      'credited',
      'credit',
      'received',
      'deposit',
      'refund',
      'money in',
    ];
    const debitWords = [
      'debited',
      'debit',
      'paid',
      'sent',
      'withdrawn',
      'purchase',
      'money out',
    ];
    var credit = 0;
    var debit = 0;
    for (final w in creditWords) {
      if (t.contains(w)) credit++;
    }
    for (final w in debitWords) {
      if (t.contains(w)) debit++;
    }
    if (credit > debit) return TransactionDirection.credited;
    if (debit > credit) return TransactionDirection.debited;
    return null; // ambiguous → let the type-based default stand
  }
}
