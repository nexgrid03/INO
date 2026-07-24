import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/home/voice_mic_button.dart';
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

  /// Opens a real global search across every document in the vault.
  void _searchDocuments() {
    showSearch<void>(context: context, delegate: DocumentSearchDelegate());
  }

  /// Opens the filter panel (from the search bar's filter icon). Picking one or
  /// more wallets opens the document search constrained to those wallets — the
  /// filter icon never opens the plain search itself.
  Future<void> _openFilters(List<WalletCategory> categories) async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WalletFilterSheet(categories: categories),
    );
    if (selected == null || !mounted) return;
    showSearch<void>(
      context: context,
      delegate: DocumentSearchDelegate(
        walletFilter: selected.isEmpty ? null : selected,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: _WalletBackdrop(
        // A static, non-scrolling page: the header, search and full wallet grid
        // are laid out in a plain Column so the content never scrolls and never
        // stretches/zooms on an overscroll bounce. Everything fits on one screen.
        child: SafeArea(
          bottom: false,
          child: FutureBuilder<WalletHubData>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header — avatar · "My Wallets" · notification bell.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: FadeSlideIn(
                      offset: 14,
                      child: _HubHeader(
                        fullName: widget.profile.fullName,
                        notificationCount: data?.insights.length ?? 0,
                        onNotifications: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Compact hero search — the hub's primary affordance.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      offset: 14,
                      child: FloatingSearchBar(
                        hint: l10n.t('searchWallets'),
                        height: 46,
                        onTap: _searchDocuments,
                        // Its own tap target: taps on the filter icon open the
                        // filter panel, not the search (the inner GestureDetector
                        // wins the tap over the bar's outer one).
                        trailing: _FilterButton(
                          onTap: data == null
                              ? null
                              : () => _openFilters(data.categories),
                        ),
                      ),
                    ),
                  ),
                  // Launcher grid — fixed-height cards, all wallets visible.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: data == null
                        ? const _LoadingState()
                        : WalletGrid(
                            categories: data.categories,
                            onOpen: _openWallet,
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

/// The Wallet tab's own backdrop — deliberately different from the Home aurora
/// so the pale teal cards lift off the page instead of blending in.
///
/// Light mode: a cool, slightly deeper mist gradient (blue-leaning at the top,
/// warming to a near-white seafoam at the bottom) with two soft accent blobs
/// and a faint diagonal sheen. Still airy and on-theme — never dark. Dark mode
/// falls back to the standard palette background.
class _WalletBackdrop extends StatelessWidget {
  const _WalletBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (palette.isDark) {
      return Container(color: palette.bg, child: child);
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFD6EBEF), // cool blue-mist crown
            Color(0xFFE4F3F0), // seafoam middle
            Color(0xFFF1FAF6), // near-white base
          ],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft accent blobs — quiet depth behind the grid.
          const Positioned(
            top: -70,
            right: -60,
            child: DecorBlob(
              size: 260,
              color: AppColors.skyBlue,
              opacity: 0.30,
            ),
          ),
          const Positioned(
            bottom: 40,
            left: -80,
            child: DecorBlob(
              size: 240,
              color: Color(0xFF5FCBBF),
              opacity: 0.22,
            ),
          ),
          child,
        ],
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
        const SizedBox(width: 10),
        // Voice assistant — highlighted icon beside the bell.
        const VoiceMicIconButton(size: 44),
        const SizedBox(width: 10),
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
                          border: Border.all(
                            color: palette.surface,
                            width: 1.5,
                          ),
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

/// The gradient filter (tune) tile that lives at the end of the search bar. It
/// owns its own tap so pressing it opens the filter panel rather than falling
/// through to the search bar's tap.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: PressableScale(
        pressedScale: 0.9,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: BorderRadius.circular(11),
            boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.28),
          ),
          child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Bottom-sheet filter panel: pick one or more wallets to constrain the
/// document search to. Returns the selected wallet names on "Show results"
/// (an empty set means "all wallets"); returns null when dismissed.
class _WalletFilterSheet extends StatefulWidget {
  const _WalletFilterSheet({required this.categories});

  final List<WalletCategory> categories;

  @override
  State<_WalletFilterSheet> createState() => _WalletFilterSheetState();
}

class _WalletFilterSheetState extends State<_WalletFilterSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.sm),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Filter documents',
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Search within the wallets you choose.',
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in widget.categories)
                  _FilterChip(
                    label: c.name,
                    selected: _selected.contains(c.name),
                    onTap: () => setState(() {
                      _selected.contains(c.name)
                          ? _selected.remove(c.name)
                          : _selected.add(c.name);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (_selected.isNotEmpty)
                  Expanded(
                    child: PressableScale(
                      child: Material(
                        color: palette.surfaceVariant,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          side: BorderSide(color: palette.border),
                        ),
                        child: InkWell(
                          onTap: () => setState(_selected.clear),
                          child: SizedBox(
                            height: AppSizes.button,
                            child: Center(
                              child: Text(
                                'Clear',
                                style: AppText.subtitle
                                    .copyWith(color: palette.textSecondary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_selected.isNotEmpty) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: PressableScale(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(_selected),
                      child: Container(
                        height: AppSizes.button,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          boxShadow: AppShadows.glow(
                            AppColors.primaryGreen,
                            opacity: 0.28,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _selected.isEmpty
                                ? 'Search all documents'
                                : 'Show results (${_selected.length})',
                            style: AppText.subtitle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.brandGradient : null,
          color: selected ? null : palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? Colors.transparent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: selected ? Colors.white : palette.textPrimary,
            fontWeight: FontWeight.w700,
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
