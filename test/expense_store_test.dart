import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/expense_models.dart';
import 'package:inoapp/services/expense_store.dart';
import 'package:inoapp/services/receipt_parser.dart';

void main() {
  final store = ExpenseStore.instance;
  final fy = FinancialYear(2026); // 1 Apr 2026 – 31 Mar 2027
  DateTime inFy([int month = 7, int day = 1]) => DateTime(2026, month, day, 12);

  setUp(store.reset);

  TransactionRecord add(
    String desc,
    double amt,
    TxnCategory cat, {
    TransactionType type = TransactionType.expense,
    DateTime? at,
    String? ref,
    String? vendor,
    double? gst,
  }) =>
      store.add(
        description: desc,
        amount: amt,
        dateTime: at ?? inFy(),
        type: type,
        category: cat,
        reference: ref,
        vendorName: vendor,
        gstAmount: gst,
      );

  test('starts completely empty — no seed data', () {
    expect(store.isEmpty, isTrue);
    expect(store.transactionsForYear(fy), isEmpty);
    expect(store.countForYear(fy), 0);
    expect(store.taxDocumentsForYear(fy), isEmpty);
  });

  group('FinancialYear', () {
    test('Indian FY runs Apr–Mar with a "YYYY-YY" label', () {
      expect(FinancialYear.of(DateTime(2026, 7, 1)).startYear, 2026);
      expect(FinancialYear.of(DateTime(2026, 2, 1)).startYear, 2025);
      expect(fy.label, '2026-27');
      expect(fy.contains(DateTime(2026, 4, 1)), isTrue);
      expect(fy.contains(DateTime(2027, 3, 31)), isTrue);
      expect(fy.contains(DateTime(2027, 4, 1)), isFalse);
      expect(FinancialYear(2026) == FinancialYear(2026), isTrue);
    });

    test('transactions are filtered by financial year', () {
      add('This FY', 100, TxnCategory.food, at: inFy(7));
      add('Next FY', 200, TxnCategory.food, at: DateTime(2027, 6, 1));
      expect(store.transactionsForYear(FinancialYear(2026)).single.description,
          'This FY');
      expect(store.transactionsForYear(FinancialYear(2027)).single.description,
          'Next FY');
      expect(store.availableYears.map((y) => y.startYear),
          containsAll([2026, 2027]));
    });
  });

  group('CRUD + totals', () {
    test('add / update / remove track count + total for the year', () {
      final t = add('Rent', 20000, TxnCategory.rent);
      add('Groceries', 3000, TxnCategory.food);
      expect(store.countForYear(fy), 2);
      expect(store.totalForYear(fy), 23000);
      store.update(t.copyWith(amount: 25000));
      expect(store.totalForYear(fy), 28000);
      store.remove(t.id);
      expect(store.countForYear(fy), 1);
      expect(store.byId(t.id), isNull);
    });
  });

  group('direction (credited / debited)', () {
    final fixed = DateTime(2026, 7, 1, 12);

    test('defaults are derived from the type when unset', () {
      // Old / unset records: income → credited, expense → debited.
      final income = TransactionRecord(
        id: 'i',
        description: 'Salary',
        amount: 1000,
        dateTime: fixed,
        type: TransactionType.income,
        category: TxnCategory.salary,
      );
      final expense = TransactionRecord(
        id: 'e',
        description: 'Rent',
        amount: 500,
        dateTime: fixed,
        type: TransactionType.expense,
        category: TxnCategory.rent,
      );
      expect(income.direction, isNull);
      expect(income.effectiveDirection, TransactionDirection.credited);
      expect(income.isCredited, isTrue);
      expect(expense.effectiveDirection, TransactionDirection.debited);
      expect(expense.isCredited, isFalse);
    });

    test('an explicit direction overrides the type default', () {
      // A refund: recorded as income but money went out → debited.
      final t = store.add(
        description: 'Refund reversal',
        amount: 200,
        dateTime: inFy(),
        type: TransactionType.income,
        category: TxnCategory.other,
        direction: TransactionDirection.debited,
      );
      expect(t.direction, TransactionDirection.debited);
      expect(t.effectiveDirection, TransactionDirection.debited);
      expect(t.isCredited, isFalse);
    });

    test('defaultFor maps type → direction', () {
      expect(TransactionDirectionX.defaultFor(TransactionType.income),
          TransactionDirection.credited);
      expect(TransactionDirectionX.defaultFor(TransactionType.expense),
          TransactionDirection.debited);
    });

    test('row round-trip persists the resolved direction, tolerates missing',
        () {
      // toInsert always writes a concrete direction (even for a legacy record
      // whose field is null).
      final legacy = TransactionRecord(
        id: 'x',
        description: 'Old income',
        amount: 1,
        dateTime: fixed,
        type: TransactionType.income,
        category: TxnCategory.salary,
      );
      expect(legacy.toInsert()['direction'], 'credited');

      // A row that predates the column (no 'direction' key) → null field, but
      // effectiveDirection still derives it from the type.
      final fromOldRow = TransactionRecord.fromRow({
        'id': 'r1',
        'title': 'Old expense',
        'amount': 10,
        'expense_date': fixed.toIso8601String(),
        'type': 'expense',
        'category': 'rent',
      });
      expect(fromOldRow.direction, isNull);
      expect(fromOldRow.effectiveDirection, TransactionDirection.debited);

      // A row with an explicit direction is read back faithfully.
      final fromNewRow = TransactionRecord.fromRow({
        'id': 'r2',
        'title': 'Refund',
        'amount': 10,
        'expense_date': fixed.toIso8601String(),
        'type': 'income',
        'category': 'other',
        'direction': 'debited',
      });
      expect(fromNewRow.direction, TransactionDirection.debited);
    });
  });

  group('search', () {
    test('matches description, transaction ID, vendor, amount and date', () {
      add('Office rent', 20000, TxnCategory.rent,
          ref: 'TXN555', vendor: 'Prestige Estates', at: inFy(7, 15));
      add('Lunch', 450, TxnCategory.food);

      expect(store.searchTransactions('', fy).length, 2);
      expect(store.searchTransactions('rent', fy).single.description,
          'Office rent');
      expect(store.searchTransactions('TXN555', fy).single.reference, 'TXN555');
      expect(store.searchTransactions('prestige', fy).single.vendorName,
          'Prestige Estates');
      expect(store.searchTransactions('20000', fy).single.amount, 20000);
      expect(store.searchTransactions('15/07/2026', fy).length, 1);
    });
  });

  group('tax document vault', () {
    test('add / list by year + type / remove', () {
      final d = store.addTaxDocument(
        type: TaxDocType.form16,
        fileName: 'Form16.pdf',
        filePath: '/tmp/f16.pdf',
        isPdf: true,
        fy: fy,
      );
      store.addTaxDocument(
        type: TaxDocType.rentReceipt,
        fileName: 'rent.jpg',
        filePath: '/tmp/rent.jpg',
        isPdf: false,
        fy: fy,
      );
      expect(store.taxDocumentsForYear(fy).length, 2);
      expect(store.taxDocumentsOfType(TaxDocType.form16, fy).single.fileName,
          'Form16.pdf');
      expect(store.taxDocumentsForYear(FinancialYear(2025)), isEmpty);
      store.removeTaxDocument(d.id);
      expect(store.taxDocumentsForYear(fy).length, 1);
    });
  });

  group('tax summary', () {
    test('aggregates income, expenses and ITR buckets for the year', () {
      add('Salary', 1200000, TxnCategory.salary, type: TransactionType.income);
      add('House rent', 240000, TxnCategory.rent);
      add('ELSS', 150000, TxnCategory.investment);
      add('LIC premium', 24000, TxnCategory.insurance);
      add('Hospital', 18000, TxnCategory.medical);
      add('Advance tax', 50000, TxnCategory.taxPayment);
      add('Groceries', 60000, TxnCategory.food);
      // Different FY — must be excluded.
      add('Old', 999, TxnCategory.food, at: DateTime(2025, 1, 1));

      final s = store.taxSummary(fy);
      expect(s.totalIncome, 1200000);
      expect(s.totalExpenses, 240000 + 150000 + 24000 + 18000 + 50000 + 60000);
      expect(s.totalInvestments, 150000);
      expect(s.insurancePremiums, 24000);
      expect(s.medicalExpenses, 18000);
      expect(s.rentPaid, 240000);
      expect(s.taxPaid, 50000);
      expect(s.transactionCount, 7);
    });
  });

  group('receipt OCR parser', () {
    test('extracts amount, date, GSTIN and vendor from receipt text', () {
      const text = '''
SUPER MART PVT LTD
GSTIN: 29ABCDE1234F1Z5
Invoice No: INV-88
Date: 15/07/2026
Item A  100.00
Item B  200.00
Total Amount Rs 354.00
Thank you
''';
      final r = ReceiptParser.parse(text);
      expect(r.gstNumber, '29ABCDE1234F1Z5');
      expect(r.amount, 354.00);
      expect(r.date, DateTime(2026, 7, 15));
      expect(r.vendorName, 'SUPER MART PVT LTD');
    });

    test('returns empty data when nothing recognisable', () {
      final r = ReceiptParser.parse('....\n----\n');
      expect(r.isEmpty, isTrue);
    });
  });

  test('clear empties the vault', () {
    add('X', 1, TxnCategory.other);
    store.addTaxDocument(
        type: TaxDocType.ais,
        fileName: 'a',
        filePath: 'p',
        isPdf: false,
        fy: fy);
    store.clear();
    expect(store.isEmpty, isTrue);
    expect(store.taxDocumentsForYear(fy), isEmpty);
  });
}
