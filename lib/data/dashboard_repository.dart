import 'package:flutter/material.dart';

import '../models/dashboard_models.dart';
import '../theme/app_theme.dart';

/// Read model that bundles everything the Home dashboard renders in one shot.
///
/// A single aggregate keeps the screen's wiring trivial: fetch once, fan the
/// pieces out to the section widgets. When this moves to a real backend each
/// field can be hydrated by its own query/endpoint inside the repository.
class DashboardData {
  const DashboardData({
    required this.hero,
    required this.market,
    required this.lifeOverview,
    required this.priorities,
    required this.quickActions,
    required this.fabActions,
    required this.wallets,
    required this.investment,
    required this.property,
    required this.health,
    required this.insurance,
    required this.familyEvents,
    required this.activity,
    required this.insights,
  });

  final HomeHero hero;
  final List<MarketQuote> market;
  final List<LifeOverviewItem> lifeOverview;
  final List<PriorityItem> priorities;
  final List<QuickAction> quickActions;
  final List<QuickAction> fabActions;
  final List<WalletSummary> wallets;
  final InvestmentSummary investment;
  final PropertySummary property;
  final HealthSummary health;
  final InsuranceSummary insurance;
  final List<FamilyEvent> familyEvents;
  final List<ActivityItem> activity;
  final List<SmartInsight> insights;
}

/// Source of dashboard data.
///
/// The app talks to this abstraction only. Swap [SampleDashboardRepository] for
/// a `SupabaseDashboardRepository` (or a live-pricing-backed one) later and the
/// UI is unchanged — that is what "real-time data integration ready" means here.
abstract class DashboardRepository {
  Future<DashboardData> load();

  /// The active implementation. Replace this single line to go live.
  static DashboardRepository instance = SampleDashboardRepository();
}

/// In-memory sample data with realistic Indian-context values.
class SampleDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> load() async {
    // Simulate a tiny network latency so skeleton/entrance states feel real.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return _data;
  }

  static final DashboardData _data = DashboardData(
    hero: const HomeHero(
      netWorth: '₹1.24 Cr',
      growthPercent: 12.2,
      growthAmount: '₹13.52 L',
      trend: [38, 39, 40.5, 41, 43, 44.2, 46, 47.1, 48.6],
      assets: 12,
      documents: 24,
      pendingTasks: 3,
      protectedItems: 6,
    ),
    market: const [
      MarketQuote(
        label: 'Gold 24K',
        icon: Icons.workspace_premium_rounded,
        price: '₹7,412',
        unit: '/ gram',
        changePercent: 0.82,
        spark: [70, 71, 70.5, 72, 71.6, 73, 73.4, 74.1],
        // Gold → hero gradient card (green → light blue).
        gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
        accent: Color(0xFFE0A100), // amber
        filled: true,
      ),
      MarketQuote(
        label: 'Silver',
        icon: Icons.brightness_7_rounded,
        price: '₹92,300',
        unit: '/ kg',
        changePercent: -0.41,
        spark: [94, 93.6, 93.8, 93.1, 92.7, 92.9, 92.4, 92.3],
        // Silver → sky-blue glass.
        gradient: [Color(0xFF7DD3FC), Color(0xFF38BDF8)],
        accent: Color(0xFF8C9BA5), // grey
      ),
      MarketQuote(
        label: 'Petrol',
        icon: Icons.local_gas_station_rounded,
        price: '₹106.31',
        unit: '/ litre',
        changePercent: 0.12,
        location: 'Mumbai',
        spark: [105.9, 106.0, 106.1, 106.0, 106.2, 106.2, 106.3, 106.31],
        // Petrol → green accent.
        gradient: [Color(0xFF00A86B), Color(0xFF34D399)],
        accent: Color(0xFF00A86B),
      ),
      MarketQuote(
        label: 'Diesel',
        icon: Icons.local_shipping_rounded,
        price: '₹94.27',
        unit: '/ litre',
        changePercent: -0.08,
        location: 'Mumbai',
        spark: [94.5, 94.4, 94.4, 94.3, 94.35, 94.3, 94.28, 94.27],
        // Diesel → blue accent.
        gradient: [Color(0xFF38BDF8), Color(0xFF7DD3FC)],
        accent: Color(0xFF38BDF8),
      ),
    ],
    lifeOverview: const [
      LifeOverviewItem(
        label: 'Documents',
        icon: Icons.description_rounded,
        count: '24',
        status: 'All synced',
        lastUpdated: 'Updated today',
        color: AppColors.primaryGreen, // green
      ),
      LifeOverviewItem(
        label: 'Properties',
        icon: Icons.home_work_rounded,
        count: '3',
        status: 'Verified',
        lastUpdated: 'Updated 2d ago',
        color: AppColors.lightBlue, // blue
      ),
      LifeOverviewItem(
        label: 'Insurance',
        icon: Icons.shield_rounded,
        count: '5',
        status: '1 expiring',
        lastUpdated: 'Updated 1w ago',
        color: AppColors.secondaryGreen, // emerald
      ),
      LifeOverviewItem(
        label: 'Health',
        icon: Icons.favorite_rounded,
        count: '12',
        status: 'Up to date',
        lastUpdated: 'Updated 3d ago',
        color: Color(0xFF3B82F6), // blue
      ),
      LifeOverviewItem(
        label: 'Goals',
        icon: Icons.flag_rounded,
        count: '4',
        status: '2 on track',
        lastUpdated: 'Updated today',
        color: Color(0xFF14B8A6), // teal
      ),
      LifeOverviewItem(
        label: 'Net Worth',
        icon: Icons.account_balance_wallet_rounded,
        count: '₹1.24 Cr',
        status: '+4.2% MoM',
        lastUpdated: 'Updated today',
        color: AppColors.primaryGreen,
        // Premium green gradient tile.
        gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
      ),
      LifeOverviewItem(
        label: 'Investments',
        icon: Icons.trending_up_rounded,
        count: '₹48.6L',
        status: '+12.3%',
        lastUpdated: 'Updated today',
        color: AppColors.secondaryGreen,
      ),
      LifeOverviewItem(
        label: 'Passwords',
        icon: Icons.lock_rounded,
        count: '38',
        status: 'Vault locked',
        lastUpdated: 'Updated 5d ago',
        color: Color(0xFF3B82F6), // indigo-blue
      ),
    ],
    priorities: const [
      PriorityItem(
        title: 'Car insurance renewal',
        subtitle: 'HDFC Ergo · Policy #IN-44218',
        icon: Icons.directions_car_rounded,
        level: PriorityLevel.critical,
        due: 'Due in 3 days',
      ),
      PriorityItem(
        title: 'Property documentation pending',
        subtitle: 'Pune flat — sale deed upload',
        icon: Icons.home_work_rounded,
        level: PriorityLevel.important,
        due: 'Action needed',
      ),
      PriorityItem(
        title: "Aanya's birthday",
        subtitle: 'Plan a gift & reminder',
        icon: Icons.cake_rounded,
        level: PriorityLevel.info,
        due: 'in 5 days',
      ),
      PriorityItem(
        title: 'Annual health checkup',
        subtitle: 'Apollo · full body panel',
        icon: Icons.health_and_safety_rounded,
        level: PriorityLevel.important,
        due: 'Due this month',
      ),
    ],
    quickActions: const [
      QuickAction(
          label: 'Scan',
          icon: Icons.document_scanner_rounded,
          color: AppColors.primaryGreen),
      QuickAction(
          label: 'Add Doc',
          icon: Icons.note_add_rounded,
          color: AppColors.lightBlue),
      QuickAction(
          label: 'Property',
          icon: Icons.add_home_rounded,
          color: Color(0xFF8B6CEF)),
      QuickAction(
          label: 'Investment',
          icon: Icons.savings_rounded,
          color: Color(0xFF2BB6A3)),
      QuickAction(
          label: 'Insurance',
          icon: Icons.add_moderator_rounded,
          color: AppColors.warning),
      QuickAction(
          label: 'Health',
          icon: Icons.medical_services_rounded,
          color: Color(0xFFEC6A8C)),
      QuickAction(
          label: 'Vault',
          icon: Icons.lock_rounded,
          color: Color(0xFF4A6CF7)),
      QuickAction(
          label: 'Reminder',
          icon: Icons.alarm_add_rounded,
          color: Color(0xFFF5704A)),
      QuickAction(
          label: 'QR Share',
          icon: Icons.qr_code_2_rounded,
          color: AppColors.darkGreen),
      QuickAction(
          label: 'Goals',
          icon: Icons.flag_rounded,
          color: Color(0xFF8B6CEF)),
    ],
    fabActions: const [
      QuickAction(
          label: 'Add Document',
          icon: Icons.note_add_rounded,
          color: AppColors.lightBlue),
      QuickAction(
          label: 'Add Reminder',
          icon: Icons.alarm_add_rounded,
          color: Color(0xFFF5704A)),
      QuickAction(
          label: 'Add Investment',
          icon: Icons.savings_rounded,
          color: Color(0xFF2BB6A3)),
      QuickAction(
          label: 'Add Property',
          icon: Icons.add_home_rounded,
          color: Color(0xFF8B6CEF)),
      QuickAction(
          label: 'Add Insurance',
          icon: Icons.add_moderator_rounded,
          color: AppColors.warning),
      QuickAction(
          label: 'Add Health Record',
          icon: Icons.medical_services_rounded,
          color: Color(0xFFEC6A8C)),
    ],
    wallets: const [
      WalletSummary(
        name: 'Identity',
        icon: Icons.badge_rounded,
        itemCount: 6,
        lastActivity: 'PAN added · 2h ago',
        status: 'Secured',
        gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
      ),
      WalletSummary(
        name: 'Documents',
        icon: Icons.folder_shared_rounded,
        itemCount: 24,
        lastActivity: 'Lease · yesterday',
        status: 'Synced',
        gradient: [Color(0xFF4A6CF7), Color(0xFF7AA7FF)],
      ),
      WalletSummary(
        name: 'Insurance',
        icon: Icons.shield_rounded,
        itemCount: 5,
        lastActivity: 'Premium paid · 3d',
        status: '1 expiring',
        gradient: [Color(0xFFF5A524), Color(0xFFF5C24A)],
      ),
      WalletSummary(
        name: 'Health',
        icon: Icons.favorite_rounded,
        itemCount: 12,
        lastActivity: 'Lab report · 3d',
        status: 'Up to date',
        gradient: [Color(0xFFEC6A8C), Color(0xFFF59BB3)],
      ),
      WalletSummary(
        name: 'Property',
        icon: Icons.home_work_rounded,
        itemCount: 3,
        lastActivity: 'Tax paid · 1w',
        status: 'Verified',
        gradient: [Color(0xFF8B6CEF), Color(0xFFB59BF5)],
      ),
      WalletSummary(
        name: 'Investment',
        icon: Icons.trending_up_rounded,
        itemCount: 9,
        lastActivity: 'SIP · today',
        status: '+12.3%',
        gradient: [Color(0xFF34D399), Color(0xFF7DD3FC)],
      ),
      WalletSummary(
        name: 'Banking',
        icon: Icons.account_balance_rounded,
        itemCount: 4,
        lastActivity: 'Statement · 2d',
        status: 'Synced',
        gradient: [Color(0xFF00875A), Color(0xFF00A86B)],
      ),
      WalletSummary(
        name: 'Passwords',
        icon: Icons.lock_rounded,
        itemCount: 38,
        lastActivity: 'Locked · 5d',
        status: 'Encrypted',
        gradient: [Color(0xFF3A4A6B), Color(0xFF5B6B8C)],
      ),
    ],
    investment: const InvestmentSummary(
      invested: 4330000,
      currentValue: 4860000,
      growth: [38, 39, 40.5, 41, 43, 44.2, 46, 47.1, 48.6],
      allocations: [
        AssetAllocation(
            label: 'Mutual Funds', value: 1850000, color: Color(0xFF1B9C85)),
        AssetAllocation(label: 'Stocks', value: 1120000, color: Color(0xFF4FC3F7)),
        AssetAllocation(label: 'Gold', value: 760000, color: Color(0xFFE0A100)),
        AssetAllocation(label: 'Land', value: 820000, color: Color(0xFF8B6CEF)),
        AssetAllocation(label: 'Savings', value: 310000, color: Color(0xFF2BB6A3)),
      ],
    ),
    property: const PropertySummary(
      totalProperties: 3,
      portfolioValue: 18500000,
      ownership: '2 owned · 1 jointly held',
      recentUpdate: 'Property tax paid · Pune flat',
    ),
    health: const HealthSummary(
      bloodGroup: 'O+',
      recordsCount: 12,
      nextCheckup: '18 Jul · Apollo',
      emergencyContacts: 3,
    ),
    insurance: const InsuranceSummary(
      activePolicies: 5,
      expiringSoon: 1,
      nextPremium: '₹12,400 · 8 Jul',
      totalCover: '₹1.2 Cr',
    ),
    familyEvents: const [
      FamilyEvent(
          name: "Aanya's Birthday",
          type: FamilyEventType.birthday,
          date: '5 Jul',
          relativeDay: 'in 5 days'),
      FamilyEvent(
          name: 'Wedding Anniversary',
          type: FamilyEventType.anniversary,
          date: '14 Jul',
          relativeDay: 'in 2 weeks'),
      FamilyEvent(
          name: "Dad's Birthday",
          type: FamilyEventType.birthday,
          date: '22 Jul',
          relativeDay: 'in 3 weeks'),
      FamilyEvent(
          name: 'Family Reunion',
          type: FamilyEventType.event,
          date: '2 Aug',
          relativeDay: 'next month'),
    ],
    activity: const [
      ActivityItem(
          title: 'PAN card uploaded',
          icon: Icons.badge_rounded,
          time: '2h ago',
          color: AppColors.primaryGreen),
      ActivityItem(
          title: 'Term insurance added',
          icon: Icons.shield_rounded,
          time: '5h ago',
          color: AppColors.warning),
      ActivityItem(
          title: 'Health record updated',
          icon: Icons.favorite_rounded,
          time: 'Yesterday',
          color: Color(0xFFEC6A8C)),
      ActivityItem(
          title: 'Pune flat added',
          icon: Icons.home_work_rounded,
          time: '2 days ago',
          color: Color(0xFF8B6CEF)),
      ActivityItem(
          title: 'Retirement goal updated',
          icon: Icons.flag_rounded,
          time: '3 days ago',
          color: Color(0xFF2BB6A3)),
    ],
    insights: const [
      SmartInsight(
          message: 'Gold is up 0.8% today — your holdings gained ₹6,080.',
          icon: Icons.trending_up_rounded,
          accent: AppColors.gold),
      SmartInsight(
          message: 'Car insurance expires in 3 days. Renew to stay covered.',
          icon: Icons.warning_amber_rounded,
          accent: AppColors.critical),
      SmartInsight(
          message: '3 documents need attention before they expire.',
          icon: Icons.description_rounded,
          accent: AppColors.lightBlue),
      SmartInsight(
          message: 'Your property portfolio value rose 2.1% this quarter.',
          icon: Icons.home_work_rounded,
          accent: AppColors.primaryGreen),
    ],
  );
}
