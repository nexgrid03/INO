import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Models backing the reusable Wallet Detail screen. The same UI renders every
/// wallet type — only this data changes.

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact, intl-free date format: "12 Jun 2026".
String inoFormatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

// ---------------------------------------------------------------------------
// Status system
// ---------------------------------------------------------------------------

enum DocumentStatus { active, expiringSoon, expired, shared, archived }

extension DocumentStatusX on DocumentStatus {
  String get label {
    switch (this) {
      case DocumentStatus.active:
        return 'Active';
      case DocumentStatus.expiringSoon:
        return 'Expiring Soon';
      case DocumentStatus.expired:
        return 'Expired';
      case DocumentStatus.shared:
        return 'Shared';
      case DocumentStatus.archived:
        return 'Archived';
    }
  }

  Color get color {
    switch (this) {
      case DocumentStatus.active:
        return AppColors.primaryGreen; // green
      case DocumentStatus.expiringSoon:
        return AppColors.warning; // orange
      case DocumentStatus.expired:
        return AppColors.critical; // red
      case DocumentStatus.shared:
        return AppColors.lightBlue; // blue
      case DocumentStatus.archived:
        return const Color(0xFF94A3B8); // gray
    }
  }
}

// ---------------------------------------------------------------------------
// Filters & sorting
// ---------------------------------------------------------------------------

enum WalletFilter { all, active, expiringSoon, favorites, shared, archived }

extension WalletFilterX on WalletFilter {
  String get label {
    switch (this) {
      case WalletFilter.all:
        return 'All';
      case WalletFilter.active:
        return 'Active';
      case WalletFilter.expiringSoon:
        return 'Expiring Soon';
      case WalletFilter.favorites:
        return 'Favorites';
      case WalletFilter.shared:
        return 'Shared';
      case WalletFilter.archived:
        return 'Archived';
    }
  }
}

enum WalletSort { recent, az, uploadDate, expiryDate }

extension WalletSortX on WalletSort {
  String get label {
    switch (this) {
      case WalletSort.recent:
        return 'Recent';
      case WalletSort.az:
        return 'A–Z';
      case WalletSort.uploadDate:
        return 'Upload Date';
      case WalletSort.expiryDate:
        return 'Expiry Date';
    }
  }
}

// ---------------------------------------------------------------------------
// Document record
// ---------------------------------------------------------------------------

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.uploadedAt,
    required this.updatedAt,
    required this.status,
    this.expiresAt,
    this.recordNumber,
    this.tags = const [],
    this.isFavorite = false,
    this.filePath,
  });

  final String id;
  final String name;
  final String category;
  final IconData icon;
  final DateTime uploadedAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final DocumentStatus status;
  final String? recordNumber;
  final List<String> tags;
  final bool isFavorite;

  /// Storage object path of the actual uploaded file (null when there is no
  /// backing file — e.g. a record with nothing yet uploaded).
  final String? filePath;

  DocumentRecord copyWith({
    String? name,
    String? category,
    DocumentStatus? status,
    bool? isFavorite,
  }) {
    return DocumentRecord(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      icon: icon,
      uploadedAt: uploadedAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      recordNumber: recordNumber,
      tags: tags,
      isFavorite: isFavorite ?? this.isFavorite,
      filePath: filePath,
    );
  }

  /// Free-text match across name, category, tags and record number.
  bool matches(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        (recordNumber?.toLowerCase().contains(q) ?? false) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }
}

// ---------------------------------------------------------------------------
// Supporting cards (overview & storage)
// ---------------------------------------------------------------------------

class DetailOverview {
  const DetailOverview({
    required this.totalRecords,
    required this.activeRecords,
    required this.expiringSoon,
    required this.lastAccessed,
    required this.storageUsedLabel,
    required this.storageFraction,
  });

  final int totalRecords;
  final int activeRecords;
  final int expiringSoon;
  final String lastAccessed; // "Today"
  final String storageUsedLabel; // "40 MB"
  final double storageFraction; // 0..1
}

class StorageAnalytics {
  const StorageAnalytics({
    required this.totalFiles,
    required this.usedLabel,
    required this.availableLabel,
    required this.usedFraction,
    required this.monthlyUploads,
    required this.monthly,
  });

  final int totalFiles;
  final String usedLabel; // "40 MB"
  final String availableLabel; // "4.96 GB"
  final double usedFraction; // 0..1
  final int monthlyUploads;
  final List<double> monthly; // small bar series
}
