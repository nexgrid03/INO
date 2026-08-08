import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dashboard_models.dart' show QuickAction, SmartInsight;
import '../models/document.dart';
import '../models/wallet_models.dart';
import '../repositories/document_repository.dart';
import '../services/card_store.dart';
import '../services/investment_store.dart';
import '../services/password_store.dart';
import '../services/property_store.dart';
import '../services/wallet_store.dart';
import '../theme/app_theme.dart';

/// Aggregate read model for the Wallet Hub - fetched once, fanned out to the
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
  Future<WalletHubData> load({List<Document>? documents});

  static WalletRepository instance = SupabaseWalletRepository();
}

class SupabaseWalletRepository implements WalletRepository {
  /// The eight wallet "buckets" the app offers. These are the app's structure
  /// (not stored data) - the counts below are filled in from real documents.
  /// Gradients match Home My Vaults accents ([AppColors.vaultAccentFor]).
  static final List<WalletCategory> _categories = [
    WalletCategory(
      name: 'Identity Wallet',
      icon: Icons.badge_rounded,
      contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
      metric: '0',
      metricLabel: 'documents',
      gradient: AppColors.vaultGradientFor('Identity Wallet'),
    ),
    WalletCategory(
      name: 'Document Wallet',
      icon: Icons.folder_shared_rounded,
      contents: ['Certificates', 'Contracts', 'Personal Documents'],
      metric: '0',
      metricLabel: 'files',
      gradient: AppColors.vaultGradientFor('Document Wallet'),
    ),
    WalletCategory(
      name: 'Property Wallet',
      icon: Icons.home_work_rounded,
      contents: ['Property Documents', 'Tax Records', 'Sale Deeds'],
      metric: '0',
      metricLabel: 'properties',
      gradient: AppColors.vaultGradientFor('Property Wallet'),
    ),
    WalletCategory(
      name: 'Insurance Wallet',
      icon: Icons.shield_rounded,
      contents: ['Health', 'Vehicle', 'Life Insurance'],
      metric: '0',
      metricLabel: 'policies',
      gradient: AppColors.vaultGradientFor('Insurance Wallet'),
    ),
    WalletCategory(
      name: 'Health Wallet',
      icon: Icons.favorite_rounded,
      contents: ['Medical Records', 'Reports', 'Prescriptions'],
      metric: '0',
      metricLabel: 'records',
      gradient: AppColors.vaultGradientFor('Health Wallet'),
    ),
    WalletCategory(
      name: 'Investment Wallet',
      icon: Icons.trending_up_rounded,
      contents: ['Gold', 'Stocks', 'Mutual Funds', 'Land'],
      metric: '0',
      metricLabel: 'holdings',
      gradient: AppColors.vaultGradientFor('Investment Wallet'),
    ),
    WalletCategory(
      name: 'Banking Wallet',
      icon: Icons.account_balance_rounded,
      contents: ['Accounts', 'Statements', 'Cards'],
      metric: '0',
      metricLabel: 'accounts',
      gradient: AppColors.vaultGradientFor('Banking Wallet'),
    ),
    WalletCategory(
      name: 'Password Vault',
      icon: Icons.lock_rounded,
      contents: ['Website Credentials', 'Bank Credentials'],
      metric: '0',
      metricLabel: 'passwords',
      gradient: AppColors.vaultGradientFor('Password Vault'),
    ),
  ];

  /// The eight wallets the app ships with (never deletable).
  static List<WalletCategory> get builtIns => _categories;

  /// Every wallet the user has: the built-ins followed by the wallets they
  /// created themselves ([CustomWalletStore]). Every picker, filter and the hub
  /// grid read this, so a new wallet shows up everywhere at once.
  static List<WalletCategory> get categories =>
      [..._categories, ...CustomWalletStore.instance.categories];

  /// Wallets a DOCUMENT can be filed under. The Password Vault is excluded:
  /// since the nickname simplification its table stores only
  /// nickname + password rows and has no document columns, so saving or moving
  /// a document into it would fail at the database.
  static List<WalletCategory> get documentWallets =>
      [for (final c in categories) if (c.name != 'Password Vault') c];

  /// Finds a wallet category by its full name (e.g. "Insurance Wallet").
  /// Case-insensitive so a custom wallet still resolves if a document row
  /// stored it with different casing.
  static WalletCategory? categoryFor(String name) {
    final id = name.trim().toLowerCase();
    for (final c in categories) {
      if (c.name.toLowerCase() == id) return c;
    }
    return null;
  }

  @override
  Future<WalletHubData> load({List<Document>? documents}) async {
    List<Document> docs;
    if (documents != null) {
      docs = documents;
    } else {
      try {
        docs = await DocumentRepository.instance.listAll();
      } catch (_) {
        docs = const []; // offline / not signed in → everything reads as empty
      }
    }

    // Count documents per wallet.
    final counts = <String, int>{};
    for (final d in docs) {
      counts[d.wallet] = (counts[d.wallet] ?? 0) + 1;
    }

    // The four data wallets count their own records rather than documents -
    // a Property Wallet holding three properties should say so, not "0 files".
    // Hydration is kicked off but never awaited: the stores are already loaded
    // by `main()` in the real app, and blocking the whole hub on four
    // `shared_preferences` reads would delay every other wallet's card.
    unawaited(PropertyStore.instance.ensureLoaded());
    unawaited(InvestmentStore.instance.ensureLoaded());
    unawaited(CardStore.instance.ensureLoaded());
    unawaited(PasswordStore.instance.ensureLoaded());

    int totalRecords = 0;
    // Built-ins + the user's own wallets, each carrying its live record count.
    final all = categories;
    final updatedCategories = all.map((c) {
      final module = _moduleCountFor(c.name);
      final count = module?.$1 ?? (counts[c.name] ?? 0);
      totalRecords += count;
      return WalletCategory(
        name: c.name,
        icon: c.icon,
        contents: c.contents,
        metric: '$count',
        metricLabel: module?.$2 ?? c.metricLabel,
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
        totalWallets: all.length,
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
            color: AppColors.skyBrand),
        QuickAction(
            label: 'Upload',
            icon: Icons.upload_file_rounded,
            color: AppColors.skyBrandSecondary),
        QuickAction(
            label: 'Property',
            icon: Icons.add_home_rounded,
            color: AppColors.skyBrandSecondary),
        QuickAction(
            label: 'Insurance',
            icon: Icons.add_moderator_rounded,
            color: AppColors.skyBrandSecondary),
        QuickAction(
            label: 'Investment',
            icon: Icons.savings_rounded,
            color: AppColors.skyBrandSecondary),
        QuickAction(
            label: 'Password',
            icon: Icons.password_rounded,
            color: AppColors.skyBrand),
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

  /// The (count, label) a data wallet reports on its hub card, or null for the
  /// document wallets - which keep counting documents.
  (int, String)? _moduleCountFor(String walletName) {
    switch (walletName) {
      case 'Property Wallet':
        return (PropertyStore.instance.count, 'properties');
      case 'Investment Wallet':
        return (InvestmentStore.instance.count, 'holdings');
      case 'Banking Wallet':
        return (CardStore.instance.count, 'cards');
      case 'Password Vault':
        return (PasswordStore.instance.count, 'passwords');
      default:
        return null;
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

  Color _colorFor(String wallet) =>
      categoryFor(wallet)?.gradient.first ?? AppColors.skyBrand;

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}
