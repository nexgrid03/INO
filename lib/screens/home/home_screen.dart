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
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/welcome_header.dart';
import '../../widgets/home/dashboard_card.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/home/market_card.dart';
import '../../widgets/home/quick_action_button.dart';
import '../../widgets/home/skeletons.dart';
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
/// snapshot (realistic fallback) — assembled in one load.
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

  // Real "Today's Overview" tile counts — sourced from the user's documents
  // and reminders, never fabricated. Any with no data source read as 0.
  final int documentsExpiring;
  final int remindersToday;
  final int insuranceRenewals;
  final int emiDue;
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
          .where((r) =>
              r.category == ReminderCategory.insurance &&
              r.daysFrom(today) >= 0 &&
              r.daysFrom(today) <= 30)
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
    setState(() => _future = data);
    await NotificationCenter.instance.refresh();
    await data;
  }

  // ---- Navigation ----------------------------------------------------------

  void _goToTab(int index) => ShellController.tab.value = index;

  Future<T?> _push<T>(Widget screen) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

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
      body: InoBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Greeting header — FIXED at the top. It lives outside the
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

  /// 1. Greeting Header Card — pinned at the top of the screen.
  Widget _header(AppPalette palette) {
    final sidePadding = context.responsivePadding;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.card),
        ),
        boxShadow: palette.cardShadow,
      ),
      child: Padding(
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
          ),
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
      ),

      // 2. Quick Actions — four symmetric shortcuts.
      _Section(
        header: SectionHeader(
          title: l10n.t('quickActions'),
          icon: Icons.bolt_rounded,
          iconColor: AppColors.lightBlue,
          actionLabel: l10n.t('viewAll'),
          onAction: () => _goToTab(1),
        ),
        child: _QuickActionsRow(
          onDocuments: () => _openWallet('Document Wallet'),
          onNotes: () => _push(const NotesScreen()),
          onExpenses: () => _push(const ExpenseDashboardScreen()),
          onScanner: _scan,
        ),
      ),

      // 3. Property & Finance Tools (Adaptive grid columns)
      _Section(
        header: SectionHeader(
          title: l10n.t('propertyFinanceTools'),
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

      // 4. Market Snapshot (Gold & Silver, single scannable card)
      _Section(
        header: SectionHeader(
          title: l10n.t('marketSnapshot'),
          icon: Icons.trending_up_rounded,
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
    // devices), and no trailing gap on the last one — the sliver's bottom
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

/// 2. Quick Actions — four symmetric shortcuts in one balanced row.
///
/// Exactly four actions means every tile gets an identical flex slice on any
/// screen width — no horizontal scrolling, no ragged trailing gap.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onDocuments,
    required this.onNotes,
    required this.onExpenses,
    required this.onScanner,
  });

  final VoidCallback onDocuments;
  final VoidCallback onNotes;
  final VoidCallback onExpenses;
  final VoidCallback onScanner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <Widget>[
      QuickActionButton(
        icon: Icons.folder_shared_rounded,
        label: l10n.t('documents'),
        color: AppColors.primaryGreen,
        onTap: onDocuments,
      ),
      QuickActionButton(
        icon: Icons.edit_note_rounded,
        label: l10n.t('notes'),
        color: AppColors.lightBlue,
        onTap: onNotes,
      ),
      QuickActionButton(
        icon: Icons.account_balance_wallet_rounded,
        label: l10n.t('expenses'),
        color: const Color(0xFF8B6CEF),
        onTap: onExpenses,
      ),
      QuickActionButton(
        icon: Icons.document_scanner_rounded,
        label: l10n.t('scanner'),
        color: const Color(0xFF55C2C8),
        onTap: onScanner,
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
    final tools = [
      _ToolTile(
        title: l10n.t('areaCalc'),
        icon: Icons.straighten_rounded,
        color: const Color(0xFF30ACB3),
        bgColor: const Color(0xFFEAFBF7),
        onTap: onOpenArea,
      ),
      _ToolTile(
        title: l10n.t('emiCalc'),
        icon: Icons.account_balance_rounded,
        color: const Color(0xFF55C2C8),
        bgColor: const Color(0xFFEDF8FF),
        onTap: onOpenEmi,
      ),
      _ToolTile(
        title: l10n.t('sipCalc'),
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF8B6CEF),
        bgColor: const Color(0xFFF3EFFF),
        onTap: onOpenSip,
      ),
      _ToolTile(
        title: l10n.t('stampDuty'),
        icon: Icons.gavel_rounded,
        color: const Color(0xFFF59E0B),
        bgColor: const Color(0xFFFFF7ED),
        onTap: onOpenStampDuty,
      ),
      _ToolTile(
        title: l10n.t('unitConv'),
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF7FD3D8),
        bgColor: const Color(0xFFF0F9FF),
        onTap: onOpenUnitConv,
      ),
      _ToolTile(
        title: l10n.t('taxCalc'),
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF55C2C8),
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
      // CRITICAL: with no explicit padding a GridView absorbs the ambient
      // MediaQuery insets (inflated by the extendBody nav bar) as its own
      // bottom padding — which rendered as a huge blank band between this
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        // FittedBox around the whole stack: if a tile ever ends up a hair
        // shorter than its content (tight grid aspect ratios on odd widths),
        // the content scales down imperceptibly instead of overflowing red.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
