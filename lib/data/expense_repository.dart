import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/expense_models.dart';

/// Everything the Transaction Vault persists, loaded in one round trip pair.
class ExpenseData {
  const ExpenseData({required this.transactions, required this.taxDocuments});

  final List<TransactionRecord> transactions;
  final List<TaxDocument> taxDocuments;
}

/// Source of Transaction Vault data — the `public.expenses` and
/// `public.tax_documents` tables in Supabase.
///
/// The store/screens depend only on this abstraction, so it stays the single
/// place that talks to those tables (same pattern as ReminderRepository /
/// NotesRepository). RLS scopes rows to the owner server-side; every query
/// here ALSO filters by `auth_user_id` as defense-in-depth.
abstract class ExpenseRepository {
  /// Loads all of the signed-in user's transactions + tax documents.
  Future<ExpenseData> load();

  /// Inserts a new transaction and returns it with its real DB id.
  Future<TransactionRecord> addTransaction(TransactionRecord txn);

  /// Updates an existing transaction (matched by id, owner-scoped).
  Future<void> updateTransaction(TransactionRecord txn);

  /// Permanently deletes a transaction.
  Future<void> removeTransaction(String id);

  /// Inserts a tax document's metadata and returns it with its real DB id.
  Future<TaxDocument> addTaxDocument(TaxDocument doc);

  /// Permanently deletes a tax document's metadata.
  Future<void> removeTaxDocument(String id);

  static ExpenseRepository instance = SupabaseExpenseRepository();
}

class SupabaseExpenseRepository implements ExpenseRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static const String _txnTable = 'expenses';
  static const String _taxTable = 'tax_documents';

  /// The signed-in user's id, or null when signed out.
  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<ExpenseData> load() async {
    final uid = _uid;
    if (uid == null) {
      return const ExpenseData(transactions: [], taxDocuments: []);
    }
    final txnRows = await _client
        .from(_txnTable)
        .select()
        .eq('auth_user_id', uid)
        .order('expense_date', ascending: false);
    final taxRows = await _client
        .from(_taxTable)
        .select()
        .eq('auth_user_id', uid)
        .order('added_at', ascending: false);
    final data = ExpenseData(
      transactions: [for (final r in txnRows) TransactionRecord.fromRow(r)],
      taxDocuments: [for (final r in taxRows) TaxDocument.fromRow(r)],
    );
    debugPrint('Expenses loaded from Supabase: '
        '${data.transactions.length} txns, ${data.taxDocuments.length} tax docs');
    return data;
  }

  @override
  Future<TransactionRecord> addTransaction(TransactionRecord txn) async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to save a transaction.');
    }
    // Stamp the owner explicitly — same belt-and-suspenders as reminders/notes.
    final payload = txn.toInsert()..['auth_user_id'] = uid;
    final row =
        await _client.from(_txnTable).insert(payload).select().single();
    return TransactionRecord.fromRow(row);
  }

  @override
  Future<void> updateTransaction(TransactionRecord txn) async {
    final uid = _uid;
    if (uid == null) return;
    // Ownership check in the filter: a user can only edit their OWN record.
    await _client
        .from(_txnTable)
        .update(txn.toInsert())
        .eq('id', txn.id)
        .eq('auth_user_id', uid);
  }

  @override
  Future<void> removeTransaction(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client
        .from(_txnTable)
        .delete()
        .eq('id', id)
        .eq('auth_user_id', uid);
  }

  @override
  Future<TaxDocument> addTaxDocument(TaxDocument doc) async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to save a document.');
    }
    final payload = doc.toInsert()..['auth_user_id'] = uid;
    final row =
        await _client.from(_taxTable).insert(payload).select().single();
    return TaxDocument.fromRow(row);
  }

  @override
  Future<void> removeTaxDocument(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client
        .from(_taxTable)
        .delete()
        .eq('id', id)
        .eq('auth_user_id', uid);
  }
}
