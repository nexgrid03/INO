import 'package:flutter/material.dart';
import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../services/wallet_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../navigation/wallet_module_router.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/home/voice_mic_button.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/create_wallet_sheet.dart';
import '../../widgets/wallet/wallet_grid.dart';
import '../notifications/notifications_screen.dart';
import 'document_search_delegate.dart';

/// The INO Wallet Hub - a premium, fast-access vault launcher.
///
/// Deliberately minimal, arranged in the "document wallet hub" rhythm:
/// a compact identity header (avatar · "My Wallets" · notifications), a hero
/// floating search bar, a single lightweight summary card ("8 Wallets • 128
/// Records") and the compact grid of all wallets, so every vault is visible
/// without scrolling - the Apple/Google Wallet model where access speed beats
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

  /// Re-reads the hub so a freshly added / removed wallet shows up with its
  /// live record count.
  void _reload() {
    // Block body on purpose: an arrow would hand setState the assigned Future
    // as its return value, which Flutter rejects.
    setState(() {
      _future = WalletRepository.instance.load();
    });
  }

  /// Create Wallet - the user's own vault, alongside the eight built-ins.
  Future<void> _addWallet() async {
    final created = await showCreateWalletSheet(context);
    if (created == null || !mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)
              .t('walletCreated')
              .replaceAll('{name}', created.name),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Long-press on a wallet. Built-ins are permanent; the user's own wallets
  /// offer a delete (documents filed under them are kept, never deleted).
  Future<void> _onLongPress(WalletCategory category) async {
    if (!CustomWalletStore.instance.isCustom(category.name)) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('deleteWallet')),
        content: Text(
          l10n.t('deleteWalletBody').replaceAll('{name}', category.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.t('delete'),
              style: const TextStyle(color: AppColors.critical),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await CustomWalletStore.instance.remove(category.name);
    if (!mounted) return;
    _reload();
  }

  /// Opens a real global search across every document in the vault.
  void _searchDocuments() {
    showSearch<void>(context: context, delegate: DocumentSearchDelegate());
  }

  /// Opens the filter panel (from the search bar's filter icon). Picking one or
  /// more wallets opens the document search constrained to those wallets - the
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

  /// The four wallets that are data modules rather than document folders. Each
  /// opens its own experience; the wallet's *documents* are still one tap away
  /// inside it, so nothing that worked before has moved out of reach.
  Widget _screenFor(WalletCategory category) => walletScreenFor(category);

  /// Opens a wallet with a premium slide + fade, then refreshes the hub - a
  /// property or card added inside a module changes that wallet's count.
  Future<void> _openWallet(WalletCategory category) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => _screenFor(category),
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
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: _WalletBackdrop(
        // The eight built-ins still fit on one screen, but the user can now add
        // wallets of their own - so the page scrolls once the grid outgrows the
        // viewport. Clamping physics keeps the old feel: no overscroll bounce,
        // no stretch/zoom on the backdrop.
        child: SafeArea(
          bottom: false,
          child: FutureBuilder<WalletHubData>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header - avatar · "My Wallets" · notification bell.
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
                    // Compact hero search - the hub's primary affordance.
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
                          // filter panel, not the search (the inner
                          // GestureDetector wins the tap over the bar's outer one).
                          trailing: _FilterButton(
                            onTap: data == null
                                ? null
                                : () => _openFilters(data.categories),
                          ),
                        ),
                      ),
                    ),
                    // Launcher grid - fixed-height cards, every wallet plus the
                    // trailing "New Wallet" slot.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: data == null
                          ? const _LoadingState()
                          : WalletGrid(
                              categories: data.categories,
                              onOpen: _openWallet,
                              onAdd: _addWallet,
                              onLongPress: _onLongPress,
                            ),
                    ),
                    // Clear the floating bottom nav (the shell extends the body
                    // behind it).
                    const SizedBox(height: 120),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The Wallet tab's own backdrop - deliberately different from the Home aurora
/// so the pale teal cards lift off the page instead of blending in.
///
/// Light mode: a cool, slightly deeper mist gradient (blue-leaning at the top,
/// warming to a near-white seafoam at the bottom) with two soft accent blobs
/// and a faint diagonal sheen. Still airy and on-theme - never dark. Dark mode
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
        // Matches the app-wide hero-sky wash (see InoBackground): the full
        // brand skyBlue at the top melting to the pale base past mid-screen.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF7DD3FC), // brand skyBlue crown
            Color(0xFFB2E2FC), // deep melt through the hero
            Color(0xFFE3F3FD), // pale wash past mid-screen
            Color(0xFFEAF4FC), // brand base
          ],
          stops: [0.0, 0.28, 0.62, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft accent blobs - quiet depth behind the grid.
           Positioned(
            top: -70,
            right: -60,
            child: DecorBlob(
              size: 260,
              color: AppColors.skyBlue,
              opacity: 0.30,
            ),
          ),
           Positioned(
            bottom: 40,
            left: -80,
            child: DecorBlob(
              size: 240,
              color: AppColors.secondaryGreen,
              opacity: 0.18,
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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.brandGradient,
            boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.28),
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
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: palette.textPrimary,
              letterSpacing: -0.7,
              height: 1.05,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const VoiceMicIconButton(size: 44),
        const SizedBox(width: 8),
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
    final iconStack = Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.notifications_none_rounded,
          size: 20,
          color: palette.textPrimary,
        ),
        if (badge > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.critical,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: LiquidGlass(
            circle: true,
            blur: 12,
            frost: palette.isDark ? 1.0 : 0.72,
            shadow: false,
            padding: EdgeInsets.zero,
            child: SizedBox(width: 44, height: 44, child: iconStack),
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
            gradient: AppColors.brandGradient,
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(AppRadius.large),
          blur: 24,
          frost: palette.isDark ? 1.1 : 0.78,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
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
                          color: Colors.transparent,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
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
                            borderRadius: BorderRadius.circular(AppRadius.pill),
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
    return  Center(
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
