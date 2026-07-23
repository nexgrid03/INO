import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// Models backing the ITR-ready Transaction Vault — a record + receipt store
// organised by financial year, with a tax-document vault and a tax summary.
//
// UI-agnostic plain objects so the in-memory store can be swapped for a
// Supabase-backed repository later without touching a widget. NO sample data —
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
  String get label => this == TransactionType.income ? 'Income' : 'Expense';
  bool get isIncome => this == TransactionType.income;
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
  String get label {
    switch (this) {
      case TxnCategory.salary:
        return 'Salary';
      case TxnCategory.business:
        return 'Business';
      case TxnCategory.investment:
        return 'Investment';
      case TxnCategory.rent:
        return 'Rent';
      case TxnCategory.insurance:
        return 'Insurance';
      case TxnCategory.medical:
        return 'Medical';
      case TxnCategory.education:
        return 'Education';
      case TxnCategory.travel:
        return 'Travel';
      case TxnCategory.food:
        return 'Food';
      case TxnCategory.shopping:
        return 'Shopping';
      case TxnCategory.utilities:
        return 'Utilities';
      case TxnCategory.loanEmi:
        return 'Loan / EMI';
      case TxnCategory.taxPayment:
        return 'Tax Payment';
      case TxnCategory.other:
        return 'Other';
    }
  }

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
        return AppColors.primaryGreen;
      case TxnCategory.business:
        return AppColors.secondaryGreen;
      case TxnCategory.investment:
        return const Color(0xFF30ACB3);
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
        return AppColors.lightBlue;
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
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.netBanking:
        return 'Net Banking';
      case PaymentMethod.cheque:
        return 'Cheque';
      case PaymentMethod.other:
        return 'Other';
    }
  }

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
  });

  final String id;

  /// The transaction description / title (e.g. "Office rent", "LIC premium").
  final String description;

  /// Always positive.
  final double amount;

  final DateTime dateTime;
  final TransactionType type;
  final TxnCategory category;

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
      );

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
  String get label {
    switch (this) {
      case TaxDocType.form16:
        return 'Form 16';
      case TaxDocType.form26AS:
        return 'Form 26AS';
      case TaxDocType.ais:
        return 'AIS';
      case TaxDocType.tdsCertificate:
        return 'TDS Certificates';
      case TaxDocType.salarySlip:
        return 'Salary Slips';
      case TaxDocType.investmentProof:
        return 'Investment Proofs';
      case TaxDocType.rentReceipt:
        return 'Rent Receipts';
      case TaxDocType.medicalBill:
        return 'Medical Bills';
      case TaxDocType.insurancePremium:
        return 'Insurance Premium Receipts';
      case TaxDocType.homeLoanInterest:
        return 'Home Loan Interest Certificates';
    }
  }

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
