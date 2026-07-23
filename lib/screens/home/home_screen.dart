import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../data/dashboard_repository.dart';
import '../../data/reminder_store.dart';
import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../models/user_profile.dart';
import '../../repositories/document_repository.dart';
import '../../services/activity_service.dart';
import '../../services/document_protection_store.dart';
import '../../services/market_rates_service.dart';
import '../../services/net_worth_service.dart';
import '../../services/notification_center.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/welcome_header.dart';
import '../../widgets/home/activity_tile.dart';
import '../../widgets/home/dashboard_card.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/home/market_card.dart';
import '../../widgets/home/quick_action_button.dart';
import '../../widgets/home/skeletons.dart';
import '../expenses/tax_records_screen.dart';
import '../home/activity_history_screen.dart';
import '../home/pending_actions_screen.dart';
import '../markets/markets_screen.dart';
import '../notes/notes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/cloud_backup_screen.dart';
import '../property/area_converter_screen.dart';
import '../property_finance/emi_calculator_screen.dart';
import '../property_finance/property_finance_tools_screen.dart';
import '../property_finance/property_valuation_screen.dart';
import '../property_finance/sip_calculator_screen.dart';
import '../reminders/reminders_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../search/global_search_screen.dart';
import '../shell/shell_controller.dart';
import '../wallet/wallet_detail_screen.dart';

/// The read model the Home screen renders: a real-data hero + activity feed, and
/// the market snapshot (realistic fallback) — assembled in one load.
class _HomeData {
  const _HomeData({
    required this.hero,
    required this.market,
    required this.activity,
  });

  final HomeHero hero;
  final List<MarketQuote> market;
  final List<ActivityItem> activity;
}

/// The INO Home — Premium Responsive Fintech & Digital Life Management Dashboard.
///
/// Responsive Features:
/// - Screen margins scale dynamically via `context.responsivePadding` across devices.
/// - Grid columns auto-adjust (Small phones: 4 quick actions, 2 tools; Tablets: 6 columns).
/// - FAB & Mic button position dynamically accounting for bottom safe areas.
/// - Cards and typography auto-resize without layout overflows.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.profile,
    this.themeMode = ThemeMode.system,
    this.onToggleTheme,
  });

  final UserProfile profile;
  final ThemeMode themeMode;
  final VoidCallback? onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    NotificationCenter.instance.load();
  }

  Future<_HomeData> _load() async {
    final dashboard = await DashboardRepository.instance.load();
    final market = await MarketRatesService.instance.fetchLive(dashboard.market);
    final activity = await ActivityService.instance.load(limit: 6);

    var documentCount = 0;
    var expiringDocuments = 0;
    try {
      final docs = await DocumentRepository.instance.listAll();
      documentCount = docs.length;
      final now = DateTime.now();
      expiringDocuments = docs.where((d) {
        final e = d.expiresAt;
        if (e == null) return false;
        final days = e.difference(now).inDays;
        return days >= 0 && days <= 30;
      }).length;
    } catch (_) {}

    var pending = expiringDocuments;
    try {
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      pending +=
          ReminderStore.instance.active.where((r) => r.daysFrom(today) <= 7).length;
    } catch (_) {}

    final hero = NetWorthService.instance.heroFrom(
      assets: documentCount,
      documents: documentCount,
      pendingTasks: pending,
      protectedItems: DocumentProtectionStore.instance.protectedCount,
    );

    return _HomeData(
      hero: hero,
      market: market,
      activity: activity,
    );
  }

  Future<void> _refresh() async {
    final data = _load();
    setState(() => _future = data);
    await NotificationCenter.instance.refresh();
    await data;
  }

  // ---- Navigation ----------------------------------------------------------

  void _goToTab(int index) => ShellController.tab.value = index;

  Future<T?> _push<T>(Widget screen) => Navigator.of(context)
      .push<T>(MaterialPageRoute(builder: (_) => screen));

  void _scan() => launchScanFlow(context);

  void _openWallet(String name) {
    final category = SupabaseWalletRepository.categoryFor(name);
    if (category != null) _push(WalletDetailScreen(category: category));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final sidePadding = context.responsivePadding;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _refresh,
              child: FutureBuilder<_HomeData>(
                future: _future,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  final hasError =
                      snapshot.connectionState == ConnectionState.done &&
                          snapshot.hasError;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      // 1. Greeting Header Card
                      SliverToBoxAdapter(child: _header(palette, data?.hero)),
                      if (hasError)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ErrorRetry(onRetry: _refresh),
                        )
                      else if (data == null)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              sidePadding, AppSpacing.sm, sidePadding, 48.rh),
                          sliver: const SliverToBoxAdapter(
                              child: DashboardSkeleton()),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              sidePadding, AppSpacing.sm, sidePadding, 48.rh),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(_sections(data)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1. Greeting Header Card
  Widget _header(AppPalette palette, HomeHero? hero) {
    final sidePadding = context.responsivePadding;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadius.card)),
        boxShadow: palette.cardShadow,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            sidePadding, AppSpacing.sm, sidePadding, AppSpacing.md),
        child: ListenableBuilder(
          listenable: NotificationCenter.instance,
          builder: (context, _) => WelcomeHeader(
            fullName: widget.profile.fullName,
            photoUrl: widget.profile.profilePhoto,
            notificationCount: NotificationCenter.instance.unreadCount,
            onProfile: () => _goToTab(4),
            onSearch: () => _push(const GlobalSearchScreen()),
            onNotifications: () => _push(const NotificationsScreen()),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(_HomeData data) {
    final l10n = AppLocalizations.of(context);
    final sections = <Widget>[
      // 2. Large Floating Search Bar
      _SearchBar(
        onTap: () => _push(const GlobalSearchScreen()),
        onFilter: () => _push(const GlobalSearchScreen()),
      ),

      SizedBox(height: 14.rh),

      // 3. Today's Overview (Main Hero Section)
      DashboardCard(
        hero: data.hero,
        onDocumentsExpiring: () => _push(const PendingActionsScreen()),
        onEmiDues: () => _push(const EmiCalculatorScreen()),
        onRemindersToday: () => _push(RemindersScreen(profile: widget.profile)),
        onInsuranceRenewals: () => _openWallet('Insurance Wallet'),
        onBackup: () => _push(CloudBackupScreen(profile: widget.profile)),
      ),

      SizedBox(height: 16.rh),

      // 4. Quick Actions (Responsive column grid)
      _Section(
        header: SectionHeader(
          title: l10n.t('quickActions'),
          subtitle: 'Access your vaults instantly',
          icon: Icons.bolt_rounded,
          iconColor: AppColors.lightBlue,
          actionLabel: l10n.t('viewAll'),
          onAction: () => _goToTab(1),
        ),
        child: _FiveQuickActions(
          onDocuments: () => _openWallet('Document Wallet'),
          onNotes: () => _push(const NotesScreen()),
          onCards: () => _openWallet('Banking Wallet'),
          onScanner: _scan,
          onInsurance: () => _openWallet('Insurance Wallet'),
        ),
      ),

      SizedBox(height: 16.rh),

      // 5. Property & Finance Tools (Adaptive grid columns)
      _Section(
        header: SectionHeader(
          title: l10n.t('propertyFinanceTools'),
          subtitle: 'Calculators & land converters',
          icon: Icons.calculate_rounded,
          iconColor: AppColors.primaryGreen,
          actionLabel: l10n.t('viewAll'),
          onAction: () => _push(const PropertyFinanceToolsScreen()),
        ),
        child: _SixFinanceTools(
          onOpenArea: () => _push(const AreaConverterScreen()),
          onOpenEmi: () => _push(const EmiCalculatorScreen()),
          onOpenSip: () => _push(const SipCalculatorScreen()),
          onOpenStampDuty: () => _push(const PropertyValuationScreen()),
          onOpenUnitConv: () => _push(const AreaConverterScreen()),
          onOpenTax: () => _push(const TaxRecordsScreen()),
        ),
      ),

      SizedBox(height: 16.rh),

      // 6. Live Market Prices (Gold & Silver ONLY)
      _Section(
        header: SectionHeader(
          title: l10n.t('marketSnapshot'),
          subtitle: 'Live precious metal rates',
          icon: Icons.trending_up_rounded,
          actionLabel: l10n.t('viewMarkets'),
          onAction: () => _push(MarketsScreen(quotes: data.market)),
        ),
        child: MarketCard(
          quotes: data.market,
          onTap: () => _push(MarketsScreen(quotes: data.market)),
        ),
      ),

      SizedBox(height: 16.rh),

      // 7. Recent Activity (Show ONLY 3 activities)
      _Section(
        header: SectionHeader(
          title: l10n.t('recentActivity'),
          subtitle: l10n.t('recentActivitySubtitle'),
          icon: Icons.access_time_rounded,
          actionLabel: l10n.t('viewAll'),
          onAction: () => _push(const ActivityHistoryScreen()),
        ),
        child: _ActivityListThree(items: data.activity, onAdd: _scan),
      ),
    ];

    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: FadeSlideIn(
            delay: Duration(milliseconds: (i * 60).clamp(0, 360)),
            child: sections[i],
          ),
        ),
    ];
  }
}

/// 2. Large Floating Search Bar Widget (Height 56px, Radius 18px)
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap, required this.onFilter});

  final VoidCallback onTap;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56.rh,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: AppColors.primaryGreen,
              size: 22,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Search documents, cards, notes...',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: onFilter,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section container wrapper
class _Section extends StatelessWidget {
  const _Section({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, child],
    );
  }
}

/// 4. Quick Actions (Responsive Grid Column Layout)
class _FiveQuickActions extends StatelessWidget {
  const _FiveQuickActions({
    required this.onDocuments,
    required this.onNotes,
    required this.onCards,
    required this.onScanner,
    required this.onInsurance,
  });

  final VoidCallback onDocuments;
  final VoidCallback onNotes;
  final VoidCallback onCards;
  final VoidCallback onScanner;
  final VoidCallback onInsurance;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      QuickActionButton(
        icon: Icons.folder_shared_rounded,
        label: 'Documents',
        color: AppColors.primaryGreen,
        onTap: onDocuments,
      ),
      QuickActionButton(
        icon: Icons.edit_note_rounded,
        label: 'Notes',
        color: AppColors.lightBlue,
        onTap: onNotes,
      ),
      QuickActionButton(
        icon: Icons.credit_card_rounded,
        label: 'Cards',
        color: const Color(0xFF8B6CEF),
        onTap: onCards,
      ),
      QuickActionButton(
        icon: Icons.document_scanner_rounded,
        label: 'Scanner',
        color: const Color(0xFF2DD4BF),
        onTap: onScanner,
      ),
      QuickActionButton(
        icon: Icons.shield_rounded,
        label: 'Insurance',
        color: AppColors.warning,
        onTap: onInsurance,
      ),
    ];

    final isSmall = context.isMobileSmall;
    if (isSmall) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SizedBox(
                width: (context.screenWidth - 50) / 4,
                child: actions[i],
              ),
            ],
          ],
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}

/// 5. Property & Finance Tools (Adaptive Grid Columns & Aspect Ratios)
class _SixFinanceTools extends StatelessWidget {
  const _SixFinanceTools({
    required this.onOpenArea,
    required this.onOpenEmi,
    required this.onOpenSip,
    required this.onOpenStampDuty,
    required this.onOpenUnitConv,
    required this.onOpenTax,
  });

  final VoidCallback onOpenArea;
  final VoidCallback onOpenEmi;
  final VoidCallback onOpenSip;
  final VoidCallback onOpenStampDuty;
  final VoidCallback onOpenUnitConv;
  final VoidCallback onOpenTax;

  @override
  Widget build(BuildContext context) {
    final tools = [
      _ToolTile(
        title: 'Area Calc',
        icon: Icons.straighten_rounded,
        color: const Color(0xFF0CB7A3),
        bgColor: const Color(0xFFEAFBF7),
        onTap: onOpenArea,
      ),
      _ToolTile(
        title: 'EMI Calc',
        icon: Icons.account_balance_rounded,
        color: const Color(0xFF3EC7FF),
        bgColor: const Color(0xFFEDF8FF),
        onTap: onOpenEmi,
      ),
      _ToolTile(
        title: 'SIP Calc',
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF8B6CEF),
        bgColor: const Color(0xFFF3EFFF),
        onTap: onOpenSip,
      ),
      _ToolTile(
        title: 'Stamp Duty',
        icon: Icons.gavel_rounded,
        color: const Color(0xFFF59E0B),
        bgColor: const Color(0xFFFFF7ED),
        onTap: onOpenStampDuty,
      ),
      _ToolTile(
        title: 'Unit Conv.',
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF7DD9FF),
        bgColor: const Color(0xFFF0F9FF),
        onTap: onOpenUnitConv,
      ),
      _ToolTile(
        title: 'Tax Calc',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF2DD4BF),
        bgColor: const Color(0xFFF0FDF4),
        onTap: onOpenTax,
      ),
    ];

    final columns = context.toolsColumns;
    final aspectRatio = context.toolsAspectRatio;

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: aspectRatio,
      children: tools,
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 7. Recent Activity List (Show ONLY 3 activities)
class _ActivityListThree extends StatelessWidget {
  const _ActivityListThree({required this.items, required this.onAdd});

  final List<ActivityItem> items;
  final VoidCallback onAdd;

  static final List<ActivityItem> _fallbackThree = [
    ActivityItem(
      title: 'Aadhaar Card Uploaded',
      time: 'Today, 10:30 AM',
      icon: Icons.badge_rounded,
      color: AppColors.primaryGreen,
      kind: ActivityKind.document,
    ),
    ActivityItem(
      title: 'PAN OCR Completed',
      time: 'Today, 09:15 AM',
      icon: Icons.document_scanner_rounded,
      color: AppColors.lightBlue,
      kind: ActivityKind.document,
    ),
    ActivityItem(
      title: 'Property Document Uploaded',
      time: 'Yesterday, 08:45 PM',
      icon: Icons.home_work_rounded,
      color: const Color(0xFF8B6CEF),
      kind: ActivityKind.document,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final list = items.isNotEmpty ? items.take(3).toList() : _fallbackThree;

    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          ActivityTile(
            item: list[i],
            isLast: i == list.length - 1,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ActivityHistoryScreen(),
                ),
              );
            },
          ),
      ],
    );
  }
}
