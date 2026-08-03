import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

// Models backing the ITR-ready Transaction Vault - a record + receipt store
// organised by financial year, with a tax-document vault and a tax summary.
//
// UI-agnostic plain objects so the in-memory store can be swapped for a
// Supabase-backed repository later without touching a widget. NO sample data -
// a new account starts completely empty.

// ---------------------------------------------------------------------------
// Financial year (Indian: 1 Apr – 31 Mar)
// ---------------------------------------------------------------------------

/// An Indian financial year, identified by its starting calendar year
/// (2026 → "2026-27", running 1 Apr 2026 → 31 Mar 2027).
class FinancialYear {
  const FinancialYear(this.startYear);

  final int startYear;

  factory FinancialYear.of(DateTime d) =>
      d.month >= 4 ? FinancialYear(d.year) : FinancialYear(d.year - 1);

  factory FinancialYear.current() => FinancialYear.of(DateTime.now());

  /// "2026-27".
  String get label =>
      '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';

  DateTime get start => DateTime(startYear, 4, 1);
  DateTime get end => DateTime(startYear + 1, 3, 31, 23, 59, 59);

  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

  FinancialYear get previous => FinancialYear(startYear - 1);
  FinancialYear get next => FinancialYear(startYear + 1);

  @override
  bool operator ==(Object other) =>
      other is FinancialYear && other.startYear == startYear;

  @override
  int get hashCode => startYear.hashCode;
}

// ---------------------------------------------------------------------------
// Transaction type + category
// ---------------------------------------------------------------------------

enum TransactionType { expense, income }

extension TransactionTypeX on TransactionType {
  String get labelKey =>
      this == TransactionType.income ? 'income' : 'expense';

  String label(AppLocalizations l10n) => l10n.t(labelKey);

  bool get isIncome => this == TransactionType.income;

  static TransactionType fromName(String? name) => name == 'income'
      ? TransactionType.income
      : TransactionType.expense;
}

/// Money direction - whether funds left the account ([debited]) or arrived
/// ([credited]). Stored alongside [TransactionType]; when absent on an older
/// record it is derived from the type (income → credited, expense → debited),
/// so pre-existing transactions keep working unchanged.
enum TransactionDirection { debited, credited }

extension TransactionDirectionX on TransactionDirection {
  String get labelKey =>
      this == TransactionDirection.credited ? 'credited' : 'debited';

  String label(AppLocalizations l10n) => l10n.t(labelKey);

  bool get isCredited => this == TransactionDirection.credited;

  /// The natural default for a [TransactionType]: income is money in
  /// (credited), an expense is money out (debited).
  static TransactionDirection defaultFor(TransactionType type) =>
      type.isIncome ? TransactionDirection.credited : TransactionDirection.debited;

  static TransactionDirection? fromName(String? name) {
    if (name == 'credited') return TransactionDirection.credited;
    if (name == 'debited') return TransactionDirection.debited;
    return null;
  }
}

/// ITR-oriented transaction categories.
enum TxnCategory {
  salary,
  business,
  investment,
  rent,
  insurance,
  medical,
  education,
  travel,
  food,
  shopping,
  utilities,
  loanEmi,
  taxPayment,
  other,
}

extension TxnCategoryX on TxnCategory {
  static TxnCategory fromName(String? name) => TxnCategory.values.firstWhere(
        (c) => c.name == name,
        orElse: () => TxnCategory.other,
      );

  String get labelKey {
    switch (this) {
      case TxnCategory.salary:
        return 'catSalary';
      case TxnCategory.business:
        return 'catBusiness';
      case TxnCategory.investment:
        return 'catInvestment';
      case TxnCategory.rent:
        return 'catRent';
      case TxnCategory.insurance:
        return 'catInsurance';
      case TxnCategory.medical:
        return 'catMedical';
      case TxnCategory.education:
        return 'catEducation';
      case TxnCategory.travel:
        return 'catTravel';
      case TxnCategory.food:
        return 'catFood';
      case TxnCategory.shopping:
        return 'catShopping';
      case TxnCategory.utilities:
        return 'catUtilities';
      case TxnCategory.loanEmi:
        return 'catLoanEmi';
      case TxnCategory.taxPayment:
        return 'catTaxPayment';
      case TxnCategory.other:
        return 'catOther';
    }
  }

  String label(AppLocalizations l10n) => l10n.t(labelKey);

  IconData get icon {
    switch (this) {
      case TxnCategory.salary:
        return Icons.payments_rounded;
      case TxnCategory.business:
        return Icons.storefront_rounded;
      case TxnCategory.investment:
        return Icons.trending_up_rounded;
      case TxnCategory.rent:
        return Icons.home_rounded;
      case TxnCategory.insurance:
        return Icons.shield_rounded;
      case TxnCategory.medical:
        return Icons.favorite_rounded;
      case TxnCategory.education:
        return Icons.school_rounded;
      case TxnCategory.travel:
        return Icons.flight_takeoff_rounded;
      case TxnCategory.food:
        return Icons.restaurant_rounded;
      case TxnCategory.shopping:
        return Icons.shopping_bag_rounded;
      case TxnCategory.utilities:
        return Icons.receipt_long_rounded;
      case TxnCategory.loanEmi:
        return Icons.account_balance_rounded;
      case TxnCategory.taxPayment:
        return Icons.gavel_rounded;
      case TxnCategory.other:
        return Icons.category_rounded;
    }
  }

  Color get color {
    switch (this) {
      case TxnCategory.salary:
        return AppColors.skyBrand;
      case TxnCategory.business:
        return AppColors.skyBrandSecondary;
      case TxnCategory.investment:
        return const Color(0xFF0EA5E9);
      case TxnCategory.rent:
        return const Color(0xFF8B6CEF);
      case TxnCategory.insurance:
        return const Color(0xFFE0A100);
      case TxnCategory.medical:
        return const Color(0xFFEC6A8C);
      case TxnCategory.education:
        return const Color(0xFF3B82F6);
      case TxnCategory.travel:
        return const Color(0xFF06B6D4);
      case TxnCategory.food:
        return const Color(0xFFF5704A);
      case TxnCategory.shopping:
        return const Color(0xFFEC4899);
      case TxnCategory.utilities:
        return AppColors.skyBrandSecondary;
      case TxnCategory.loanEmi:
        return const Color(0xFF6366F1);
      case TxnCategory.taxPayment:
        return AppColors.critical;
      case TxnCategory.other:
        return const Color(0xFF64748B);
    }
  }
}

// ---------------------------------------------------------------------------
// Payment method
// ---------------------------------------------------------------------------

/// How a transaction was paid / received.
enum PaymentMethod { cash, upi, card, netBanking, cheque, other }

extension PaymentMethodX on PaymentMethod {
  String get labelKey {
    switch (this) {
      case PaymentMethod.cash:
        return 'pmCash';
      case PaymentMethod.upi:
        return 'pmUpi';
      case PaymentMethod.card:
        return 'pmCard';
      case PaymentMethod.netBanking:
        return 'pmNetBanking';
      case PaymentMethod.cheque:
        return 'pmCheque';
      case PaymentMethod.other:
        return 'pmOther';
    }
  }

  String label(AppLocalizations l10n) => l10n.t(labelKey);

  IconData get icon {
    switch (this) {
      case PaymentMethod.cash:
        return Icons.payments_rounded;
      case PaymentMethod.upi:
        return Icons.qr_code_rounded;
      case PaymentMethod.card:
        return Icons.credit_card_rounded;
      case PaymentMethod.netBanking:
        return Icons.account_balance_rounded;
      case PaymentMethod.cheque:
        return Icons.receipt_long_rounded;
      case PaymentMethod.other:
        return Icons.more_horiz_rounded;
    }
  }

  static PaymentMethod? fromName(String? name) {
    if (name == null) return null;
    for (final m in PaymentMethod.values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Transaction record
// ---------------------------------------------------------------------------

/// One ITR-ready transaction with an optional attached receipt.
class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.description,
    required this.amount,
    required this.dateTime,
    required this.type,
    required this.category,
    this.reference,
    this.gstAmount,
    this.vendorName,
    this.paymentMethod,
    this.note,
    this.receiptPath,
    this.receiptIsPdf = false,
    this.direction,
  });

  final String id;

  /// The transaction description / title (e.g. "Office rent", "LIC premium").
  final String description;

  /// Always positive.
  final double amount;

  final DateTime dateTime;
  final TransactionType type;
  final TxnCategory category;

  /// Money direction, or null when unset (older records) - read via
  /// [effectiveDirection], which falls back to the type-derived default.
  final TransactionDirection? direction;

  /// User-entered transaction reference / Transaction ID (e.g. "TXN123456").
  final String? reference;

  /// GST component of [amount], if any.
  final double? gstAmount;

  /// Vendor / payee name, if any.
  final String? vendorName;

  /// How the transaction was paid / received, if recorded.
  final PaymentMethod? paymentMethod;

  /// Free-text note for the transaction, if any.
  final String? note;

  /// Local path to the attached receipt/screenshot, or null.
  final String? receiptPath;
  final bool receiptIsPdf;

  bool get isIncome => type.isIncome;
  bool get hasReceipt => receiptPath != null;
  FinancialYear get financialYear => FinancialYear.of(dateTime);

  /// The money direction to display / store: the explicit [direction] when set,
  /// otherwise the type-derived default (income → credited, expense → debited).
  /// This is what makes records saved before the direction field keep rendering
  /// correctly.
  TransactionDirection get effectiveDirection =>
      direction ?? TransactionDirectionX.defaultFor(type);

  /// True when funds arrived (shown as "+₹…" in lists).
  bool get isCredited => effectiveDirection.isCredited;

  TransactionRecord copyWith({
    String? description,
    double? amount,
    DateTime? dateTime,
    TransactionType? type,
    TxnCategory? category,
    String? reference,
    double? gstAmount,
    String? vendorName,
    PaymentMethod? paymentMethod,
    String? note,
    String? receiptPath,
    bool? receiptIsPdf,
    TransactionDirection? direction,
  }) =>
      TransactionRecord(
        id: id,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        dateTime: dateTime ?? this.dateTime,
        type: type ?? this.type,
        category: category ?? this.category,
        reference: reference ?? this.reference,
        gstAmount: gstAmount ?? this.gstAmount,
        vendorName: vendorName ?? this.vendorName,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        note: note ?? this.note,
        receiptPath: receiptPath ?? this.receiptPath,
        receiptIsPdf: receiptIsPdf ?? this.receiptIsPdf,
        direction: direction ?? this.direction,
      );

  // ---- Supabase row mapping (public.expenses) ------------------------------
  // The DB column `title` holds this model's `description`; `notes` holds
  // `note`; `expense_date` holds `dateTime`.

  /// Builds a [TransactionRecord] from a `public.expenses` row.
  factory TransactionRecord.fromRow(Map<String, dynamic> row) =>
      TransactionRecord(
        id: row['id'].toString(),
        description: (row['title'] as String?) ?? '',
        amount: (row['amount'] as num?)?.toDouble() ?? 0,
        dateTime: DateTime.tryParse(row['expense_date']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
        type: TransactionTypeX.fromName(row['type'] as String?),
        category: TxnCategoryX.fromName(row['category'] as String?),
        reference: row['reference'] as String?,
        gstAmount: (row['gst_amount'] as num?)?.toDouble(),
        vendorName: row['vendor_name'] as String?,
        paymentMethod:
            PaymentMethodX.fromName(row['payment_method'] as String?),
        note: row['notes'] as String?,
        receiptPath: row['receipt_path'] as String?,
        receiptIsPdf: (row['receipt_is_pdf'] as bool?) ?? false,
        // Null for rows written before the column existed → effectiveDirection
        // derives it from the type.
        direction: TransactionDirectionX.fromName(row['direction'] as String?),
      );

  /// The column values for an INSERT/UPDATE (no `id` - the DB generates it on
  /// insert; updates target the row by id in the filter).
  Map<String, dynamic> toInsert() => {
        'title': description,
        'amount': amount,
        'type': type.name,
        'category': category.name,
        'payment_method': paymentMethod?.name,
        'expense_date': dateTime.toUtc().toIso8601String(),
        'reference': reference,
        'gst_amount': gstAmount,
        'vendor_name': vendorName,
        'notes': note,
        'receipt_path': receiptPath,
        'receipt_is_pdf': receiptIsPdf,
        // Persist the resolved direction so old rows get a concrete value on
        // their next save (and new rows are always explicit).
        'direction': effectiveDirection.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// Full rebuild used when a field must be set back to null (copyWith can't).
  TransactionRecord replace({
    required String description,
    required double amount,
    required DateTime dateTime,
    required TransactionType type,
    required TxnCategory category,
    required String? reference,
    required double? gstAmount,
    required String? vendorName,
    required PaymentMethod? paymentMethod,
    required String? note,
    required String? receiptPath,
    required bool receiptIsPdf,
    required TransactionDirection? direction,
  }) =>
      TransactionRecord(
        id: id,
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
        direction: direction,
      );
}

// ---------------------------------------------------------------------------
// Tax document vault
// ---------------------------------------------------------------------------

/// The kinds of tax document the vault stores.
enum TaxDocType {
  form16,
  form26AS,
  ais,
  tdsCertificate,
  salarySlip,
  investmentProof,
  rentReceipt,
  medicalBill,
  insurancePremium,
  homeLoanInterest,
}

extension TaxDocTypeX on TaxDocType {
  static TaxDocType fromName(String? name) => TaxDocType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => TaxDocType.investmentProof,
      );

  String get labelKey {
    switch (this) {
      case TaxDocType.form16:
        return 'taxDocForm16';
      case TaxDocType.form26AS:
        return 'taxDocForm26AS';
      case TaxDocType.ais:
        return 'taxDocAis';
      case TaxDocType.tdsCertificate:
        return 'taxDocTds';
      case TaxDocType.salarySlip:
        return 'taxDocSalarySlip';
      case TaxDocType.investmentProof:
        return 'taxDocInvestmentProof';
      case TaxDocType.rentReceipt:
        return 'taxDocRentReceipt';
      case TaxDocType.medicalBill:
        return 'taxDocMedicalBill';
      case TaxDocType.insurancePremium:
        return 'taxDocInsurancePremium';
      case TaxDocType.homeLoanInterest:
        return 'taxDocHomeLoanInterest';
    }
  }

  String label(AppLocalizations l10n) => l10n.t(labelKey);

  IconData get icon {
    switch (this) {
      case TaxDocType.form16:
        return Icons.description_rounded;
      case TaxDocType.form26AS:
        return Icons.article_rounded;
      case TaxDocType.ais:
        return Icons.summarize_rounded;
      case TaxDocType.tdsCertificate:
        return Icons.verified_rounded;
      case TaxDocType.salarySlip:
        return Icons.payments_rounded;
      case TaxDocType.investmentProof:
        return Icons.trending_up_rounded;
      case TaxDocType.rentReceipt:
        return Icons.home_rounded;
      case TaxDocType.medicalBill:
        return Icons.favorite_rounded;
      case TaxDocType.insurancePremium:
        return Icons.shield_rounded;
      case TaxDocType.homeLoanInterest:
        return Icons.account_balance_rounded;
    }
  }
}

/// One stored tax document (image / PDF) filed under a financial year + type.
class TaxDocument {
  const TaxDocument({
    required this.id,
    required this.type,
    required this.fileName,
    required this.filePath,
    required this.isPdf,
    required this.addedAt,
    required this.financialYearStart,
  });

  final String id;
  final TaxDocType type;
  final String fileName;
  final String filePath;
  final bool isPdf;
  final DateTime addedAt;

  /// The [FinancialYear.startYear] this document is filed under.
  final int financialYearStart;

  // ---- Supabase row mapping (public.tax_documents) -------------------------

  /// Builds a [TaxDocument] from a `public.tax_documents` row.
  factory TaxDocument.fromRow(Map<String, dynamic> row) => TaxDocument(
        id: row['id'].toString(),
        type: TaxDocTypeX.fromName(row['doc_type'] as String?),
        fileName: (row['file_name'] as String?) ?? '',
        filePath: (row['file_path'] as String?) ?? '',
        isPdf: (row['is_pdf'] as bool?) ?? false,
        addedAt: DateTime.tryParse(row['added_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
        financialYearStart: (row['financial_year_start'] as num?)?.toInt() ??
            FinancialYear.current().startYear,
      );

  /// The column values for an INSERT (no `id` - the DB generates it).
  Map<String, dynamic> toInsert() => {
        'doc_type': type.name,
        'file_name': fileName,
        'file_path': filePath,
        'is_pdf': isPdf,
        'financial_year_start': financialYearStart,
        'added_at': addedAt.toUtc().toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Tax summary (ITR export)
// ---------------------------------------------------------------------------

/// A computed ITR summary for one financial year.
class TaxSummary {
  const TaxSummary({
    required this.year,
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalInvestments,
    required this.insurancePremiums,
    required this.medicalExpenses,
    required this.rentPaid,
    required this.taxPaid,
    required this.transactionCount,
  });

  final FinancialYear year;
  final double totalIncome;
  final double totalExpenses;
  final double totalInvestments;
  final double insurancePremiums;
  final double medicalExpenses;
  final double rentPaid;
  final double taxPaid;
  final int transactionCount;
}
