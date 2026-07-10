import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reminder_store.dart';
import '../models/document.dart';
import '../repositories/document_repository.dart';
import '../theme/app_theme.dart';

/// What a search hit points to, so the results screen can route on tap.
enum SearchHitType { document, reminder, category, tag }

/// One global-search result.
class SearchHit {
  const SearchHit({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.wallet,
    this.documentId,
  });

  final SearchHitType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? wallet; // for documents: which wallet to open
  final String? documentId;
}

/// Global search across the user's real data — documents (name / category /
/// tags / wallet), reminders (title / subtitle), plus category and tag matches.
///
/// Also owns the persisted "recent searches" list. Everything is queried live so
/// results are always current; there is no fake data.
class GlobalSearchService {
  GlobalSearchService._();
  static final GlobalSearchService instance = GlobalSearchService._();

  static const _kRecent = 'search_recent_terms';
  static const _maxRecent = 8;

  List<Document>? _docCache;

  /// Frequently useful starting points shown before the user types.
  static const List<String> suggestions = [
    'Insurance',
    'Identity',
    'PAN',
    'Aadhaar',
    'Passport',
    'Property',
    'Expiring',
  ];

  /// Runs a case-insensitive search. Returns an empty list for a blank query.
  Future<List<SearchHit>> search(String rawQuery) async {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final hits = <SearchHit>[];
    final seenCategories = <String>{};
    final seenTags = <String>{};

    // Documents.
    try {
      final docs = _docCache ??= await DocumentRepository.instance.listAll();
      for (final d in docs) {
        final category = d.category ?? 'Other';
        final haystack = [
          d.name,
          category,
          d.wallet,
          d.recordNumber ?? '',
          ...d.tags,
        ].join(' ').toLowerCase();

        if (haystack.contains(q)) {
          hits.add(SearchHit(
            type: SearchHitType.document,
            title: d.name,
            subtitle: '$category · ${d.wallet}',
            icon: Icons.description_rounded,
            color: AppColors.primaryGreen,
            wallet: d.wallet,
            documentId: d.id,
          ));
        }
        // Surface distinct matching categories / tags as their own hits.
        if (category.toLowerCase().contains(q) &&
            seenCategories.add(category.toLowerCase())) {
          hits.add(SearchHit(
            type: SearchHitType.category,
            title: category,
            subtitle: 'Category',
            icon: Icons.folder_rounded,
            color: AppColors.lightBlue,
            wallet: d.wallet,
          ));
        }
        for (final t in d.tags) {
          if (t.toLowerCase().contains(q) && seenTags.add(t.toLowerCase())) {
            hits.add(SearchHit(
              type: SearchHitType.tag,
              title: '#$t',
              subtitle: 'Tag',
              icon: Icons.label_rounded,
              color: AppColors.secondaryGreen,
              wallet: d.wallet,
            ));
          }
        }
      }
    } catch (e) {
      developer.log('search: documents unavailable: $e', name: 'search');
    }

    // Reminders.
    try {
      await ReminderStore.instance.ensureLoaded();
      for (final r in ReminderStore.instance.active) {
        final haystack =
            '${r.title} ${r.subtitle} ${r.category.name}'.toLowerCase();
        if (haystack.contains(q)) {
          hits.add(SearchHit(
            type: SearchHitType.reminder,
            title: r.title,
            subtitle: r.subtitle.isEmpty ? 'Reminder' : r.subtitle,
            icon: Icons.alarm_rounded,
            color: AppColors.warning,
          ));
        }
      }
    } catch (e) {
      developer.log('search: reminders unavailable: $e', name: 'search');
    }

    return hits;
  }

  /// Clears the cached document snapshot so the next search re-fetches.
  void invalidate() => _docCache = null;

  // ---- Recent searches -----------------------------------------------------

  Future<List<String>> recentSearches() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList(_kRecent) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRecent(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_kRecent) ?? <String>[];
      list.removeWhere((e) => e.toLowerCase() == t.toLowerCase());
      list.insert(0, t);
      await p.setStringList(
          _kRecent, list.take(_maxRecent).toList(growable: false));
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> clearRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kRecent);
    } catch (_) {}
  }

  /// Drops the in-memory document cache AND the persisted recent-search history
  /// so the next account can't search the previous user's documents or see their
  /// search terms. Called from [SessionReset] on sign-out.
  Future<void> clear() async {
    _docCache = null;
    await clearRecent();
  }
}
