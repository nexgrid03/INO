import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../models/user_profile.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/sections/insights_section.dart';
import '../../widgets/dashboard/sections/quick_actions_section.dart';
import '../../widgets/wallet/recent_items.dart';
import '../../widgets/wallet/security_center.dart';
import '../../widgets/wallet/wallet_grid.dart';
import '../../widgets/wallet/wallet_header.dart';
import '../../widgets/wallet/wallet_overview_card.dart';
import 'wallet_detail_screen.dart';

/// The INO Wallet Hub — the secure command center for a user's digital life.
///
/// Composes, in the brief's order: header → vault overview hero → wallet
/// categories grid → quick actions → recently accessed → security center →
/// smart insights. Data comes from [WalletRepository] (sample today, live
/// later); each section staggers in for a premium settle-in.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<WalletHubData> _future;

  @override
  void initState() {
    super.initState();
    _future = WalletRepository.instance.load();
  }

  Future<void> _refresh() async {
    final data = WalletRepository.instance.load();
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

  /// Opens the reusable Wallet Detail screen with a premium slide + fade.
  void _openWallet(WalletCategory category) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => WalletDetailScreen(category: category),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
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
          child: FutureBuilder<WalletHubData>(
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: WalletHeader(
                        fullName: widget.profile.fullName,
                        itemsSecured: data?.overview.protectedItems ?? 0,
                        notificationCount: data?.insights.length ?? 0,
                        onSearch: () => _toast('Search wallets — coming soon'),
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
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

  List<Widget> _sections(WalletHubData data) {
    final sections = <Widget>[
      WalletOverviewCard(overview: data.overview),
      WalletGrid(
        categories: data.categories,
        onOpen: _openWallet,
      ),
      QuickActionsSection(
        actions: data.quickActions,
        onAction: (a) => _toast('${a.label} — coming soon'),
      ),
      RecentItemsSection(
        items: data.recents,
        onOpen: (i) => _toast('Opening ${i.name} — coming soon'),
      ),
      SecurityCenter(status: data.security),
      InsightsSection(insights: data.insights),
    ];

    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: FadeSlideIn(
            delay: Duration(milliseconds: (i * 80).clamp(0, 480)),
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
