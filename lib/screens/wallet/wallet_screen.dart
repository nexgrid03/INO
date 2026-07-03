import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../models/user_profile.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../theme/app_theme.dart';
import '../../widgets/wallet/wallet_grid.dart';
import '../../widgets/wallet/wallet_header.dart';
import '../notifications/notifications_screen.dart';
import 'document_search_delegate.dart';
import 'wallet_detail_screen.dart';

/// The INO Wallet Hub — a premium, fast-access vault launcher.
///
/// Deliberately minimal: a lightweight header (avatar · search · notifications
/// · "8 Wallets • 128 Records") above a compact grid of all wallets, so every
/// vault is visible without scrolling — the Apple/Google Wallet model where
/// access speed beats analytics. Tapping a wallet opens its detail screen.
/// (Overview analytics, quick actions, recents, security and insights now live
/// on the detail/other screens.)
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
                  // Header — compact, with the lightweight summary line.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: WalletHeader(
                        fullName: widget.profile.fullName,
                        walletCount: data?.categories.length ?? 0,
                        recordCount: data?.overview.totalRecords ?? 0,
                        notificationCount: data?.insights.length ?? 0,
                        onSearch: () => _searchDocuments(),
                        onNotifications: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const NotificationsScreen()),
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
