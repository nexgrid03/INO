import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/expense_repository.dart';
import '../models/expense_models.dart';

/// The single source of truth for the ITR-ready Transaction Vault.
///
/// A notify-on-change **store** backed by Supabase (`public.expenses` +
/// `public.tax_documents` via [ExpenseRepository] — see
/// supabase/migrations/20260724000000_notes_expenses.sql). Mutations are
/// optimistic: the UI updates instantly and the write is persisted in the
/// background (the ReminderStore pattern), with the DB-generated id swapped in
/// once the insert lands. When nobody is signed in (tests / signed-out
/// browsing) it works purely in memory, exactly as before.
///
/// It records transactions and tax documents organised by financial year, and
/// derives a tax summary. **No sample data** — a new account starts empty.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore._();
  static final ExpenseStore instance = ExpenseStore._();

  final List<TransactionRecord> _txns = [];
  final List<TaxDocument> _taxDocs = [];
  FinancialYear _selectedYear = FinancialYear.current();
  int _seq = 0;

  bool _loaded = false;
  bool _loading = false;
  String? _loadError;

  /// True while the first load (or a [reload]) is in flight.
  bool get isLoading => _loading;

  /// True once a load has completed (even an empty or failed one).
  bool get isLoaded => _loaded;

  /// Human-readable message when the last load failed (offline, …), else null.
  String? get loadError => _loadError;

  /// The signed-in user's id, or null (tests / signed out). Defensive: reading
  /// Supabase before init throws, so we treat any failure as "no user".
  String? _uid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool get _remote => _uid() != null;

  // ---- Hydration -------------------------------------------------------------

  /// Hydrates the vault from Supabase once. Safe to call from every screen's
  /// `initState`. Signed out → stays empty (in-memory only).
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await _load();
  }

  /// Pull-to-refresh: re-hydrates from the backend.
  Future<void> reload() async {
    if (_loading) return;
    await _load();
  }

  Future<void> _load() async {
    if (!_remote) {
      // Tests / signed out: nothing to fetch; the in-memory list is the truth.
      _loaded = true;
      return;
    }
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final data = await ExpenseRepository.instance.load();
      _txns
        ..clear()
        ..addAll(data.transactions);
      _taxDocs
        ..clear()
        ..addAll(data.taxDocuments);
    } catch (e) {
      debugPrint('Expenses load failed: $e');
      _loadError = 'Couldn\'t load your transactions. Check your connection.';
    }
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

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

  /// All transactions in calendar month [month] of [year], newest first.
  List<TransactionRecord> transactionsForMonth(int year, int month) {
    final list = _txns
        .where((t) => t.dateTime.year == year && t.dateTime.month == month)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return List.unmodifiable(list);
  }

  /// Transactions in [fy] filed under [category], newest first.
  List<TransactionRecord> transactionsForCategory(TxnCategory category,
          [FinancialYear? fy]) =>
      transactionsForYear(fy).where((t) => t.category == category).toList();

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

  // ---- Analytics -----------------------------------------------------------

  /// Total spent (or received, with [type]) in calendar month [month]/[year].
  double monthlyTotal(int year, int month,
          {TransactionType type = TransactionType.expense}) =>
      transactionsForMonth(year, month)
          .where((t) => t.type == type)
          .fold(0.0, (s, t) => s + t.amount);

  /// Total spent (or received, with [type]) in calendar year [year].
  double yearlyTotal(int year,
          {TransactionType type = TransactionType.expense}) =>
      _txns
          .where((t) => t.dateTime.year == year && t.type == type)
          .fold(0.0, (s, t) => s + t.amount);

  /// Per-category totals for [fy] (defaults to the selected year), restricted
  /// to [type], sorted by amount descending. Categories with no spend are
  /// omitted.
  Map<TxnCategory, double> categoryBreakdown(
      {FinancialYear? fy, TransactionType type = TransactionType.expense}) {
    final totals = <TxnCategory, double>{};
    for (final t in transactionsForYear(fy)) {
      if (t.type != type) continue;
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

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
    // Optimistically show it, then insert to Supabase and swap in the real id.
    _txns.add(t);
    notifyListeners();
    if (_remote) {
      unawaited(ExpenseRepository.instance.addTransaction(t).then((saved) {
        final i = _txns.indexWhere((e) => e.id == t.id);
        if (i != -1) {
          _txns[i] = saved;
          notifyListeners();
        }
        debugPrint('Expense saved: ${saved.id}');
      }).catchError((Object e) {
        debugPrint('Expense save failed: $e');
      }));
    }
    return t;
  }

  void update(TransactionRecord updated) {
    final i = _txns.indexWhere((t) => t.id == updated.id);
    if (i == -1) return;
    _txns[i] = updated;
    notifyListeners();
    if (_remote) {
      unawaited(
          ExpenseRepository.instance.updateTransaction(updated).catchError(
        (Object e) {
          debugPrint('Expense update failed: $e');
        },
      ));
    }
  }

  void remove(String id) {
    _txns.removeWhere((t) => t.id == id);
    notifyListeners();
    if (_remote) {
      unawaited(ExpenseRepository.instance.removeTransaction(id).catchError(
        (Object e) {
          debugPrint('Expense delete failed: $e');
        },
      ));
    }
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
    if (_remote) {
      unawaited(ExpenseRepository.instance.addTaxDocument(d).then((saved) {
        final i = _taxDocs.indexWhere((e) => e.id == d.id);
        if (i != -1) {
          _taxDocs[i] = saved;
          notifyListeners();
        }
      }).catchError((Object e) {
        debugPrint('Tax document save failed: $e');
      }));
    }
    return d;
  }

  void removeTaxDocument(String id) {
    _taxDocs.removeWhere((d) => d.id == id);
    notifyListeners();
    if (_remote) {
      unawaited(ExpenseRepository.instance.removeTaxDocument(id).catchError(
        (Object e) {
          debugPrint('Tax document delete failed: $e');
        },
      ));
    }
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
  /// account never sees the previous user's records. The next [ensureLoaded]
  /// re-hydrates from Supabase for whoever signs in next (RLS-scoped).
  void clear() {
    _txns.clear();
    _taxDocs.clear();
    _selectedYear = FinancialYear.current();
    _loaded = false;
    _loading = false;
    _loadError = null;
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
