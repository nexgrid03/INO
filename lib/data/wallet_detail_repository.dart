import 'package:flutter/material.dart';

import '../models/dashboard_models.dart' show SmartInsight;
import '../models/document.dart';
import '../models/wallet_detail_models.dart';
import '../models/wallet_models.dart' show RecentItem, SecurityStatus, WalletCategory;
import '../repositories/document_repository.dart';
import '../theme/app_theme.dart';

/// Aggregate read model for one wallet's detail screen.
class WalletDetailData {
  const WalletDetailData({
    required this.walletName,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.lastUpdatedLabel,
    required this.overview,
    required this.records,
    required this.recents,
    required this.insights,
    required this.security,
    required this.storage,
  });

  final String walletName;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String lastUpdatedLabel; // "Updated Today"
  final DetailOverview overview;
  final List<DocumentRecord> records;
  final List<RecentItem> recents;
  final List<SmartInsight> insights;
  final SecurityStatus security;
  final StorageAnalytics storage;
}

/// Source of Wallet Detail data. The screen depends only on this abstraction.
/// The same UI is reused for every wallet — [load] returns the signed-in user's
/// real documents for the given wallet, straight from Supabase.
abstract class WalletDetailRepository {
  Future<WalletDetailData> load(WalletCategory category);
  void addRecord(String walletName, DocumentRecord record);
  void updateRecord(String walletName, DocumentRecord record);
  void deleteRecord(String walletName, String recordId);

  static WalletDetailRepository instance = SupabaseWalletDetailRepository();
}

/// Live implementation backed by the `documents` table in Supabase.
///
/// Keeps a small in-memory cache per wallet so favourite / archive toggles feel
/// instant; the real writes go to Supabase via [DocumentRepository] so they
/// survive an app restart.
class SupabaseWalletDetailRepository implements WalletDetailRepository {
  final Map<String, List<DocumentRecord>> _cache = {};

  @override
  Future<WalletDetailData> load(WalletCategory category) async {
    List<DocumentRecord> records;
    try {
      final docs =
          await DocumentRepository.instance.listForWallet(category.name);
      records = docs.map(_toRecord).toList();
      _cache[category.name] = records;
    } catch (_) {
      // Offline / not signed in — fall back to whatever we already have.
      records = _cache[category.name] ?? const [];
    }

    final active =
        records.where((r) => r.status == DocumentStatus.active).length;
    final expiring = records
        .where((r) =>
            r.status == DocumentStatus.expiringSoon ||
            r.status == DocumentStatus.expired)
        .length;
    final usedMb = records.length * 4; // rough estimate for the storage bar

    return WalletDetailData(
      walletName: category.name,
      subtitle: _subtitleFor(category.name),
      icon: category.icon,
      gradient: category.gradient,
      lastUpdatedLabel: records.isEmpty ? 'No documents yet' : 'Updated Today',
      overview: DetailOverview(
        totalRecords: records.length,
        activeRecords: active,
        expiringSoon: expiring,
        lastAccessed: records.isEmpty ? '—' : 'Today',
        storageUsedLabel: '$usedMb MB',
        storageFraction: (usedMb / 5120).clamp(0.0, 1.0),
      ),
      records: records,
      recents: _recentsFrom(records, category),
      insights: _insightsFor(category, expiring),
      security: const SecurityStatus(
        score: 100,
        vaultLocked: true,
        biometricEnabled: true,
        lastBackup: 'Synced',
        cloudSynced: true,
      ),
      storage: StorageAnalytics(
        totalFiles: records.length,
        usedLabel: '$usedMb MB',
        availableLabel: '5 GB',
        usedFraction: (usedMb / 5120).clamp(0.0, 1.0),
        monthlyUploads: records.length,
        monthly: const [0, 0, 0, 0, 0, 0],
      ),
    );
  }

  @override
  void addRecord(String walletName, DocumentRecord record) {
    final list = _cache[walletName] ?? [];
    _cache[walletName] = [record, ...list];
  }

  @override
  void updateRecord(String walletName, DocumentRecord record) {
    final list = _cache[walletName];
    if (list != null) {
      final idx = list.indexWhere((r) => r.id == record.id);
      if (idx != -1) list[idx] = record;
    }
    // Persist the change so it survives a restart (fire-and-forget).
    DocumentRepository.instance.update(record.id, {
      'is_favorite': record.isFavorite,
      'status': record.status.name,
    }).catchError((_) {});
  }

  @override
  void deleteRecord(String walletName, String recordId) {
    _cache[walletName]?.removeWhere((r) => r.id == recordId);
    DocumentRepository.instance.delete(recordId).catchError((_) {});
  }

  // ---- Mapping ------------------------------------------------------------

  /// Turns a database [Document] into the UI's [DocumentRecord].
  DocumentRecord _toRecord(Document d) {
    return DocumentRecord(
      id: d.id,
      name: d.name,
      category: d.category ?? 'Other',
      icon: _iconFor(d.category),
      uploadedAt: d.createdAt,
      updatedAt: d.updatedAt,
      expiresAt: d.expiresAt,
      status: _statusFor(d),
      recordNumber: d.recordNumber,
      tags: d.tags,
      isFavorite: d.isFavorite,
    );
  }

  /// Derives a display status: an expiry date always wins over the stored
  /// string so the UI stays honest about what's expired / expiring.
  DocumentStatus _statusFor(Document d) {
    final exp = d.expiresAt;
    if (exp != null) {
      final days = exp.difference(DateTime.now()).inDays;
      if (days < 0) return DocumentStatus.expired;
      if (days <= 30) return DocumentStatus.expiringSoon;
    }
    switch (d.status) {
      case 'shared':
        return DocumentStatus.shared;
      case 'archived':
        return DocumentStatus.archived;
      case 'expired':
        return DocumentStatus.expired;
      case 'expiringSoon':
        return DocumentStatus.expiringSoon;
      default:
        return DocumentStatus.active;
    }
  }

  IconData _iconFor(String? category) {
    switch (category) {
      case 'Identity':
        return Icons.badge_rounded;
      case 'Financial':
        return Icons.account_balance_rounded;
      case 'Legal':
        return Icons.gavel_rounded;
      case 'Medical':
        return Icons.favorite_rounded;
      case 'Property':
        return Icons.home_work_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  String _subtitleFor(String name) {
    const map = {
      'Identity Wallet': 'Manage your important identity documents securely.',
      'Document Wallet': 'All your certificates and contracts in one vault.',
      'Property Wallet': 'Deeds, tax records and ownership papers, organised.',
      'Insurance Wallet': 'Every policy and premium, tracked and protected.',
      'Health Wallet': 'Medical records, reports and prescriptions, private.',
      'Investment Wallet': 'Your portfolio statements and holdings, secured.',
      'Banking Wallet': 'Accounts, statements and cards, safely stored.',
      'Password Vault': 'Encrypted credentials, locked behind biometrics.',
    };
    return map[name] ?? 'Manage your records securely.';
  }

  // ---- Recents / insights (derived from real records) ---------------------

  List<RecentItem> _recentsFrom(
      List<DocumentRecord> records, WalletCategory category) {
    final sorted = [...records]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final r in sorted.take(5))
        RecentItem(
          name: r.name,
          category: r.category,
          lastOpened: _relativeTime(r.updatedAt),
          icon: r.icon,
          color: category.gradient.first,
        ),
    ];
  }

  List<SmartInsight> _insightsFor(WalletCategory category, int expiring) {
    return [
      if (expiring > 0)
        SmartInsight(
          message:
              '$expiring record${expiring > 1 ? 's are' : ' is'} expiring soon in this wallet.',
          icon: Icons.timelapse_rounded,
          accent: AppColors.warning,
        ),
    ];
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}
