import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Typed data models that back the Home dashboard.
///
/// These are intentionally UI-agnostic plain Dart objects. Today they are
/// filled by `DashboardRepository`'s sample implementation; tomorrow the same
/// shapes can be hydrated from Supabase tables or live pricing APIs without
/// touching a single widget. Keep the widgets reading *these* types, not raw
/// maps, so the integration swap is a one-file change.

// ---------------------------------------------------------------------------
// Home hero (net worth + headline metrics)
// ---------------------------------------------------------------------------

/// Backs the Home dashboard hero card: total net worth, monthly growth, a small
/// trend series, and the four headline metrics shown along the bottom.
class HomeHero {
  const HomeHero({
    required this.netWorth,
    required this.growthPercent,
    required this.growthAmount,
    required this.trend,
    required this.assets,
    required this.documents,
    required this.pendingTasks,
    required this.protectedItems,
  });

  final String netWorth; // pre-formatted, e.g. "₹1.24 Cr"
  final double growthPercent; // monthly growth, e.g. 12.2
  final String growthAmount; // pre-formatted gain, e.g. "₹13.52 L"
  final List<double> trend; // net-worth series for the mini graph
  final int assets;
  final int documents;
  final int pendingTasks;
  final int protectedItems;

  bool get isUp => growthPercent >= 0;
}

// ---------------------------------------------------------------------------
// 2. Live market intelligence
// ---------------------------------------------------------------------------

enum TrendDirection { up, down, flat }

/// One live commodity / fuel quote shown in the market carousel.
class MarketQuote {
  const MarketQuote({
    required this.label,
    required this.icon,
    required this.price,
    required this.unit,
    required this.changePercent,
    required this.spark,
    required this.gradient,
    this.accent = const Color(0xFF00A86B),
    this.filled = false,
    this.location,
  });

  final String label; // "Gold", "Petrol", …
  final IconData icon;
  final String price; // pre-formatted, e.g. "₹7,412"
  final String unit; // "/ gram", "/ litre"
  final double changePercent; // +0.82, -0.31 …
  final List<double> spark; // mini trend series (oldest → newest)
  final List<Color> gradient; // premium accent for the icon tile / card fill
  final Color accent; // flat accent (e.g. gold amber, silver grey)
  final bool filled; // true → whole card is a gradient hero (e.g. Gold)
  final String? location; // for fuels: "Mumbai"

  TrendDirection get trend => changePercent > 0
      ? TrendDirection.up
      : changePercent < 0
          ? TrendDirection.down
          : TrendDirection.flat;

  /// Returns a copy with live values swapped in (keeps icon/gradient/spark).
  MarketQuote copyWith({
    String? price,
    String? unit,
    double? changePercent,
  }) =>
      MarketQuote(
        label: label,
        icon: icon,
        price: price ?? this.price,
        unit: unit ?? this.unit,
        changePercent: changePercent ?? this.changePercent,
        spark: spark,
        gradient: gradient,
        accent: accent,
        filled: filled,
        location: location,
      );
}

// ---------------------------------------------------------------------------
// 3. Life overview summary
// ---------------------------------------------------------------------------

class LifeOverviewItem {
  const LifeOverviewItem({
    required this.label,
    required this.icon,
    required this.count,
    required this.status,
    required this.lastUpdated,
    required this.color,
    this.gradient,
  });

  final String label;
  final IconData icon;
  final String count; // "24", "₹48.6L" …
  final String status; // "All synced", "2 expiring"
  final String lastUpdated; // "Updated today"
  final Color color;

  /// Optional premium gradient for the icon tile (e.g. Net Worth).
  final List<Color>? gradient;
}

// ---------------------------------------------------------------------------
// 4. Priority center
// ---------------------------------------------------------------------------

enum PriorityLevel { critical, important, info }

class PriorityItem {
  const PriorityItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.level,
    required this.due,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final PriorityLevel level;
  final String due; // "Due in 3 days"
}

// ---------------------------------------------------------------------------
// 5 & 14. Quick actions / FAB actions
// ---------------------------------------------------------------------------

class QuickAction {
  const QuickAction({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

/// Maps a canonical [QuickAction.label] (kept in English for dispatch) to its
/// localized display string. Unknown labels pass through unchanged.
String localizedQuickActionLabel(AppLocalizations l10n, String label) {
  const map = {
    'Add Document': 'addDocument',
    'Add Reminder': 'addReminder',
    'Add Investment': 'addInvestment',
    'Add Property': 'addProperty',
    'Add Insurance': 'addInsurance',
    'Add Health Record': 'addHealthRecord',
    'Add Password': 'addPassword',
    'Scan': 'scan',
    'Scan Document': 'scanDocument',
    'Upload PDF': 'uploadPdf',
    'Import Image': 'importImage',
    'Create Category': 'createCategory',
  };
  final key = map[label];
  return key == null ? label : l10n.t(key);
}

// ---------------------------------------------------------------------------
// 6. Wallet ecosystem
// ---------------------------------------------------------------------------

class WalletSummary {
  const WalletSummary({
    required this.name,
    required this.icon,
    required this.itemCount,
    required this.lastActivity,
    required this.status,
    required this.gradient,
  });

  final String name;
  final IconData icon;
  final int itemCount;
  final String lastActivity;
  final String status;
  final List<Color> gradient;
}

// ---------------------------------------------------------------------------
// 7. Investment overview
// ---------------------------------------------------------------------------

class AssetAllocation {
  const AssetAllocation({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value; // absolute amount
  final Color color;
}

class InvestmentSummary {
  const InvestmentSummary({
    required this.invested,
    required this.currentValue,
    required this.allocations,
    required this.growth,
  });

  final double invested;
  final double currentValue;
  final List<AssetAllocation> allocations;
  final List<double> growth; // portfolio value series for the chart

  double get profit => currentValue - invested;
  double get returnPercent => invested == 0 ? 0 : (profit / invested) * 100;
  bool get isGain => profit >= 0;
}

// ---------------------------------------------------------------------------
// 8. Property overview
// ---------------------------------------------------------------------------

class PropertySummary {
  const PropertySummary({
    required this.totalProperties,
    required this.portfolioValue,
    required this.ownership,
    required this.recentUpdate,
  });

  final int totalProperties;
  final double portfolioValue;
  final String ownership; // "3 owned · 1 jointly held"
  final String recentUpdate;
}

// ---------------------------------------------------------------------------
// 9. Health overview
// ---------------------------------------------------------------------------

class HealthSummary {
  const HealthSummary({
    required this.bloodGroup,
    required this.recordsCount,
    required this.nextCheckup,
    required this.emergencyContacts,
  });

  final String bloodGroup;
  final int recordsCount;
  final String nextCheckup;
  final int emergencyContacts;
}

// ---------------------------------------------------------------------------
// 10. Insurance overview
// ---------------------------------------------------------------------------

class InsuranceSummary {
  const InsuranceSummary({
    required this.activePolicies,
    required this.expiringSoon,
    required this.nextPremium,
    required this.totalCover,
  });

  final int activePolicies;
  final int expiringSoon;
  final String nextPremium; // "₹12,400 · 8 Jul"
  final String totalCover; // "₹1.2 Cr"
}

// ---------------------------------------------------------------------------
// 11. Family & events
// ---------------------------------------------------------------------------

enum FamilyEventType { birthday, anniversary, event }

class FamilyEvent {
  const FamilyEvent({
    required this.name,
    required this.type,
    required this.date,
    required this.relativeDay,
  });

  final String name;
  final FamilyEventType type;
  final String date; // "12 Jul"
  final String relativeDay; // "in 3 days"

  IconData get icon {
    switch (type) {
      case FamilyEventType.birthday:
        return Icons.cake_rounded;
      case FamilyEventType.anniversary:
        return Icons.favorite_rounded;
      case FamilyEventType.event:
        return Icons.celebration_rounded;
    }
  }
}

// ---------------------------------------------------------------------------
// 12. Recent activity timeline
// ---------------------------------------------------------------------------

/// The kind of activity — drives the icon/colour and the history filters.
enum ActivityKind { document, asset, reminder, backup, insurance, security, system }

class ActivityItem {
  const ActivityItem({
    required this.title,
    required this.icon,
    required this.time,
    required this.color,
    this.subtitle,
    this.at,
    this.name,
    this.kind = ActivityKind.system,
  });

  final String title;
  final IconData icon;
  final String time; // "2h ago", "Yesterday"
  final Color color;

  /// Optional one-line description shown under the title on the history page.
  final String? subtitle;

  /// The real timestamp, used for sorting / grouping / filtering when available.
  final DateTime? at;

  /// The raw document / reminder name (user data — not translated), used to
  /// build the localized title at render time.
  final String? name;

  final ActivityKind kind;

  /// The title in the active language, built from [kind] + [name] so it
  /// re-translates live on language switch. Falls back to [title].
  String localizedTitle(AppLocalizations l10n) {
    switch (kind) {
      case ActivityKind.document:
        return '${name ?? ''} ${l10n.t('uploaded')}'.trim();
      case ActivityKind.reminder:
        return '${l10n.t('reminder')} · ${name ?? ''}';
      case ActivityKind.backup:
        return l10n.t('cloudBackupCompleted');
      default:
        return title;
    }
  }

  /// A localized relative time for recent items; older items keep [time].
  String localizedTime(AppLocalizations l10n) {
    final t = at;
    if (t == null) return time;
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return l10n.t('justNow');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${l10n.t('minutesAgo')}';
    if (diff.inHours < 24) return '${diff.inHours} ${l10n.t('hoursAgo')}';
    if (diff.inDays == 1) return l10n.t('yesterday');
    if (diff.inDays < 7) return '${diff.inDays} ${l10n.t('daysAgo')}';
    return time; // absolute date fallback
  }
}

// ---------------------------------------------------------------------------
// 13. Smart insights
// ---------------------------------------------------------------------------

class SmartInsight {
  const SmartInsight({
    required this.message,
    required this.icon,
    required this.accent,
  });

  final String message;
  final IconData icon;
  final Color accent;
}
