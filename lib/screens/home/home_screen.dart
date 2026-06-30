import 'package:flutter/material.dart';

import '../../data/dashboard_repository.dart';
import '../../models/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/sections/activity_section.dart';
import '../../widgets/dashboard/sections/family_section.dart';
import '../../widgets/dashboard/sections/insights_section.dart';
import '../../widgets/dashboard/sections/investment_section.dart';
import '../../widgets/dashboard/sections/life_overview_section.dart';
import '../../widgets/dashboard/sections/market_section.dart';
import '../../widgets/dashboard/sections/priority_section.dart';
import '../../widgets/dashboard/sections/quick_actions_section.dart';
import '../../widgets/dashboard/sections/snapshot_sections.dart';
import '../../widgets/dashboard/sections/wallet_section.dart';
import '../../widgets/dashboard/welcome_header.dart';

/// The INO Home Dashboard — the app's "Digital Life Command Center".
///
/// Composes all the dashboard sections in a single scroll, ordered by the
/// information hierarchy in the product brief: what needs attention → market
/// pulse → life overview → quick actions → wallets → the per-domain snapshots →
/// family → activity → insights. Data comes from [DashboardRepository] (sample
/// today, live later) and each section staggers in for a premium settle-in.
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
    setState(() {
      _future = data;
    });
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
                  // Pinned-feel header (scrolls normally but always first).
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: WelcomeHeader(
                        fullName: widget.profile.fullName,
                        themeMode: widget.themeMode,
                        notificationCount: data?.priorities.length ?? 0,
                        onToggleTheme:
                            widget.onToggleTheme ?? () {},
                        onSearch: () => _toast('Global search — coming soon'),
                        onNotifications: () =>
                            _toast('Notification center — coming soon'),
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          _sections(data),
                        ),
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

  /// Builds the ordered section list, each wrapped in a staggered entrance.
  List<Widget> _sections(DashboardData data) {
    final sections = <Widget>[
      MarketSection(quotes: data.market),
      LifeOverviewSection(items: data.lifeOverview),
      PrioritySection(items: data.priorities),
      QuickActionsSection(
        actions: data.quickActions,
        onAction: (a) => _toast('${a.label} — coming soon'),
      ),
      WalletSection(wallets: data.wallets),
      InvestmentSection(summary: data.investment),
      PropertySection(summary: data.property),
      HealthSection(summary: data.health),
      InsuranceSection(summary: data.insurance),
      FamilySection(events: data.familyEvents),
      ActivitySection(items: data.activity),
      InsightsSection(insights: data.insights),
    ];

    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: FadeSlideIn(
            // Cap the cascade so later sections don't feel sluggish.
            delay: Duration(milliseconds: (i * 70).clamp(0, 560)),
            child: sections[i],
          ),
        ),
    ];
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
