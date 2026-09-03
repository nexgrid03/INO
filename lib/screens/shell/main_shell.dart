import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../services/family_vault_store.dart';
import '../../services/guest_mode.dart';
import '../../services/voice_greeting_service.dart';
import '../../widgets/shell/feature_tour.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/shell/quick_actions.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../reminders/reminders_screen.dart';
import '../wallet/wallet_screen.dart';
import 'placeholder_tab.dart';
import 'shell_controller.dart';

/// The app shell: an [IndexedStack] of the five primary destinations behind a
/// custom bottom navigation bar, with the voice mic floating above.
///
/// Bottom nav: Home · Wallet · Scan · Reminders · Profile. The nav bar is
/// always fixed to the bottom and stays visible while content scrolls
/// beneath it (`extendBody` lets the blur show the page through). The single
/// floating affordance is the hands-free voice mic at the bottom-right -
/// tapping it opens the voice sheet and the matched destination navigates
/// itself.
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.profile,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final UserProfile profile;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = ShellController.tab.value;

  /// Held in state so a profile edit (from the Profile tab) propagates to every
  /// destination that shows the user's details.
  late UserProfile _profile = widget.profile;

  /// Whether the one-time first-run coach-mark tour is currently showing.
  bool _tourActive = false;

  /// Locates the Home header's voice-assistant button for the tour's final
  /// step. Threaded Home → WelcomeHeader → VoiceMicIconButton.
  final GlobalKey _voiceKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();

  /// GlobalKeys for bottom nav tabs so the spotlight anchors precisely to live UI widgets.
  final GlobalKey _homeTabKey = GlobalKey();
  final GlobalKey _vaultTabKey = GlobalKey();
  final GlobalKey _quickAddKey = GlobalKey();
  final GlobalKey _alertsTabKey = GlobalKey();
  final GlobalKey _profileTabKey = GlobalKey();

  /// Plays a brief fade each time the destination changes. The [IndexedStack]
  /// keeps every page alive (no rebuilds, scroll preserved); we only fade the
  /// freshly-revealed page in — a single opacity layer over the existing
  /// RepaintBoundary, so the transition costs almost nothing per frame.
  late final AnimationController _pageAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final Animation<double> _pageFade = CurvedAnimation(
    parent: _pageAnim,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    ShellController.tab.addListener(_onTabChanged);
    // Smart voice greeting - spoken once per session when the authenticated
    // shell first appears (covers both a fresh login and opening while signed
    // in). Deferred a beat so it doesn't compete with the first-frame work.
    // greetOnce() is self-guarding: rebuilds, navigation back, or a second
    // shell mount can never replay it (see VoiceGreetingService).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Guests get no spoken greeting - there's no one to greet yet, and the
      // first-run tour is about to take the stage.
      if (!GuestMode.active) {
        VoiceGreetingService.instance.greetOnce(userName: _profile.fullName);
      }
      // One-time feature tour: nav destinations + the voice assistant. Shown
      // the very first time the shell appears on this device (i.e. right after
      // "Get Started"), then never again.
      if (!AppSettings.instance.tourSeen.value) {
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _tourActive = true);
        });
      }
      // Surface any Family Vault invitations addressed to this user on app open
      // (drives the pending badge / cards) and open a realtime subscription so
      // the list + badge stay live. Fire-and-forget; never blocks.
      if (!GuestMode.active) {
        FamilyVaultStore.instance.refreshPendingInvitations();
      }
    });
  }

  @override
  void dispose() {
    ShellController.tab.removeListener(_onTabChanged);
    _pageAnim.dispose();
    super.dispose();
  }

  final Set<int> _visitedTabs = {ShellController.tab.value};

  // Driven by the shared controller so pushed routes can switch tabs too.
  void _onTabChanged() {
    final next = ShellController.tab.value;
    // Guests may only rest on Home - every other destination needs an account.
    // Gating HERE (not in _select) catches every path that switches tabs:
    // the nav bar, in-page shortcuts and voice navigation alike.
    if (mounted && GuestMode.active && next != 0) {
      ShellController.tab.value = _index; // snap back (no-op re-entry)
      GuestMode.promptSignIn(context);
      return;
    }
    if (mounted && _index != next) {
      setState(() {
        _visitedTabs.add(next);
        _index = next;
      });
      _pageAnim.forward(from: 0);
    }
  }

  /// System back at the shell root: **Home is always one press away, and the
  /// second press exits.**
  ///
  /// Retracing the full tab history was the wrong model. Hopping
  /// Home → Wallet → Alerts → Profile meant three back presses to leave, each
  /// landing somewhere the user had already moved on from, and no way to
  /// predict how many presses "get me out" would take. Android's convention
  /// for a bottom-nav app is a single home destination that back returns to,
  /// which is also what makes the gesture safe: from anywhere but Home you go
  /// to Home, from Home you leave.
  ///
  /// Note this only fires at the shell ROOT — a pushed route (a wallet, a
  /// form) pops normally through the Navigator first, so "inside a wallet,
  /// back returns to Wallets" still holds and is untouched.
  void _handleBack() {
    // The FAB's quick menu is an overlay on top of the shell: back closes it
    // and stops there, without moving tabs or popping a route.
    if (InoBottomNav.isMenuOpen) {
      InoBottomNav.closeActiveMenu();
      return;
    }

    if (_index == _homeTab) {
      SystemNavigator.pop();
      return;
    }

    // Any other destination returns to Home; the next press then exits.
    // Set `_index` first so `_onTabChanged` sees no change and treats this as
    // an already-applied switch.
    setState(() => _index = _homeTab);
    ShellController.tab.value = _homeTab;
    _pageAnim.forward(from: 0);
  }

  /// Home's index in the bottom nav — the one destination back always returns
  /// to, and the only one a back press can exit the app from.
  static const int _homeTab = 0;

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    ShellController.tab.value = i;
  }

  /// The centre "+" button's quick menu (tap fan-out or hold-wheel) resolved
  /// to a feature. Guests get the sign-in prompt; everyone else goes straight
  /// to the shared [openQuickMenuAction] router.
  void _onQuickAction(QuickMenuAction action) async {
    if (!await GuestMode.requireAuth(context)) return;
    if (!mounted) return;
    openQuickMenuAction(context, action);
  }

  /// The one-time tour's stops: the four nav destinations, the centre quick-add
  /// button, then the voice assistant up top. Target positions are resolved
  /// live via GlobalKey + RenderBox.localToGlobal() on every frame tick.
  List<TourStep> _tourSteps(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);

    Offset resolveCenter(GlobalKey key, String name, {GlobalKey? fallbackKey}) {
      var ctx = key.currentContext;
      if (ctx == null && fallbackKey != null) {
        ctx = fallbackKey.currentContext;
      }
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.attached) {
          final pos = box.localToGlobal(box.size.center(Offset.zero));
          return pos;
        }
      }
      return Offset(size.width / 2, size.height / 2);
    }

    return [
      TourStep(
        name: 'HomeTab',
        title: l10n.t('home'),
        body: l10n.t('tourHomeBody'),
        target: () => resolveCenter(_homeTabKey, 'HomeTab'),
      ),
      TourStep(
        name: 'VaultTab',
        title: l10n.t('vault'),
        body: l10n.t('tourVaultBody'),
        target: () => resolveCenter(_vaultTabKey, 'VaultTab'),
      ),
      TourStep(
        name: 'QuickAddFAB',
        title: l10n.t('quickAdd'),
        body: l10n.t('tourQuickAddBody'),
        target: () => resolveCenter(_quickAddKey, 'QuickAddFAB'),
        radius: 40,
      ),
      TourStep(
        name: 'NotificationBell',
        title: l10n.t('alerts'),
        body: l10n.t('tourAlertsBody'),
        target: () => resolveCenter(
          _notificationsKey,
          'NotificationBell',
          fallbackKey: _alertsTabKey,
        ),
      ),
      TourStep(
        name: 'ProfileTab',
        title: l10n.t('profile'),
        body: l10n.t('tourProfileBody'),
        target: () => resolveCenter(_profileTabKey, 'ProfileTab'),
      ),
      TourStep(
        name: 'VoiceAssistant',
        title: l10n.t('voiceAssistant'),
        body: l10n.t('tourVoiceBody'),
        target: () => resolveCenter(_voiceKey, 'VoiceAssistant'),
        radius: 32,
      ),
    ];
  }

  void _finishTour() {
    setState(() => _tourActive = false);
    AppSettings.instance.setTourSeen(true);
  }

  @override
  Widget build(BuildContext context) {
    // Guests can only rest on Home (every other tab snaps back to a sign-in
    // prompt), so don't mount the real data screens unauthenticated - an
    // IndexedStack builds ALL its children, visible or not.
    final guest = GuestMode.active;
    final rawPages = [
      HomeScreen(
        profile: _profile,
        themeMode: widget.themeMode,
        onToggleTheme: widget.onToggleTheme,
        voiceTourKey: _voiceKey,
        notificationsTourKey: _notificationsKey,
      ),
      if (guest)
        const PlaceholderTab(
          titleKey: 'vault',
          icon: Icons.account_balance_wallet_rounded,
          messageKey: 'guestVaultMessage',
        )
      else
        WalletScreen(profile: _profile),
      const PlaceholderTab(
        titleKey: 'scan',
        icon: Icons.document_scanner_rounded,
        messageKey: 'guestScanMessage',
      ),
      if (guest)
        const PlaceholderTab(
          titleKey: 'alerts',
          icon: Icons.notifications_rounded,
          messageKey: 'guestAlertsMessage',
        )
      else
        RemindersScreen(profile: _profile),
      if (guest)
        const PlaceholderTab(
          titleKey: 'profile',
          icon: Icons.person_rounded,
          messageKey: 'guestProfileMessage',
        )
      else
        ProfileScreen(
          profile: _profile,
          themeMode: widget.themeMode,
          onToggleTheme: widget.onToggleTheme,
          onProfileUpdated: (updated) => setState(() => _profile = updated),
        ),
    ];

    final pages = [
      for (var i = 0; i < rawPages.length; i++)
        _visitedTabs.contains(i)
            // Pause tickers on hidden tabs — InoBackground / skeletons keep
            // animating otherwise and burn GPU while the user is elsewhere.
            ? TickerMode(enabled: i == _index, child: rawPages[i])
            : const SizedBox.shrink(),
    ];

    final shell = Scaffold(
      // Let content (and the nav's blur) sit behind the floating nav bar.
      extendBody: true,
      // Keep the bottom nav planted at all times: it lives in
      // `bottomNavigationBar` (so it never scrolls with the page), and this
      // stops the keyboard inset from ever pushing it upward. The nav stays
      // pinned to the bottom edge no matter what the body does.
      resizeToAvoidBottomInset: false,
      // The voice assistant now lives as a small icon in each page's top bar
      // (beside the notification bell), so there's no floating mic here anymore.
      // No transient overlays here: the spoken greeting is muted from
      // Settings › Preferences › "Startup greeting" (a persistent switch), not
      // from a pill that appears and disappears while it plays.
      body: FadeTransition(
        opacity: _pageFade,
        child: RepaintBoundary(
          child: IndexedStack(index: _index, children: pages),
        ),
      ),
      bottomNavigationBar: InoBottomNav(
        index: _index,
        onSelect: _select,
        onQuickMenuAction: _onQuickAction,
        homeTabKey: _homeTabKey,
        vaultTabKey: _vaultTabKey,
        quickAddKey: _quickAddKey,
        alertsTabKey: _alertsTabKey,
        profileTabKey: _profileTabKey,
      ),
    );

    return PopScope(
      // We handle the back gesture ourselves so it retraces tabs instead of
      // closing the app; only _handleBack() exits (once tab history is empty).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      // The tour overlay sits ABOVE the whole Scaffold (body + nav bar) so its
      // spotlight can point at the nav destinations themselves.
      child: Stack(
        children: [
          shell,
          if (_tourActive)
            Positioned.fill(
              child: FeatureTour(
                steps: _tourSteps(context),
                onFinish: _finishTour,
              ),
            ),
        ],
      ),
    );
  }
}
