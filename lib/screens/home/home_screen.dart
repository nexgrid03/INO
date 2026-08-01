import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../data/dashboard_repository.dart';
import '../../data/reminder_store.dart';
import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../models/reminder_models.dart';
import '../../models/user_profile.dart';
import '../../repositories/document_repository.dart';
import '../../services/document_protection_store.dart';
import '../../services/market_rates_service.dart';
import '../../services/net_worth_service.dart';
import '../../services/notification_center.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../services/guest_mode.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/shiny_border.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/welcome_header.dart';
import '../../widgets/home/dashboard_card.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/home/market_card.dart';
import '../../widgets/home/quick_action_button.dart';
import '../../widgets/home/skeletons.dart';
import '../documents/offline_documents_screen.dart';
import '../expenses/expense_dashboard_screen.dart';
import '../expenses/tax_records_screen.dart';
import '../home/pending_actions_screen.dart';
import '../markets/markets_screen.dart';
import '../notes/notes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../property/area_converter_screen.dart';
import '../property_finance/emi_calculator_screen.dart';
import '../property_finance/property_finance_tools_screen.dart';
import '../property_finance/property_valuation_screen.dart';
import '../property_finance/sip_calculator_screen.dart';
import '../reminders/reminders_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../shell/shell_controller.dart';
import '../wallet/wallet_detail_screen.dart';

/// The read model the Home screen renders: a real-data hero and the market
/// snapshot (realistic fallback) - assembled in one load.
class _HomeData {
  const _HomeData({
    required this.hero,
    required this.market,
    required this.documentsExpiring,
    required this.remindersToday,
    required this.insuranceRenewals,
    required this.emiDue,
  });

  final HomeHero hero;
  final List<MarketQuote> market;

  // Real "Today's Overview" tile counts - sourced from the user's documents
  // and reminders, never fabricated. Any with no data source read as 0.
  final int documentsExpiring;
  final int remindersToday;
  final int insuranceRenewals;
  final int emiDue;
}

/// The INO Home - Premium Responsive Fintech & Digital Life Management Dashboard.
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
    this.voiceTourKey,
  });

  final UserProfile profile;
  final ThemeMode themeMode;
  final VoidCallback? onToggleTheme;

  /// Attached to the header's voice-assistant button so the first-run tour can
  /// spotlight it (see [MainShell]).
  final GlobalKey? voiceTourKey;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  /// Session-local dismissal of the expiry alert banner.
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    NotificationCenter.instance.load();
  }

  Future<_HomeData> _load() async {
    final dashboard = await DashboardRepository.instance.load();
    final market = await MarketRatesService.instance.fetchLive(
      dashboard.market,
    );

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
    var remindersToday = 0;
    var insuranceRenewals = 0;
    try {
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      final active = ReminderStore.instance.active;
      pending += active.where((r) => r.daysFrom(today) <= 7).length;
      remindersToday = active.where((r) => r.daysFrom(today) == 0).length;
      insuranceRenewals = active
          .where(
            (r) =>
                r.category == ReminderCategory.insurance &&
                r.daysFrom(today) >= 0 &&
                r.daysFrom(today) <= 30,
          )
          .length;
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
      documentsExpiring: expiringDocuments,
      remindersToday: remindersToday,
      insuranceRenewals: insuranceRenewals,
      // No EMI/loan data source exists in the app yet, so this reads 0 rather
      // than a fabricated figure. Wire a loan store here when one lands.
      emiDue: 0,
    );
  }

  Future<void> _refresh() async {
    final data = _load();
    // Block body: an arrow hands setState the assigned Future, which it rejects.
    setState(() {
      _future = data;
    });
    await NotificationCenter.instance.refresh();
    await data;
  }

  // ---- Navigation ----------------------------------------------------------

  // Tab switches are gated for guests inside MainShell._onTabChanged, so this
  // needs no guard of its own.
  void _goToTab(int index) => ShellController.tab.value = index;

  /// The single choke point every Home shortcut funnels through - which is
  /// what lets guest explore mode gate "anything that opens a feature" with
  /// one sign-in check instead of one per tile.
  Future<T?> _push<T>(Widget screen) async {
    if (!await GuestMode.requireAuth(context)) return null;
    if (!mounted) return null;
    return Navigator.of(
      context,
    ).push<T>(MaterialPageRoute(builder: (_) => screen));
  }

  void _scan() async {
    if (!await GuestMode.requireAuth(context)) return;
    if (!mounted) return;
    launchScanFlow(context);
  }

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
      body: InoBackground(
        sky: true,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Greeting header - FIXED at the top. It lives outside the
              // scroll view, so it stays pinned while the content below scrolls.
              _header(palette),
              // 2. Scrollable content beneath the fixed header.
              Expanded(
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
                          if (hasError)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: ErrorRetry(onRetry: _refresh),
                            )
                          else if (data == null)
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                sidePadding,
                                AppSpacing.md,
                                sidePadding,
                                120.rh,
                              ),
                              sliver: const SliverToBoxAdapter(
                                child: DashboardSkeleton(),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                sidePadding,
                                AppSpacing.md,
                                sidePadding,
                                120.rh,
                              ),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Greeting Header - pinned at the top of the screen. It sits directly
  /// on the hero-sky gradient (no card of its own), so the brand-blue band
  /// flows from the status bar down behind the greeting, like the reference
  /// vault design.
  Widget _header(AppPalette palette) {
    final sidePadding = context.responsivePadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePadding,
        AppSpacing.sm,
        sidePadding,
        AppSpacing.md,
      ),
      child: ListenableBuilder(
        listenable: NotificationCenter.instance,
        builder: (context, _) => WelcomeHeader(
          fullName: widget.profile.fullName,
          photoUrl: widget.profile.profilePhoto,
          notificationCount: NotificationCenter.instance.unreadCount,
          onProfile: () => _goToTab(4),
          onNotifications: () => _push(const NotificationsScreen()),
          voiceButtonKey: widget.voiceTourKey,
        ),
      ),
    );
  }

  List<Widget> _sections(_HomeData data) {
    final l10n = AppLocalizations.of(context);

    // Four balanced sections with one consistent rhythm: hero → actions →
    // tools → market. Each is separated by the same generous gap so the page
    // reads as an intentional, evenly-weighted composition.
    final sections = <Widget>[
      // 1. Today's Overview (Main Hero Section)
      DashboardCard(
        hero: data.hero,
        documentsExpiring: data.documentsExpiring,
        remindersToday: data.remindersToday,
        insuranceRenewals: data.insuranceRenewals,
        emiDue: data.emiDue,
        onDocumentsExpiring: () => _push(const PendingActionsScreen()),
        onEmiDues: () => _push(const EmiCalculatorScreen()),
        onRemindersToday: () => _push(RemindersScreen(profile: widget.profile)),
        onInsuranceRenewals: () => _openWallet('Insurance Wallet'),
        onCta: () => _openWallet('Document Wallet'),
      ),

      // 2. Quick Actions - four symmetric shortcuts.
      _Section(
        header: SectionHeader(
          title: l10n.t('quickActions'),
          actionLabel: l10n.t('viewAll'),
          onAction: () => _goToTab(1),
        ),
        child: _QuickActionsRow(
          onDocuments: () => _openWallet('Document Wallet'),
          onNotes: () => _push(const NotesScreen()),
          onExpenses: () => _push(const ExpenseDashboardScreen()),
          onScanner: _scan,
          onOffline: () => _push(const OfflineDocumentsScreen()),
        ),
      ),

      // 2b. Expiry alert banner (reference alignment): only when documents
      // are actually expiring, dismissible for the session.
      if (data.documentsExpiring > 0 && !_bannerDismissed)
        _ExpiryBanner(
          count: data.documentsExpiring,
          onReview: () => _push(const PendingActionsScreen()),
          onDismiss: () => setState(() => _bannerDismissed = true),
        ),

      // 3. Property & Finance Tools (Adaptive grid columns)
      _Section(
        header: SectionHeader(
          title: l10n.t('propertyFinanceTools'),
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

      // 4. Market Snapshot (Gold & Silver, single scannable card)
      _Section(
        header: SectionHeader(
          title: l10n.t('marketSnapshot'),
          actionLabel: l10n.t('viewMarkets'),
          onAction: () => _push(MarketsScreen(quotes: data.market)),
        ),
        child: MarketCard(
          quotes: data.market,
          onTap: () => _push(MarketsScreen(quotes: data.market)),
        ),
      ),
    ];

    // One consistent vertical rhythm for the whole screen: an identical, tight
    // gap between every section (fixed, so it never over-scales on tall
    // devices), and no trailing gap on the last one - the sliver's bottom
    // padding owns the clearance above the floating nav.
    const sectionGap = 22.0;
    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: EdgeInsets.only(
            bottom: i == sections.length - 1 ? 0 : sectionGap,
          ),
          child: FadeSlideIn(
            delay: Duration(milliseconds: (i * 60).clamp(0, 360)),
            child: sections[i],
          ),
        ),
    ];
  }
}

/// The dismissible alert banner (reference "Passport expires in 5 days" row):
/// a brand-gradient icon disc, title + hint, a gradient "Review →" pill and a
/// dismiss cross - all on one white glass card.
class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({
    required this.count,
    required this.onReview,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? '1 document expiring soon'
                      : '$count documents expiring soon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review now to stay on track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PressableScale(
            child: GestureDetector(
              onTap: onReview,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Review',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 13, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
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

/// 2. Quick Actions - four symmetric shortcuts in one balanced row.
///
/// Exactly four actions means every tile gets an identical flex slice on any
/// screen width - no horizontal scrolling, no ragged trailing gap.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onDocuments,
    required this.onNotes,
    required this.onExpenses,
    required this.onScanner,
    required this.onOffline,
  });

  final VoidCallback onDocuments;
  final VoidCallback onNotes;
  final VoidCallback onExpenses;
  final VoidCallback onScanner;
  final VoidCallback onOffline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // One clearly distinct hue per action. Documents, Notes and Scanner used to
    // be three shades of the same teal (Notes' `lightBlue` and Scanner were the
    // identical #38BDF8), so the row read as one repeated button.
    final actions = <Widget>[
      QuickActionButton(
        icon: Icons.folder_shared_rounded,
        label: l10n.t('documents'),
        color: AppColors.primaryGreen, // teal - the brand anchor
        onTap: onDocuments,
      ),
      QuickActionButton(
        icon: Icons.edit_note_rounded,
        label: l10n.t('notes'),
        color: const Color(0xFFF2B33D), // amber - paper & pencil
        onTap: onNotes,
      ),
      QuickActionButton(
        icon: Icons.account_balance_wallet_rounded,
        label: l10n.t('expenses'),
        color: const Color(0xFF8B6CEF), // purple - money
        onTap: onExpenses,
      ),
      QuickActionButton(
        icon: Icons.document_scanner_rounded,
        label: l10n.t('scanner'),
        color: const Color(0xFF4383EA), // blue - capture / tech
        onTap: onScanner,
      ),
      QuickActionButton(
        icon: Icons.offline_pin_rounded,
        label: 'Offline',
        color: const Color(0xFF14B8A6), // seafoam - always available
        onTap: onOffline,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
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
    final l10n = AppLocalizations.of(context);
    // One distinct hue per tool, from the app's curated accent family. Four of
    // the six used to be teal (two were the same #38BDF8), so the grid read as
    // one repeated tile. The tint behind each icon is derived from its own
    // accent, so the two can no longer drift apart.
    final tools = [
      _ToolTile(
        title: l10n.t('areaCalc'),
        icon: Icons.straighten_rounded,
        color: const Color(0xFF0EA5E9), // teal
        onTap: onOpenArea,
      ),
      _ToolTile(
        title: l10n.t('emiCalc'),
        icon: Icons.account_balance_rounded,
        color: const Color(0xFF4383EA), // blue
        onTap: onOpenEmi,
      ),
      _ToolTile(
        title: l10n.t('sipCalc'),
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF9B6DE0), // purple
        onTap: onOpenSip,
      ),
      _ToolTile(
        title: l10n.t('stampDuty'),
        icon: Icons.gavel_rounded,
        color: const Color(0xFFF2B33D), // amber
        onTap: onOpenStampDuty,
      ),
      _ToolTile(
        title: l10n.t('unitConv'),
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF06B6D4), // cyan
        onTap: onOpenUnitConv,
      ),
      _ToolTile(
        title: l10n.t('taxCalc'),
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF10B981), // green
        onTap: onOpenTax,
      ),
    ];

    final columns = context.toolsColumns;
    final aspectRatio = context.toolsAspectRatio;

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // CRITICAL: with no explicit padding a GridView absorbs the ambient
      // MediaQuery insets (inflated by the extendBody nav bar) as its own
      // bottom padding - which rendered as a huge blank band between this
      // section and Market Snapshot. Zero it so the section-gap system is the
      // only source of vertical rhythm.
      padding: EdgeInsets.zero,
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
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final themeStyle = InoStyle.of(context);
    final bold = themeStyle == ThemeStyle.bold;
    final soft = themeStyle == ThemeStyle.soft;

    // Divine Glass: classic/soft tiles are white glass cards with a hairline
    // light-blue edge and whisper shadow. Bold keeps its accent-flooded fill.
    final fill = bold ? InoStyle.boldFill(color) : palette.surface;
    final edge = bold ? InoStyle.boldBorder(color) : palette.border;

    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge, width: bold ? 2 : 1),
        boxShadow: bold ? null : palette.cardShadow,
      ),
      // FittedBox around the whole stack: if a tile ever ends up a hair
      // shorter than its content (tight grid aspect ratios on odd widths),
      // the content scales down imperceptibly instead of overflowing red.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A pastel accent chip: the tool's coloured glyph on its own soft
            // tint. In bold the badge body drops away and the bare glyph
            // grows into the slot.
            bold
                ? SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(icon, color: Colors.white, size: 26),
                  )
                : Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              style: TextStyle(
                color: bold ? Colors.white : palette.textPrimary,
                fontSize: bold ? 14 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Soft: the classic accent border picks up the glass sheen.
      child: ShinyBorder(radius: 16, width: 1, enabled: soft, child: tile),
    );
  }
}
