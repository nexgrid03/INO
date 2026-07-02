import 'package:flutter/material.dart';

import '../models/dashboard_models.dart' show QuickAction, SmartInsight;
import '../models/document.dart';
import '../models/wallet_models.dart';
import '../repositories/document_repository.dart';
import '../theme/app_theme.dart';

/// Aggregate read model for the Wallet Hub — fetched once, fanned out to the
/// section widgets.
class WalletHubData {
  const WalletHubData({
    required this.overview,
    required this.categories,
    required this.quickActions,
    required this.recents,
    required this.security,
    required this.insights,
  });

  final WalletOverview overview;
  final List<WalletCategory> categories;
  final List<QuickAction> quickActions;
  final List<RecentItem> recents;
  final SecurityStatus security;
  final List<SmartInsight> insights;
}

/// Source of Wallet Hub data. The screen depends only on this abstraction.
/// [SupabaseWalletRepository] fills the wallet counts and recents from the
/// signed-in user's real documents.
abstract class WalletRepository {
  Future<WalletHubData> load();

  static WalletRepository instance = SupabaseWalletRepository();
}

class SupabaseWalletRepository implements WalletRepository {
  /// The eight wallet "buckets" the app offers. These are the app's structure
  /// (not stored data) — the counts below are filled in from real documents.
  static const List<WalletCategory> _categories = [
    WalletCategory(
      name: 'Identity Wallet',
      icon: Icons.badge_rounded,
      contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
      metric: '0',
      metricLabel: 'documents',
      gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
    ),
    WalletCategory(
      name: 'Document Wallet',
      icon: Icons.folder_shared_rounded,
      contents: ['Certificates', 'Contracts', 'Personal Documents'],
      metric: '0',
      metricLabel: 'files',
      gradient: [Color(0xFF3B82F6), Color(0xFF7DD3FC)],
    ),
    WalletCategory(
      name: 'Property Wallet',
      icon: Icons.home_work_rounded,
      contents: ['Property Documents', 'Tax Records', 'Sale Deeds'],
      metric: '0',
      metricLabel: 'properties',
      gradient: [Color(0xFF38BDF8), Color(0xFF7DD3FC)],
    ),
    WalletCategory(
      name: 'Insurance Wallet',
      icon: Icons.shield_rounded,
      contents: ['Health', 'Vehicle', 'Life Insurance'],
      metric: '0',
      metricLabel: 'policies',
      gradient: [Color(0xFF00A86B), Color(0xFF34D399)],
    ),
    WalletCategory(
      name: 'Health Wallet',
      icon: Icons.favorite_rounded,
      contents: ['Medical Records', 'Reports', 'Prescriptions'],
      metric: '0',
      metricLabel: 'records',
      gradient: [Color(0xFF3B82F6), Color(0xFF38BDF8)],
    ),
    WalletCategory(
      name: 'Investment Wallet',
      icon: Icons.trending_up_rounded,
      contents: ['Gold', 'Stocks', 'Mutual Funds', 'Land'],
      metric: '0',
      metricLabel: 'holdings',
      gradient: [Color(0xFF34D399), Color(0xFF7DD3FC)],
    ),
    WalletCategory(
      name: 'Banking Wallet',
      icon: Icons.account_balance_rounded,
      contents: ['Accounts', 'Statements', 'Cards'],
      metric: '0',
      metricLabel: 'accounts',
      gradient: [Color(0xFF00875A), Color(0xFF00A86B)],
    ),
    WalletCategory(
      name: 'Password Vault',
      icon: Icons.lock_rounded,
      contents: ['Website Credentials', 'Bank Credentials'],
      metric: '0',
      metricLabel: 'passwords',
      gradient: [Color(0xFF0EA5A5), Color(0xFF34D399)],
    ),
  ];

  @override
  Future<WalletHubData> load() async {
    List<Document> docs;
    try {
      docs = await DocumentRepository.instance.listAll();
    } catch (_) {
      docs = const []; // offline / not signed in → everything reads as empty
    }

    // Count documents per wallet.
    final counts = <String, int>{};
    for (final d in docs) {
      counts[d.wallet] = (counts[d.wallet] ?? 0) + 1;
    }

    int totalRecords = 0;
    final updatedCategories = _categories.map((c) {
      final count = counts[c.name] ?? 0;
      totalRecords += count;
      return WalletCategory(
        name: c.name,
        icon: c.icon,
        contents: c.contents,
        metric: '$count',
        metricLabel: c.metricLabel,
        gradient: c.gradient,
      );
    }).toList();

    final usedMb = totalRecords * 4;

    // Recents: the five most-recently updated real documents.
    final recent = [...docs]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recents = [
      for (final d in recent.take(5))
        RecentItem(
          name: d.name,
          category: d.category ?? 'Document',
          lastOpened: _relativeTime(d.updatedAt),
          icon: _iconFor(d.category),
          color: _colorFor(d.wallet),
        ),
    ];

    return WalletHubData(
      overview: WalletOverview(
        totalWallets: _categories.length,
        totalRecords: totalRecords,
        protectedItems: totalRecords,
        lastBackup: totalRecords == 0 ? 'No documents yet' : 'Synced',
        storageUsedLabel: '$usedMb MB of 5 GB',
        storageFraction: (usedMb / 5120).clamp(0.0, 1.0),
      ),
      categories: updatedCategories,
      quickActions: const [
        QuickAction(
            label: 'Scan',
            icon: Icons.document_scanner_rounded,
            color: AppColors.primaryGreen),
        QuickAction(
            label: 'Upload',
            icon: Icons.upload_file_rounded,
            color: AppColors.lightBlue),
        QuickAction(
            label: 'Property',
            icon: Icons.add_home_rounded,
            color: Color(0xFF38BDF8)),
        QuickAction(
            label: 'Insurance',
            icon: Icons.add_moderator_rounded,
            color: AppColors.secondaryGreen),
        QuickAction(
            label: 'Investment',
            icon: Icons.savings_rounded,
            color: Color(0xFF34D399)),
        QuickAction(
            label: 'Password',
            icon: Icons.password_rounded,
            color: Color(0xFF0EA5A5)),
      ],
      recents: recents,
      security: const SecurityStatus(
        score: 100,
        vaultLocked: true,
        biometricEnabled: true,
        lastBackup: 'Synced',
        cloudSynced: true,
      ),
      insights: const [],
    );
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

  Color _colorFor(String wallet) {
    for (final c in _categories) {
      if (c.name == wallet) return c.gradient.first;
    }
    return AppColors.primaryGreen;
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}
