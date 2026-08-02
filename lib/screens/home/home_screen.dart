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
import '../../widgets/common/ino_svg_icon.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/common/shiny_border.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/dashboard/welcome_header.dart';
import '../../widgets/home/dashboard_card.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/home/market_card.dart';
import '../../widgets/home/my_vaults_row.dart';
import '../../widgets/home/pending_actions_row.dart';
import '../../widgets/home/quick_action_button.dart';
import '../../widgets/home/launcher_finance_tools.dart';
import '../../widgets/home/launcher_hub_shortcuts.dart';
import '../../widgets/home/launcher_quick_actions.dart';
import '../../widgets/home/skeletons.dart';
import '../../widgets/home/voice_mic_button.dart';
import '../documents/offline_documents_screen.dart';
import '../expenses/expense_dashboard_screen.dart';
import '../expenses/tax_records_screen.dart';
import '../home/pending_actions_screen.dart';
import '../markets/markets_screen.dart';
import '../notes/notes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/help_center_screen.dart';
import '../property/area_converter_screen.dart';
import '../property_finance/emi_calculator_screen.dart';
import '../property_finance/property_finance_tools_screen.dart';
import '../property_finance/property_valuation_screen.dart';
import '../property_finance/sip_calculator_screen.dart';
import '../reminders/reminders_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../shell/shell_controller.dart';
import '../../navigation/wallet_module_router.dart';
import '../networth/net_worth_analytics_screen.dart';

/// The read model the Home screen renders: a real-data hero, vault counts for
/// My Vaults, reminder buckets for Launcher, and the market snapshot.
class _HomeData {
  const _HomeData({
    required this.hero,
    required this.market,
    required this.documentsExpiring,
    required this.remindersToday,
    required this.remindersTomorrow,
    required this.remindersThisWeek,
    required this.remindersCompleted,
    required this.insuranceRenewals,
    required this.emiDue,
    required this.identityCount,
    required this.propertyCount,
    required this.investmentCount,
    required this.cardsCount,
    required this.pendingItems,
  });

  final HomeHero hero;
  final List<MarketQuote> market;

  final int documentsExpiring;
  final int remindersToday;
  final int remindersTomorrow;
  final int remindersThisWeek;
  final int remindersCompleted;
  final int insuranceRenewals;
  final int emiDue;

  final int identityCount;
  final int propertyCount;
  final int investmentCount;
  final int cardsCount;

  final List<LauncherPendingItem> pendingItems;
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
    var remindersTomorrow = 0;
    var remindersThisWeek = 0;
    var remindersCompleted = 0;
    var insuranceRenewals = 0;
    final pendingItems = <LauncherPendingItem>[];
    try {
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      final active = ReminderStore.instance.active;
      pending += active.where((r) => r.daysFrom(today) <= 7).length;
      remindersToday = active.where((r) => r.daysFrom(today) == 0).length;
      remindersTomorrow = active.where((r) => r.daysFrom(today) == 1).length;
      remindersThisWeek = active
          .where((r) => r.daysFrom(today) >= 0 && r.daysFrom(today) <= 7)
          .length;
      remindersCompleted = ReminderStore.instance.completed.length;
      insuranceRenewals = active
          .where(
            (r) =>
                r.category == ReminderCategory.insurance &&
                r.daysFrom(today) >= 0 &&
                r.daysFrom(today) <= 30,
          )
          .length;

      for (final r in active.where((r) => r.daysFrom(today) <= 7).take(6)) {
        final d = r.daysFrom(today);
        pendingItems.add(
          LauncherPendingItem(
            title: r.title,
            status: d < 0
                ? 'Overdue'
                : (d <= 3 ? 'Due Soon' : 'On Track'),
            icon: r.category.icon,
            accent: reminderUrgencyColor(r, today),
          ),
        );
      }
    } catch (_) {}

    // Expiring docs also feed the pending strip when reminders are sparse.
    if (pendingItems.length < 3 && expiringDocuments > 0) {
      pendingItems.add(
        LauncherPendingItem(
          title: expiringDocuments == 1
              ? '1 document expiring'
              : '$expiringDocuments documents expiring',
          status: 'Due Soon',
          icon: Icons.description_rounded,
          accent: AppColors.warning,
        ),
      );
    }

    var identityCount = 0;
    var propertyCount = 0;
    var investmentCount = 0;
    var cardsCount = 0;
    try {
      final hub = await WalletRepository.instance.load();
      for (final c in hub.categories) {
        final n = int.tryParse(c.metric) ?? 0;
        switch (c.name) {
          case 'Identity Wallet':
            identityCount = n;
          case 'Property Wallet':
            propertyCount = n;
          case 'Investment Wallet':
            investmentCount = n;
          case 'Banking Wallet':
            cardsCount = n;
        }
      }
    } catch (_) {}

    HomeHero hero;
    try {
      await NetWorthService.instance.ensureReady();
      hero = NetWorthService.instance.heroFrom(
        assets: documentCount,
        documents: documentCount,
        pendingTasks: pending,
        protectedItems: DocumentProtectionStore.instance.protectedCount,
      );
    } catch (_) {
      hero = HomeHero(
        netWorth: '₹0',
        growthPercent: 0,
        growthAmount: '₹0',
        trend: const [0, 0, 0, 0, 0, 0, 0],
        assets: documentCount,
        documents: documentCount,
        pendingTasks: pending,
        protectedItems: DocumentProtectionStore.instance.protectedCount,
      );
    }

    return _HomeData(
      hero: hero,
      market: market,
      documentsExpiring: expiringDocuments,
      remindersToday: remindersToday,
      remindersTomorrow: remindersTomorrow,
      remindersThisWeek: remindersThisWeek,
      remindersCompleted: remindersCompleted,
      insuranceRenewals: insuranceRenewals,
      emiDue: 0,
      identityCount: identityCount,
      propertyCount: propertyCount,
      investmentCount: investmentCount,
      cardsCount: cardsCount,
      pendingItems: pendingItems,
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
    if (category == null) return;
    _push(walletScreenFor(category));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final sidePadding = context.responsivePadding;
    // Rebuild Home when Profile → App theme changes (classic vs launcher layout).
    final style = InoStyle.of(context);

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
                                key: ValueKey(style),
                                delegate: SliverChildListDelegate(
                                  _sections(data, style),
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

  Widget _header(AppPalette palette) {
    final sidePadding = context.responsivePadding;
    final launcher = InoStyle.of(context) == ThemeStyle.launcher;
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
          launcherStyle: launcher,
          onHelp: () => _push(const HelpCenterScreen()),
        ),
      ),
    );
  }

  List<Widget> _sections(_HomeData data, ThemeStyle style) {
    final l10n = AppLocalizations.of(context);
    if (style == ThemeStyle.launcher) {
      return _wrapSections(_launcherSections(data, l10n));
    }
    return _wrapSections(_classicSections(data, l10n));
  }

  List<Widget> _wrapSections(List<Widget> sections) {
    const sectionGap = 22.0;
    // Launcher: no staggered FadeSlideIn — each section starts a ticker and
    // on Flutter web that + many glass tiles left content stuck at opacity 0
    // (blank Home) and flooded mouse_tracker assertions.
    final animate = InoStyle.of(context) != ThemeStyle.launcher;
    return [
      for (var i = 0; i < sections.length; i++)
        Padding(
          padding: EdgeInsets.only(
            bottom: i == sections.length - 1 ? 0 : sectionGap,
          ),
          child: animate
              ? FadeSlideIn(
                  delay: Duration(milliseconds: (i * 60).clamp(0, 360)),
                  child: sections[i],
                )
              : sections[i],
        ),
    ];
  }

  /// Classic / Bold / Soft — original Home (unchanged structure).
  List<Widget> _classicSections(_HomeData data, AppLocalizations l10n) {
    return [
      DashboardCard(
        hero: data.hero,
        documentsExpiring: data.documentsExpiring,
        remindersToday: data.remindersToday,
        insuranceRenewals: data.insuranceRenewals,
        emiDue: data.emiDue,
        onDocumentsExpiring: () => _push(const PendingActionsScreen()),
        onEmiDues: () => _push(const EmiCalculatorScreen()),
        onRemindersToday: () =>
            _push(RemindersScreen(profile: widget.profile)),
        onInsuranceRenewals: () => _openWallet('Insurance Wallet'),
        onCta: () => _openWallet('Document Wallet'),
      ),
      _Section(
        header: SectionHeader(title: l10n.t('quickActions')),
        child: _QuickActionsRow(
          useSvg: false,
          onDocuments: () => _openWallet('Document Wallet'),
          onNotes: () => _push(const NotesScreen()),
          onExpenses: () => _push(const ExpenseDashboardScreen()),
          onScanner: _scan,
          onOffline: () => _push(const OfflineDocumentsScreen()),
        ),
      ),
      if (data.documentsExpiring > 0 && !_bannerDismissed)
        _ExpiryBanner(
          count: data.documentsExpiring,
          onReview: () => _push(const PendingActionsScreen()),
          onDismiss: () => setState(() => _bannerDismissed = true),
        ),
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
  }

  /// Launcher theme — first fold: hero → quick actions → vaults.
  /// One "Needs attention" module merges expiry / pending / summary strip.
  /// Hub shortcuts (Expenses · Net Worth) sit after tools, below the fold.
  List<Widget> _launcherSections(_HomeData data, AppLocalizations l10n) {
    final pendingCount = data.pendingItems.length;
    void openPending() {
      _push(const PendingActionsScreen());
    }
    return [
      // 1. Vault hero
      DashboardCard(
        hero: data.hero,
        showSummaryStrip: false,
        onCta: () => _openWallet('Document Wallet'),
      ),

      // 2. Quick Actions — Scan / Documents / Reminder / Voice
      _Section(
        header: SectionHeader(title: l10n.t('quickActions')),
        child: LauncherQuickActions(
          onScan: _scan,
          onAddDocument: () => _openWallet('Document Wallet'),
          onAddReminder: () =>
              _push(RemindersScreen(profile: widget.profile)),
          onVoice: () => showVoiceCommandSheet(context),
        ),
      ),

      // 3. My Vaults
      _Section(
        header: SectionHeader(
          title: l10n.t('myVaults'),
          actionLabel: l10n.t('viewAll'),
          onAction: () => _goToTab(1),
        ),
        child: MyVaultsRow(
          identityCount: data.identityCount,
          propertyCount: data.propertyCount,
          investmentCount: data.investmentCount,
          cardsCount: data.cardsCount,
          onIdentity: () => _openWallet('Identity Wallet'),
          onProperty: () => _openWallet('Property Wallet'),
          onInvestments: () => _openWallet('Investment Wallet'),
          onCards: () => _openWallet('Banking Wallet'),
        ),
      ),

      // 4. Needs attention — summary strip + pending cards (single module)
      _Section(
        header: SectionHeader(
          title: l10n.t('needsAttention'),
          actionLabel: l10n.t('viewAll'),
          onAction: openPending,
        ),
        child: Column(
          children: [
            HomeSummaryStrip(
              documentsExpiring: data.documentsExpiring,
              remindersToday: data.remindersToday,
              insuranceRenewals: data.insuranceRenewals,
              emiDue: data.emiDue,
              pendingCount: pendingCount,
              replaceRemindersWithPending: true,
              enlargedIcons: true,
              onDocumentsExpiring: openPending,
              onEmiDues: () => _push(const EmiCalculatorScreen()),
              onPending: openPending,
              onInsuranceRenewals: () => _openWallet('Insurance Wallet'),
            ),
            const SizedBox(height: 12),
            PendingActionsRow(
              items: [
                for (final p in data.pendingItems)
                  LauncherPendingItem(
                    title: p.title,
                    status: p.status,
                    icon: p.icon,
                    accent: p.accent,
                    onTap: openPending,
                  ),
              ],
              onViewAll: openPending,
            ),
          ],
        ),
      ),

      // 5. Property & Finance Tools
      _Section(
        header: SectionHeader(
          title: l10n.t('propertyFinanceTools'),
          actionLabel: l10n.t('viewAll'),
          onAction: () => _push(const PropertyFinanceToolsScreen()),
        ),
        child: LauncherFinanceTools(
          onOpenArea: () => _push(const AreaConverterScreen()),
          onOpenEmi: () => _push(const EmiCalculatorScreen()),
          onOpenSip: () => _push(const SipCalculatorScreen()),
          onOpenStampDuty: () => _push(const PropertyValuationScreen()),
          onOpenUnitConv: () => _push(const AreaConverterScreen()),
          onOpenTax: () => _push(const TaxRecordsScreen()),
        ),
      ),

      // 6. Secondary hubs (below the fold)
      LauncherHubShortcuts(
        onExpenses: () => _push(const ExpenseDashboardScreen()),
        onNetWorth: () => _push(const NetWorthAnalyticsScreen()),
      ),

      // 7. Market Snapshot
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
    return LiquidGlass(
      borderRadius: BorderRadius.circular(18),
      blur: 18,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
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

/// Quick Actions row for Classic / Bold / Soft themes.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.useSvg,
    required this.onDocuments,
    required this.onNotes,
    required this.onExpenses,
    required this.onScanner,
    required this.onOffline,
  });

  final bool useSvg;
  final VoidCallback onDocuments;
  final VoidCallback onNotes;
  final VoidCallback onExpenses;
  final VoidCallback onScanner;
  final VoidCallback onOffline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <Widget>[
      QuickActionButton(
        icon: useSvg ? null : Icons.folder_shared_rounded,
        svgAsset: useSvg ? InoHomeIcons.documents : null,
        label: l10n.t('documents'),
        color: AppColors.primaryGreen,
        onTap: onDocuments,
      ),
      QuickActionButton(
        icon: useSvg ? null : Icons.edit_note_rounded,
        svgAsset: useSvg ? InoHomeIcons.notes : null,
        label: l10n.t('notes'),
        color: AppColors.accentAmber,
        onTap: onNotes,
      ),
      QuickActionButton(
        icon: useSvg ? null : Icons.account_balance_wallet_rounded,
        svgAsset: useSvg ? InoHomeIcons.expenses : null,
        label: l10n.t('expenses'),
        color: AppColors.vaultIdentity,
        onTap: onExpenses,
      ),
      QuickActionButton(
        icon: useSvg ? null : Icons.document_scanner_rounded,
        svgAsset: useSvg ? InoHomeIcons.scan : null,
        label: l10n.t('scanner'),
        color: AppColors.accentIndigo,
        onTap: onScanner,
      ),
      QuickActionButton(
        icon: useSvg ? null : Icons.offline_pin_rounded,
        svgAsset: useSvg ? InoHomeIcons.offline : null,
        label: 'Offline',
        color: AppColors.accentCyan,
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

/// Property & Finance Tools grid for Classic / Bold / Soft.
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
    final columns = context.toolsColumns;

    final tools = [
      _ToolTile(
        title: l10n.t('areaCalc'),
        icon: Icons.straighten_rounded,
        color: AppColors.primaryGreen,
        onTap: onOpenArea,
      ),
      _ToolTile(
        title: l10n.t('emiCalc'),
        icon: Icons.account_balance_rounded,
        color: AppColors.accentIndigo,
        onTap: onOpenEmi,
      ),
      _ToolTile(
        title: l10n.t('sipCalc'),
        icon: Icons.trending_up_rounded,
        color: AppColors.accentViolet,
        onTap: onOpenSip,
      ),
      _ToolTile(
        title: l10n.t('stampDuty'),
        icon: Icons.gavel_rounded,
        color: AppColors.accentAmber,
        onTap: onOpenStampDuty,
      ),
      _ToolTile(
        title: l10n.t('unitConv'),
        icon: Icons.swap_horiz_rounded,
        color: AppColors.accentCyan,
        onTap: onOpenUnitConv,
      ),
      _ToolTile(
        title: l10n.t('taxCalc'),
        icon: Icons.receipt_long_rounded,
        color: AppColors.accentEmerald,
        onTap: onOpenTax,
      ),
    ];

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: context.toolsAspectRatio,
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

    final iconBox = 32.0;
    final iconSize = bold ? 26.0 : 18.0;

    final Widget glyph = Icon(
      icon,
      color: bold ? Colors.white : color,
      size: iconSize,
    );

    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bold
              ? SizedBox(
                  width: iconBox,
                  height: iconBox,
                  child: Center(child: glyph),
                )
              : Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: glyph,
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
    );

    final tile = bold
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: InoStyle.boldFill(color),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: InoStyle.boldBorder(color), width: 2),
            ),
            child: content,
          )
        : LiquidGlass(
            borderRadius: BorderRadius.circular(16),
            blur: 16,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: content,
          );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ShinyBorder(radius: 16, width: 1, enabled: soft, child: tile),
    );
  }
}
