import 'package:flutter/material.dart';

import '../models/dashboard_models.dart' show SmartInsight;
import '../models/wallet_detail_models.dart';
import '../models/wallet_models.dart' show RecentItem, SecurityStatus, WalletCategory;
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
/// The same UI is reused for every wallet — [load] simply returns different
/// data for the given [WalletCategory].
abstract class WalletDetailRepository {
  Future<WalletDetailData> load(WalletCategory category);
  void addRecord(String walletName, DocumentRecord record);
  void updateRecord(String walletName, DocumentRecord record);
  void deleteRecord(String walletName, String recordId);
  int getRecordCount(String walletName, WalletCategory fallbackCategory);

  static WalletDetailRepository instance = SampleWalletDetailRepository();
}

class SampleWalletDetailRepository implements WalletDetailRepository {
  final Map<String, List<DocumentRecord>> _vault = {};

  List<DocumentRecord> _getOrCreateRecords(WalletCategory category) {
    return _vault.putIfAbsent(
      category.name,
      () => category.name == 'Identity Wallet'
          ? List<DocumentRecord>.from(_identityRecords)
          : _recordsFor(category),
    );
  }

  @override
  void addRecord(String walletName, DocumentRecord record) {
    final list = _vault[walletName] ?? [];
    _vault[walletName] = [record, ...list];
  }

  @override
  void updateRecord(String walletName, DocumentRecord record) {
    final list = _vault[walletName];
    if (list != null) {
      final idx = list.indexWhere((r) => r.id == record.id);
      if (idx != -1) {
        list[idx] = record;
      }
    }
  }

  @override
  void deleteRecord(String walletName, String recordId) {
    final list = _vault[walletName];
    if (list != null) {
      list.removeWhere((r) => r.id == recordId);
    }
  }

  @override
  int getRecordCount(String walletName, WalletCategory fallbackCategory) {
    if (!_vault.containsKey(walletName)) {
      _getOrCreateRecords(fallbackCategory);
    }
    return _vault[walletName]?.length ?? 0;
  }

  @override
  Future<WalletDetailData> load(WalletCategory category) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final records = _getOrCreateRecords(category);
    final active =
        records.where((r) => r.status == DocumentStatus.active).length;
    final expiring =
        records.where((r) => r.status == DocumentStatus.expiringSoon).length;
    final usedMb = records.length * 4; // ~4 MB / record for the demo

    return WalletDetailData(
      walletName: category.name,
      subtitle: _subtitleFor(category.name),
      icon: category.icon,
      gradient: category.gradient,
      lastUpdatedLabel: 'Updated Today',
      overview: DetailOverview(
        totalRecords: records.length,
        activeRecords: active,
        expiringSoon: expiring,
        lastAccessed: 'Today',
        storageUsedLabel: '$usedMb MB',
        storageFraction: (usedMb / 5120).clamp(0.0, 1.0),
      ),
      records: records,
      recents: _recentsFrom(records, category),
      insights: _insightsFor(category, expiring),
      security: const SecurityStatus(
        score: 98,
        vaultLocked: true,
        biometricEnabled: true,
        lastBackup: 'Today, 9:24 AM',
        cloudSynced: true,
      ),
      storage: StorageAnalytics(
        totalFiles: records.length,
        usedLabel: '$usedMb MB',
        availableLabel: '${(5120 - usedMb) ~/ 1024}.${((5120 - usedMb) % 1024) ~/ 103} GB',
        usedFraction: (usedMb / 5120).clamp(0.0, 1.0),
        monthlyUploads: 6,
        monthly: const [2.0, 4.0, 3.0, 5.0, 4.0, 6.0],
      ),
    );
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

  // ---- Records ------------------------------------------------------------

  List<DocumentRecord> _recordsFor(WalletCategory category) {
    if (category.name == 'Identity Wallet') return _identityRecords;
    // Data-driven fallback: build records from the wallet's content labels so
    // every wallet type renders meaningfully without bespoke datasets.
    final statuses = [
      DocumentStatus.active,
      DocumentStatus.active,
      DocumentStatus.expiringSoon,
      DocumentStatus.shared,
      DocumentStatus.archived,
    ];
    final contents = category.contents;
    return [
      for (var i = 0; i < contents.length; i++)
        DocumentRecord(
          id: '${category.name}-$i',
          name: contents[i],
          category: _shortName(category.name),
          icon: category.icon,
          uploadedAt: DateTime(2026, 6, 2 + i * 3),
          updatedAt: DateTime(2026, 6, 20 + i),
          expiresAt: i.isEven ? DateTime(2026, 11, 10 + i) : null,
          status: statuses[i % statuses.length],
          recordNumber: 'REC-${1000 + i}',
          tags: const ['important'],
          isFavorite: i == 0,
        ),
    ];
  }

  String _shortName(String walletName) =>
      walletName.replaceAll(' Wallet', '').replaceAll(' Vault', '');

  static final List<DocumentRecord> _identityRecords = [
    DocumentRecord(
      id: 'id-aadhaar',
      name: 'Aadhaar Card',
      category: 'Identity',
      icon: Icons.fingerprint_rounded,
      uploadedAt: DateTime(2025, 3, 12),
      updatedAt: DateTime(2026, 6, 28),
      status: DocumentStatus.active,
      recordNumber: 'XXXX-XXXX-1234',
      tags: const ['govt', 'kyc'],
      isFavorite: true,
    ),
    DocumentRecord(
      id: 'id-pan',
      name: 'PAN Card',
      category: 'Identity',
      icon: Icons.badge_rounded,
      uploadedAt: DateTime(2025, 1, 8),
      updatedAt: DateTime(2026, 6, 20),
      status: DocumentStatus.active,
      recordNumber: 'ABCDE1234F',
      tags: const ['govt', 'tax'],
      isFavorite: true,
    ),
    DocumentRecord(
      id: 'id-passport',
      name: 'Passport',
      category: 'Identity',
      icon: Icons.book_rounded,
      uploadedAt: DateTime(2024, 9, 2),
      updatedAt: DateTime(2026, 5, 14),
      expiresAt: DateTime(2026, 10, 30),
      status: DocumentStatus.expiringSoon,
      recordNumber: 'P1234567',
      tags: const ['travel', 'govt'],
    ),
    DocumentRecord(
      id: 'id-dl',
      name: 'Driving License',
      category: 'Identity',
      icon: Icons.directions_car_rounded,
      uploadedAt: DateTime(2025, 2, 18),
      updatedAt: DateTime(2026, 4, 9),
      expiresAt: DateTime(2027, 2, 18),
      status: DocumentStatus.active,
      recordNumber: 'MH-0420231234',
      tags: const ['vehicle', 'govt'],
    ),
    DocumentRecord(
      id: 'id-voter',
      name: 'Voter ID',
      category: 'Identity',
      icon: Icons.how_to_vote_rounded,
      uploadedAt: DateTime(2024, 11, 22),
      updatedAt: DateTime(2026, 3, 1),
      status: DocumentStatus.shared,
      recordNumber: 'WB/12/345/678',
      tags: const ['govt'],
    ),
  ];

  // ---- Recents / insights -------------------------------------------------

  List<RecentItem> _recentsFrom(
      List<DocumentRecord> records, WalletCategory category) {
    const times = ['2h ago', '5h ago', 'Yesterday', '2 days ago', '4 days ago'];
    return [
      for (var i = 0; i < records.length && i < 5; i++)
        RecentItem(
          name: records[i].name,
          category: records[i].category,
          lastOpened: times[i % times.length],
          icon: records[i].icon,
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
      const SmartInsight(
        message: '3 documents need a fresh backup to stay protected.',
        icon: Icons.cloud_upload_rounded,
        accent: AppColors.lightBlue,
      ),
      const SmartInsight(
        message: '2 records are missing tags — add them to find files faster.',
        icon: Icons.sell_rounded,
        accent: AppColors.primaryGreen,
      ),
      SmartInsight(
        message: 'A ${_shortName(category.name)} record requires verification.',
        icon: Icons.verified_rounded,
        accent: const Color(0xFF3B82F6),
      ),
    ];
  }
}
