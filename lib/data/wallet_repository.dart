import 'package:flutter/material.dart';

import '../models/dashboard_models.dart' show QuickAction, SmartInsight;
import '../models/wallet_models.dart';
import '../theme/app_theme.dart';
import 'wallet_detail_repository.dart';

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

/// Source of Wallet Hub data. The screen depends only on this abstraction;
/// swap [SampleWalletRepository] for a Supabase/vault-backed impl to go live.
abstract class WalletRepository {
  Future<WalletHubData> load();

  static WalletRepository instance = SampleWalletRepository();
}


class SampleWalletRepository implements WalletRepository {
  static const List<WalletCategory> _categories = [
    WalletCategory(
      name: 'Identity Wallet',
      icon: Icons.badge_rounded,
      contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
      metric: '5',
      metricLabel: 'documents',
      gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
    ),
    WalletCategory(
      name: 'Document Wallet',
      icon: Icons.folder_shared_rounded,
      contents: ['Certificates', 'Contracts', 'Personal Documents'],
      metric: '24',
      metricLabel: 'files',
      gradient: [Color(0xFF3B82F6), Color(0xFF7DD3FC)],
    ),
    WalletCategory(
      name: 'Property Wallet',
      icon: Icons.home_work_rounded,
      contents: ['Property Documents', 'Tax Records', 'Sale Deeds'],
      metric: '3',
      metricLabel: 'properties',
      gradient: [Color(0xFF38BDF8), Color(0xFF7DD3FC)],
    ),
    WalletCategory(
      name: 'Insurance Wallet',
      icon: Icons.shield_rounded,
      contents: ['Health', 'Vehicle', 'Life Insurance'],
      metric: '5',
      metricLabel: 'policies',
      gradient: [Color(0xFF00A86B), Color(0xFF34D399)],
    ),
    WalletCategory(
      name: 'Health Wallet',
      icon: Icons.favorite_rounded,
      contents: ['Medical Records', 'Reports', 'Prescriptions'],
      metric: '12',
      metricLabel: 'records',
      gradient: [Color(0xFF3B82F6), Color(0xFF38BDF8)],
    ),
    WalletCategory(
      name: 'Investment Wallet',
      icon: Icons.trending_up_rounded,
      contents: ['Gold', 'Stocks', 'Mutual Funds', 'Land'],
      metric: '₹48.6L',
      metricLabel: 'portfolio',
      gradient: [Color(0xFF34D399), Color(0xFF7DD3FC)],
    ),
    WalletCategory(
      name: 'Banking Wallet',
      icon: Icons.account_balance_rounded,
      contents: ['Accounts', 'Statements', 'Cards'],
      metric: '4',
      metricLabel: 'accounts',
      gradient: [Color(0xFF00875A), Color(0xFF00A86B)],
    ),
    WalletCategory(
      name: 'Password Vault',
      icon: Icons.lock_rounded,
      contents: ['Website Credentials', 'Bank Credentials'],
      metric: '38',
      metricLabel: 'passwords',
      gradient: [Color(0xFF0EA5A5), Color(0xFF34D399)],
    ),
  ];

  @override
  Future<WalletHubData> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final detailRepo = WalletDetailRepository.instance;

    int totalRecords = 0;
    final updatedCategories = _categories.map((c) {
      if (c.metricLabel != 'portfolio') {
        final count = detailRepo.getRecordCount(c.name, c);
        totalRecords += count;
        return WalletCategory(
          name: c.name,
          icon: c.icon,
          contents: c.contents,
          metric: '$count',
          metricLabel: c.metricLabel,
          gradient: c.gradient,
        );
      } else {
        return c;
      }
    }).toList();

    final usedMb = totalRecords * 4;

    return WalletHubData(
      overview: WalletOverview(
        totalWallets: 8,
        totalRecords: totalRecords,
        protectedItems: totalRecords,
        lastBackup: 'Today, 9:24 AM',
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
      recents: const [
        RecentItem(
            name: 'PAN Card',
            category: 'Identity',
            lastOpened: '2h ago',
            icon: Icons.badge_rounded,
            color: AppColors.primaryGreen),
        RecentItem(
            name: 'Passport',
            category: 'Identity',
            lastOpened: '5h ago',
            icon: Icons.book_rounded,
            color: AppColors.lightBlue),
        RecentItem(
            name: 'Property Deed — Pune',
            category: 'Property',
            lastOpened: 'Yesterday',
            icon: Icons.home_work_rounded,
            color: Color(0xFF38BDF8)),
        RecentItem(
            name: 'Health Report',
            category: 'Health',
            lastOpened: '2 days ago',
            icon: Icons.favorite_rounded,
            color: Color(0xFF3B82F6)),
        RecentItem(
            name: 'Car Insurance Policy',
            category: 'Insurance',
            lastOpened: '3 days ago',
            icon: Icons.shield_rounded,
            color: AppColors.secondaryGreen),
      ],
      security: const SecurityStatus(
        score: 98,
        vaultLocked: true,
        biometricEnabled: true,
        lastBackup: 'Today, 9:24 AM',
        cloudSynced: true,
      ),
      insights: const [
        SmartInsight(
            message: '3 documents require attention before they expire.',
            icon: Icons.description_rounded,
            accent: AppColors.lightBlue),
        SmartInsight(
            message: 'Car insurance expires in 12 days. Renew to stay covered.',
            icon: Icons.shield_rounded,
            accent: AppColors.warning),
        SmartInsight(
            message: 'Property tax is due next month for your Pune flat.',
            icon: Icons.home_work_rounded,
            accent: AppColors.primaryGreen),
        SmartInsight(
            message: 'A health checkup reminder is available to schedule.',
            icon: Icons.health_and_safety_rounded,
            accent: Color(0xFF3B82F6)),
      ],
    );
  }
}
