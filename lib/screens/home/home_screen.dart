import 'package:flutter/material.dart';

import '../../data/dashboard_repository.dart';
import '../../models/user_profile.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/welcome_header.dart';
import '../../widgets/home/activity_tile.dart';
import '../../widgets/home/dashboard_card.dart';
import '../../widgets/home/floating_menu.dart';
import '../../widgets/home/market_card.dart';
import '../../widgets/home/priority_card.dart';
import '../../widgets/home/quick_action_button.dart';
import '../documents/add_document_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../shell/shell_controller.dart';

/// The INO Home — a minimal, premium fintech launcher.
///
/// Six focused sections, one job each, nothing duplicated: header → net-worth
/// hero → top-3 priorities → compact market snapshot → 5 quick actions →
/// recent activity. Every module's own numbers (insurance, health, property,
/// goals, investments) live on their dedicated pages, not here.
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
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = DashboardRepository.instance.load();
  }

  Future<void> _refresh() async {
    final data = DashboardRepository.instance.load();
    setState(() => _future = data);
    await data;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  void _goToTab(int index) => ShellController.tab.value = index;

  void _addDocument() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddDocumentScreen()),
    );
  }

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
          child: FutureBuilder<DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                          AppSpacing.sm, AppSpacing.screen, AppSpacing.xs),
                      child: WelcomeHeader(
                        fullName: widget.profile.fullName,
                        themeMode: widget.themeMode,
                        notificationCount: data?.priorities.length ?? 0,
                        onToggleTheme: widget.onToggleTheme ?? () {},
                        onSearch: () => _toast('Global search — coming soon'),
                        onNotifications: () =>
                            _toast('Notifications — coming soon'),
                      ),
                    ),
                  ),
                  if (data == null)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _LoadingState(),
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

  List<Widget> _sections(DashboardData data) {
    final recent = data.activity.take(5).toList();
    final sections = <Widget>[
      // 2. Net-worth hero.
      DashboardCard(
        hero: data.hero,
        onCta: () => _toast('Portfolio — coming soon'),
      ),
      // 3. Priority Center — top 3 only, horizontal cards.
      _Section(
        header: SectionHeader(
          title: 'Priority Center',
          subtitle: 'Items that need your attention',
          icon: Icons.error_rounded,
          iconColor: AppColors.critical,
          actionLabel: 'View all',
          onAction: () => _toast('All priorities — coming soon'),
        ),
        child: SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: data.priorities.take(3).length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final p = data.priorities[i];
              return SizedBox(
                width: 190,
                child: PriorityCard(
                  item: p,
                  onTap: () => _toast('${p.title} — coming soon'),
                ),
              );
            },
          ),
        ),
      ),
      // 4. Market Snapshot — compact.
      _Section(
        header: SectionHeader(
          title: 'Market Snapshot',
          subtitle: 'Live rates near you',
          icon: Icons.trending_up_rounded,
          actionLabel: 'View markets',
          onAction: () => _toast('Markets — coming soon'),
        ),
        child: MarketCard(
          quotes: data.market,
          onTap: () => _toast('Markets — coming soon'),
        ),
      ),
      // 5. Quick Actions.
      _Section(
        header: const SectionHeader(
          title: 'Quick Actions',
          subtitle: 'Do more in one tap',
          icon: Icons.bolt_rounded,
          iconColor: AppColors.lightBlue,
        ),
        child: _QuickActions(
          onScan: _scan,
          onAddDocument: _addDocument,
          onWallet: () => _goToTab(1),
          onReminder: () => _goToTab(3),
          onMore: () => FloatingMenu.show(
            context,
            title: 'Quick Add',
            actions: data.fabActions,
            onSelect: (a) {
              switch (a.label) {
                case 'Add Document':
                  _addDocument();
                case 'Scan':
                case 'Scan Document':
                  _scan();
                default:
                  _toast('${a.label} — coming soon');
              }
            },
          ),
        ),
      ),
      // 6. Recent Activity — latest 5.
      _Section(
        header: SectionHeader(
          title: 'Recent Activity',
          subtitle: 'Your latest updates',
          icon: Icons.access_time_rounded,
          actionLabel: 'View all',
          onAction: () => _toast('Activity history — coming soon'),
        ),
        child: InoCard(
          radius: AppRadius.card,
          padding: const EdgeInsets.all(AppSpacing.internal),
          child: Column(
            children: [
              for (var i = 0; i < recent.length; i++)
                ActivityTile(
                  item: recent[i],
                  isLast: i == recent.length - 1,
                ),
            ],
          ),
        ),
      ),
    ];

    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: EdgeInsets.only(
              bottom: i == sections.length - 1 ? 0 : AppSpacing.section),
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
    required this.onScan,
    required this.onAddDocument,
    required this.onWallet,
    required this.onReminder,
    required this.onMore,
  });

  final VoidCallback onScan;
  final VoidCallback onAddDocument;
  final VoidCallback onWallet;
  final VoidCallback onReminder;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    // Each action shares the row equally so labels never overflow on small
    // phones; the 52px icon target stays fixed and centred.
    final actions = <Widget>[
      QuickActionButton(
          icon: AppIcons.scan,
          label: 'Scan',
          color: AppColors.primaryGreen,
          onTap: onScan),
      QuickActionButton(
          icon: AppIcons.addDocument,
          label: 'Document',
          color: AppColors.lightBlue,
          onTap: onAddDocument),
      QuickActionButton(
          icon: AppIcons.wallet,
          label: 'Wallet',
          color: AppColors.secondaryGreen,
          onTap: onWallet),
      QuickActionButton(
          icon: AppIcons.reminder,
          label: 'Reminder',
          color: const Color(0xFFF5704A),
          onTap: onReminder),
      QuickActionButton(
          icon: AppIcons.more,
          label: 'More',
          color: AppColors.darkGreen,
          onTap: onMore),
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(top: 80),
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: AppColors.primaryGreen,
          ),
        ),
      ),
    );
  }
}
