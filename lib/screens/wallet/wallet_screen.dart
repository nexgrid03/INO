import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/wallet_grid.dart';
import '../notifications/notifications_screen.dart';
import 'document_search_delegate.dart';
import 'wallet_detail_screen.dart';

/// The INO Wallet Hub — a premium, fast-access vault launcher.
///
/// Deliberately minimal, arranged in the "document wallet hub" rhythm:
/// a compact identity header (avatar · "My Wallets" · notifications), a hero
/// floating search bar, a single lightweight summary card ("8 Wallets • 128
/// Records") and the compact grid of all wallets, so every vault is visible
/// without scrolling — the Apple/Google Wallet model where access speed beats
/// analytics. Tapping a wallet opens its detail screen. (Overview analytics,
/// quick actions, recents, security and insights live on the detail/other
/// screens.)
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

  /// Opens a real global search across every document in the vault.
  void _searchDocuments() {
    showSearch<void>(context: context, delegate: DocumentSearchDelegate());
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
    final l10n = AppLocalizations.of(context);
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
                  // Header — avatar · "My Wallets" · notification bell.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: FadeSlideIn(
                        offset: 14,
                        child: _HubHeader(
                          fullName: widget.profile.fullName,
                          notificationCount: data?.insights.length ?? 0,
                          onNotifications: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Hero search — the hub's primary affordance.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 60),
                        offset: 14,
                        child: FloatingSearchBar(
                          hint: l10n.t('searchWallets'),
                          onTap: _searchDocuments,
                          trailing: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: AppGradients.primary,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: AppShadows.glow(
                                AppColors.primaryGreen,
                                opacity: 0.28,
                              ),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Lightweight summary — a floating stat card with the brand
                  // accent edge ("8 Wallets • 128 Records").
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 120),
                        offset: 14,
                        child: _WalletSummaryCard(
                          walletCount: data?.categories.length ?? 0,
                          recordCount: data?.overview.totalRecords ?? 0,
                        ),
                      ),
                    ),
                  ),
                  if (data == null)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _LoadingState(),
                    )
                  else
                    // Compact launcher grid — all wallets, no scrolling.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverToBoxAdapter(
                        child: WalletGrid(
                          categories: data.categories,
                          onOpen: _openWallet,
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
}

/// Header row in the hub style: gradient avatar, the "My Wallets" headline and
/// a circular notification button with an unread dot.
class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.fullName,
    required this.notificationCount,
    required this.onNotifications,
  });

  final String fullName;
  final int notificationCount;
  final VoidCallback onNotifications;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppGradients.primary,
            boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.26),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            l10n.t('myWallets'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _BellButton(
          badge: notificationCount,
          tooltip: l10n.t('notifications'),
          onTap: onNotifications,
        ),
      ],
    );
  }
}

/// Circular notification control (hub header style) with an unread dot.
class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.onTap,
    required this.tooltip,
    this.badge = 0,
  });

  final VoidCallback onTap;
  final String tooltip;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: palette.surface,
          shape: CircleBorder(side: BorderSide(color: palette.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 21,
                    color: palette.textPrimary,
                  ),
                  if (badge > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.critical,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: palette.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lightweight vault summary as a floating stat card: a gradient accent
/// edge, a gradient icon container and the "N Wallets • N Records" line.
class _WalletSummaryCard extends StatelessWidget {
  const _WalletSummaryCard({
    required this.walletCount,
    required this.recordCount,
  });

  final int walletCount;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return InoCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
      child: Row(
        children: [
          // Brand accent edge (the stat-card signature).
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.3),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '$walletCount ${l10n.t('wallets')}  •  $recordCount ${l10n.t('records')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
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
