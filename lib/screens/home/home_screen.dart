import 'package:flutter/material.dart';

import '../../data/dashboard_repository.dart';
import '../../data/reminder_store.dart';
import '../../models/dashboard_models.dart';
import '../../models/user_profile.dart';
import '../../repositories/document_repository.dart';
import '../../services/activity_service.dart';
import '../../services/document_protection_store.dart';
import '../../services/net_worth_service.dart';
import '../../services/notification_center.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/welcome_header.dart';
import '../../widgets/home/activity_tile.dart';
import '../../widgets/home/dashboard_card.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/home/market_card.dart';
import '../../widgets/home/quick_action_button.dart';
import '../../widgets/home/skeletons.dart';
import '../assets/assets_screen.dart';
import '../documents/add_document_screen.dart';
import '../home/activity_history_screen.dart';
import '../home/ai_insights_screen.dart';
import '../home/pending_actions_screen.dart';
import '../home/protection_center_screen.dart';
import '../markets/markets_screen.dart';
import '../networth/net_worth_analytics_screen.dart';
import '../notifications/notifications_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../search/global_search_screen.dart';
import '../shell/shell_controller.dart';

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

/// The INO Home — a premium fintech dashboard.
///
/// Header (search · notifications · profile) → net-worth hero (tappable stats +
/// analytics) → quick actions → market snapshot → recent activity. The hero
/// counts, activity feed and notification badge are driven by the user's real
/// data; wealth figures are realistic fallbacks until live feeds are connected.
/// Every control routes to a real page.
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
    // Refresh the notification feed so the bell badge is accurate.
    NotificationCenter.instance.load();
  }

  Future<_HomeData> _load() async {
    // Market + FAB actions come from the (sample) dashboard repository.
    final dashboard = await DashboardRepository.instance.load();

    // Real activity feed.
    final activity = await ActivityService.instance.load(limit: 6);

    // Real hero counts.
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
    } catch (_) {
      // Offline / signed out — hero still shows the fallback net worth.
    }

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
      market: dashboard.market,
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
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
                  SliverToBoxAdapter(child: _header(palette, data?.hero)),
                  if (hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorRetry(onRetry: _refresh),
                    )
                  else if (data == null)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.screen,
                          AppSpacing.md, AppSpacing.screen, 120),
                      sliver: SliverToBoxAdapter(child: DashboardSkeleton()),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                          AppSpacing.md, AppSpacing.screen, 120),
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
    );
  }

  Widget _header(AppPalette palette, HomeHero? hero) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadius.large)),
        border: Border(bottom: BorderSide(color: palette.border)),
        boxShadow: palette.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
            AppSpacing.screen, AppSpacing.md),
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
    final sections = <Widget>[
      // Net-worth hero with tappable stats.
      DashboardCard(
        hero: data.hero,
        onCta: () => _push(const NetWorthAnalyticsScreen()),
        onAssets: () => _push(const AssetsScreen()),
        onPending: () => _push(const PendingActionsScreen()),
        onProtected: () => _push(const ProtectionCenterScreen()),
      ),
      // Quick actions.
      _Section(
        header: const SectionHeader(
          title: 'Quick Actions',
          subtitle: 'Do more in one tap',
          icon: Icons.bolt_rounded,
          iconColor: AppColors.lightBlue,
        ),
        child: _QuickActions(
          onAddAsset: () => _push(const AddDocumentScreen()),
          onScan: _scan,
          onInsights: () => _push(const AiInsightsScreen()),
          onProtect: () => _push(const ProtectionCenterScreen()),
        ),
      ),
      // Market snapshot.
      _Section(
        header: SectionHeader(
          title: 'Market Snapshot',
          subtitle: 'Live rates near you',
          icon: Icons.trending_up_rounded,
          actionLabel: 'View markets',
          onAction: () => _push(MarketsScreen(quotes: data.market)),
        ),
        child: MarketCard(
          quotes: data.market,
          onTap: () => _push(MarketsScreen(quotes: data.market)),
        ),
      ),
      // Recent activity (real).
      _Section(
        header: SectionHeader(
          title: 'Recent Activity',
          subtitle: 'Your latest updates',
          icon: Icons.access_time_rounded,
          actionLabel: 'View all',
          onAction: () => _push(const ActivityHistoryScreen()),
        ),
        child: _ActivityList(items: data.activity, onAdd: _scan),
      ),
    ];

    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: EdgeInsets.only(
              bottom: i == sections.length - 1 ? 0 : AppSpacing.sm),
          child: FadeSlideIn(
            delay: Duration(milliseconds: (i * 70).clamp(0, 420)),
            child: sections[i],
          ),
        ),
    ];
  }
}

/// A section header + body with the standard gap between them.
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddAsset,
    required this.onScan,
    required this.onInsights,
    required this.onProtect,
  });

  final VoidCallback onAddAsset;
  final VoidCallback onScan;
  final VoidCallback onInsights;
  final VoidCallback onProtect;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      QuickActionButton(
          icon: Icons.add_chart_rounded,
          label: 'Add Asset',
          color: AppColors.primaryGreen,
          onTap: onAddAsset),
      QuickActionButton(
          icon: Icons.document_scanner_rounded,
          label: 'Scan & Upload',
          color: AppColors.lightBlue,
          onTap: onScan),
      QuickActionButton(
          icon: Icons.auto_awesome_rounded,
          label: 'AI Insights',
          color: const Color(0xFF8B6CEF),
          onTap: onInsights),
      QuickActionButton(
          icon: Icons.verified_user_rounded,
          label: 'Protect',
          color: const Color(0xFF2BB6A3),
          onTap: onProtect),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}

/// The recent-activity list, with a proper empty state when there's nothing yet.
class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.items, required this.onAdd});

  final List<ActivityItem> items;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return InoCard(
        radius: AppRadius.card,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.timeline_rounded,
          title: 'No activity yet',
          message: 'Scan or add your first document to see your activity here.',
          actionLabel: 'Scan a document',
          onAction: onAdd,
          compact: true,
        ),
      );
    }
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            ActivityTile(item: items[i], isLast: i == items.length - 1),
        ],
      ),
    );
  }
}
