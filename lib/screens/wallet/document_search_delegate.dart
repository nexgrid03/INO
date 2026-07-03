import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../models/document.dart';
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
  DocumentSearchDelegate() : super(searchFieldLabel: 'Search documents');

  Future<List<Document>>? _corpus;
  Future<List<Document>> _load() =>
      _corpus ??= DocumentRepository.instance.listAll();

  List<Document> _filter(List<Document> docs, String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return docs;
    return docs
        .where((d) =>
            d.name.toLowerCase().contains(query) ||
            (d.category?.toLowerCase().contains(query) ?? false) ||
            (d.recordNumber?.toLowerCase().contains(query) ?? false) ||
            d.wallet.toLowerCase().contains(query) ||
            d.tags.any((t) => t.toLowerCase().contains(query)))
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
                ? 'Type to search your documents.'
                : 'No documents match “$query”.',
          );
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: palette.border),
          itemBuilder: (context, i) {
            final d = results[i];
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
