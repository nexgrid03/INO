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
    this.transactionId,
    this.direction,
  });

  /// A validated money amount ([ReceiptParser.parseAmount]) — never an ID read
  /// as a number. Null when no amount could be confidently read (the screen
  /// then leaves the field blank with a "enter manually" hint).
  final double? amount;
  final DateTime? date;
  final String? vendorName;

  /// A GSTIN parsed from the receipt.
  final String? gstNumber;

  /// A payment reference code (Transaction ID / UTR), kept verbatim as a string
  /// — offered for the Transaction ID field, never the amount.
  final String? transactionId;

  /// The money direction inferred from the receipt text (e.g. a bank SMS/UPI
  /// screenshot saying "debited" / "credited"), or null when ambiguous.
  final TransactionDirection? direction;

  bool get isEmpty =>
      amount == null &&
      date == null &&
      vendorName == null &&
      gstNumber == null &&
      transactionId == null &&
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
  ///
  /// Uses the OCR engine's **textOnly** mode: a receipt only needs the raw text
  /// (re-parsed below with regex), so this runs a single downscaled recognition
  /// pass and skips the enhanced/binarized image passes — the measured
  /// multi-second bottleneck — that exist only to rescue ID-card field
  /// extraction. Results are cached by the engine, so re-opening the same image
  /// returns instantly.
  Future<ReceiptScanResult> scan(String path) async {
    final extraction =
        await OcrService.instance.extract(path, textOnly: true);
    final text = extraction.rawText;
    final data = ReceiptParser.parse(text);
    return ReceiptScanResult(
      amount: data.amount,
      date: data.date,
      vendorName: data.vendorName,
      gstNumber: data.gstNumber,
      transactionId: data.transactionId,
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
