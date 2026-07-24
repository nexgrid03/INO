import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../models/document.dart';
import '../../models/document_extraction.dart';
import '../../repositories/document_repository.dart';
import '../../theme/app_theme.dart';
import 'wallet_detail_screen.dart';

/// A real global search across every document in the vault.
///
/// Loads the signed-in user's documents once and filters live by name,
/// category, wallet, record number or tag. Selecting a result opens that
/// document's wallet. Backed by [DocumentRepository]; degrades to a friendly
/// message when signed out / offline.
class DocumentSearchDelegate extends SearchDelegate<void> {
  DocumentSearchDelegate({Set<String>? walletFilter})
      : walletFilter = walletFilter ?? const <String>{},
        super(searchFieldLabel: 'Search documents');

  /// Canonical wallet names (e.g. "Identity Wallet") to constrain results to.
  /// Empty means no wallet filter — set from the Wallet hub's filter panel.
  final Set<String> walletFilter;

  Future<List<Document>>? _corpus;
  Future<List<Document>> _load() =>
      _corpus ??= DocumentRepository.instance.listAll();

  List<Document> _filter(List<Document> docs, String q) {
    final query = q.trim().toLowerCase();
    Iterable<Document> pool = docs;
    if (walletFilter.isNotEmpty) {
      pool = pool.where((d) => walletFilter.contains(d.wallet));
    }
    if (query.isEmpty) return pool.toList();
    return pool
        .where((d) =>
            d.name.toLowerCase().contains(query) ||
            (d.category?.toLowerCase().contains(query) ?? false) ||
            (d.recordNumber?.toLowerCase().contains(query) ?? false) ||
            d.wallet.toLowerCase().contains(query) ||
            d.tags.any((t) => t.toLowerCase().contains(query)) ||
            // Search the OCR-extracted fields (Aadhaar / PAN / passport / license
            // number, full name, …) stored with the document.
            DocumentExtraction.decode(d.notes)
                .searchableText
                .toLowerCase()
                .contains(query))
        .toList();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _resultsList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _resultsList(context);

  Widget _resultsList(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<List<Document>>(
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return _message(context, 'Sign in to search your documents.');
        }
        final results = _filter(snap.data!, query);
        if (results.isEmpty) {
          return _message(
            context,
            query.trim().isEmpty
                ? (walletFilter.isEmpty
                    ? 'Type to search your documents.'
                    : 'No documents in the selected wallets.')
                : 'No documents match “$query”.',
          );
        }
        return ListView.separated(
          itemCount: results.length + (walletFilter.isEmpty ? 0 : 1),
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: palette.border),
          itemBuilder: (context, i) {
            if (walletFilter.isNotEmpty && i == 0) {
              return _filterBanner(context);
            }
            final d = results[walletFilter.isEmpty ? i : i - 1];
            return ListTile(
              leading: const Icon(Icons.description_rounded,
                  color: AppColors.primaryGreen),
              title: Text(d.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [d.wallet, if (d.category != null) d.category!].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _open(context, d),
            );
          },
        );
      },
    );
  }

  void _open(BuildContext context, Document d) {
    final category = SupabaseWalletRepository.categoryFor(d.wallet);
    close(context, null);
    if (category == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WalletDetailScreen(category: category)),
    );
  }

  /// A slim header shown above filtered results, naming the active wallets.
  Widget _filterBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.primaryGreen.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 16, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filtered · ${walletFilter.join(' · ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, fontSize: 14.5),
        ),
      ),
    );
  }
}
