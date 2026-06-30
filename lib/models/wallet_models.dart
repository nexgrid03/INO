import 'package:flutter/material.dart';

/// Typed models backing the Wallet Hub screen.
///
/// Like the dashboard models these are UI-agnostic plain objects, hydrated
/// today by `WalletRepository`'s sample implementation and tomorrow by Supabase
/// / the vault service — without touching the widgets.

// ---------------------------------------------------------------------------
// 2. Wallet overview hero
// ---------------------------------------------------------------------------

class WalletOverview {
  const WalletOverview({
    required this.totalWallets,
    required this.totalRecords,
    required this.protectedItems,
    required this.lastBackup,
    required this.storageUsedLabel,
    required this.storageFraction,
  });

  final int totalWallets;
  final int totalRecords;
  final int protectedItems;
  final String lastBackup; // "Today, 9:24 AM"
  final String storageUsedLabel; // "1.2 GB of 5 GB"
  final double storageFraction; // 0..1 for the bar
}

// ---------------------------------------------------------------------------
// 3. Wallet categories grid
// ---------------------------------------------------------------------------

class WalletCategory {
  const WalletCategory({
    required this.name,
    required this.icon,
    required this.contents,
    required this.metric,
    required this.metricLabel,
    required this.gradient,
  });

  final String name; // "Identity Wallet"
  final IconData icon;
  final List<String> contents; // ["Aadhaar", "PAN", …]
  final String metric; // "5", "₹48.6L"
  final String metricLabel; // "documents", "portfolio"
  final List<Color> gradient; // icon chip + accent
}

// ---------------------------------------------------------------------------
// 5. Recently accessed
// ---------------------------------------------------------------------------

class RecentItem {
  const RecentItem({
    required this.name,
    required this.category,
    required this.lastOpened,
    required this.icon,
    required this.color,
  });

  final String name; // "PAN Card"
  final String category; // badge: "Identity"
  final String lastOpened; // "2h ago"
  final IconData icon;
  final Color color;
}

// ---------------------------------------------------------------------------
// 6. Security center
// ---------------------------------------------------------------------------

class SecurityStatus {
  const SecurityStatus({
    required this.score,
    required this.vaultLocked,
    required this.biometricEnabled,
    required this.lastBackup,
    required this.cloudSynced,
  });

  final int score; // 0..100
  final bool vaultLocked;
  final bool biometricEnabled;
  final String lastBackup;
  final bool cloudSynced;
}
