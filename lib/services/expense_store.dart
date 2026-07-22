import 'package:flutter/foundation.dart';

import '../models/expense_models.dart';

/// The single source of truth for the ITR-ready Transaction Vault.
///
/// A notify-on-change **repository** (in-memory today, Supabase-ready tomorrow —
/// the models already carry stable ids + receipt paths). It records
/// transactions and tax documents organised by financial year, and derives a
/// tax summary. **No sample data** — a new account starts completely empty.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore._();
  static final ExpenseStore instance = ExpenseStore._();

  final List<TransactionRecord> _txns = [];
  final List<TaxDocument> _taxDocs = [];
  FinancialYear _selectedYear = FinancialYear.current();
  int _seq = 0;

  // ---- Financial year ------------------------------------------------------

  FinancialYear get selectedYear => _selectedYear;

  void setSelectedYear(FinancialYear fy) {
    if (fy == _selectedYear) return;
    _selectedYear = fy;
    notifyListeners();
  }

  /// Years that have data, plus the current year, newest first.
  List<FinancialYear> get availableYears {
    final years = <int>{
      FinancialYear.current().startYear,
      _selectedYear.startYear,
      for (final t in _txns) FinancialYear.of(t.dateTime).startYear,
      for (final d in _taxDocs) d.financialYearStart,
    };
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return [for (final y in sorted) FinancialYear(y)];
  }

  // ---- Transactions --------------------------------------------------------

  /// All transactions in [fy] (defaults to the selected year), newest first.
  List<TransactionRecord> transactionsForYear([FinancialYear? fy]) {
    final year = fy ?? _selectedYear;
    final list = _txns.where((t) => year.contains(t.dateTime)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return List.unmodifiable(list);
  }

  /// Search within [fy] by description, Transaction ID, vendor, amount or date.
  List<TransactionRecord> searchTransactions(String query, [FinancialYear? fy]) {
    final base = transactionsForYear(fy);
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((t) {
      final amount = t.amount.toStringAsFixed(0);
      final date = _searchableDate(t.dateTime);
      final hay = '${t.description} ${t.reference ?? ''} ${t.vendorName ?? ''} '
              '$amount ${t.category.label} $date'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  bool get isEmpty => _txns.isEmpty;
  int countForYear([FinancialYear? fy]) => transactionsForYear(fy).length;
  double totalForYear([FinancialYear? fy]) =>
      transactionsForYear(fy).fold(0.0, (s, t) => s + t.amount);

  TransactionRecord? byId(String id) {
    for (final t in _txns) {
      if (t.id == id) return t;
    }
    return null;
  }

  TransactionRecord add({
    required String description,
    required double amount,
    required DateTime dateTime,
    required TransactionType type,
    required TxnCategory category,
    String? reference,
    double? gstAmount,
    String? vendorName,
    PaymentMethod? paymentMethod,
    String? note,
    String? receiptPath,
    bool receiptIsPdf = false,
  }) {
    final t = TransactionRecord(
      id: _newId('txn'),
      description: description,
      amount: amount,
      dateTime: dateTime,
      type: type,
      category: category,
      reference: reference,
      gstAmount: gstAmount,
      vendorName: vendorName,
      paymentMethod: paymentMethod,
      note: note,
      receiptPath: receiptPath,
      receiptIsPdf: receiptIsPdf,
    );
    _txns.add(t);
    notifyListeners();
    return t;
  }

  void update(TransactionRecord updated) {
    final i = _txns.indexWhere((t) => t.id == updated.id);
    if (i == -1) return;
    _txns[i] = updated;
    notifyListeners();
  }

  void remove(String id) {
    _txns.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  // ---- Tax document vault --------------------------------------------------

  /// Tax documents filed under [fy] (defaults to the selected year).
  List<TaxDocument> taxDocumentsForYear([FinancialYear? fy]) {
    final year = fy ?? _selectedYear;
    final list = _taxDocs
        .where((d) => d.financialYearStart == year.startYear)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return List.unmodifiable(list);
  }

  List<TaxDocument> taxDocumentsOfType(TaxDocType type, [FinancialYear? fy]) =>
      taxDocumentsForYear(fy).where((d) => d.type == type).toList();

  TaxDocument addTaxDocument({
    required TaxDocType type,
    required String fileName,
    required String filePath,
    required bool isPdf,
    FinancialYear? fy,
  }) {
    final year = fy ?? _selectedYear;
    final d = TaxDocument(
      id: _newId('tax'),
      type: type,
      fileName: fileName,
      filePath: filePath,
      isPdf: isPdf,
      addedAt: DateTime.now(),
      financialYearStart: year.startYear,
    );
    _taxDocs.add(d);
    notifyListeners();
    return d;
  }

  void removeTaxDocument(String id) {
    _taxDocs.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  // ---- Tax summary (ITR export) --------------------------------------------

  TaxSummary taxSummary([FinancialYear? fy]) {
    final year = fy ?? _selectedYear;
    final inYear = _txns.where((t) => year.contains(t.dateTime));
    double sum(bool Function(TransactionRecord) test) =>
        inYear.where(test).fold(0.0, (s, t) => s + t.amount);
    return TaxSummary(
      year: year,
      totalIncome: sum((t) => t.isIncome),
      totalExpenses: sum((t) => !t.isIncome),
      totalInvestments: sum((t) => t.category == TxnCategory.investment),
      insurancePremiums: sum((t) => t.category == TxnCategory.insurance),
      medicalExpenses: sum((t) => t.category == TxnCategory.medical),
      rentPaid: sum((t) => t.category == TxnCategory.rent && !t.isIncome),
      taxPaid: sum((t) => t.category == TxnCategory.taxPayment),
      transactionCount: inYear.length,
    );
  }

  // ---- Lifecycle -----------------------------------------------------------

  /// Clears all vault state — called on sign-out (SessionReset) so a new
  /// account never sees the previous user's records.
  void clear() {
    _txns.clear();
    _taxDocs.clear();
    _selectedYear = FinancialYear.current();
    notifyListeners();
  }

  @visibleForTesting
  void reset() => clear();

  String _newId(String prefix) =>
      '${prefix}_${_seq++}_${DateTime.now().microsecondsSinceEpoch}';

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  String _searchableDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year} '
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
