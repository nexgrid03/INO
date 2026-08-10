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

  /// Breadcrumb of visited tabs so the system back button returns to the
  /// previous tab instead of closing the app. Only the app root (an empty
  /// history) lets a back press actually exit.
  final List<int> _tabHistory = [];

  /// Held in state so a profile edit (from the Profile tab) propagates to every
  /// destination that shows the user's details.
  late UserProfile _profile = widget.profile;

  /// Whether the one-time first-run coach-mark tour is currently showing.
  bool _tourActive = false;

  /// Locates the Home header's voice-assistant button for the tour's final
  /// step. Threaded Home → WelcomeHeader → VoiceMicIconButton.
  final GlobalKey _voiceKey = GlobalKey();

  /// Plays a brief fade + slide-in each time the destination changes. The
  /// [IndexedStack] keeps every page alive (no rebuilds, scroll preserved); we
  /// only animate the freshly-revealed page in from the right.
  late final AnimationController _pageAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
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
        FamilyVaultStore.instance.startRealtime();
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
        _tabHistory.add(_index); // remember where we came from
        _index = next;
      });
      _pageAnim.forward(from: 0);
    }
  }

  /// System back at the shell root: step back through the visited tabs; only
  /// exit the app once there's no tab history left.
  void _handleBack() {
    if (_tabHistory.isEmpty) {
      SystemNavigator.pop();
      return;
    }
    final previous = _tabHistory.removeLast();
    // Set `_index` first so `_onTabChanged` sees no change and doesn't push
    // this hop back onto the history.
    setState(() => _index = previous);
    ShellController.tab.value = previous;
    _pageAnim.forward(from: 0);
  }

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
  /// button, then the voice assistant up top. Nav positions are derived from
  /// the bar's own geometry (see [InoBottomNav]: 16px outer + 8px inner padding,
  /// 66px tall, 12px above the safe area, five equal slots).
  List<TourStep> _tourSteps(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final slotW = (size.width - 32 - 16) / 5;
    final navY = size.height - safeBottom - 12 - 33;
    Offset slot(int i) => Offset(24 + slotW * (i + 0.5), navY);

    Offset voiceCenter() {
      final box = _voiceKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        return box.localToGlobal(box.size.center(Offset.zero));
      }
      // Fallback: where the header places it (beside the bell, top-right).
      return Offset(size.width - 82, MediaQuery.paddingOf(context).top + 46);
    }

    return [
      TourStep(
        title: l10n.t('home'),
        body: l10n.t('tourHomeBody'),
        target: () => slot(0),
      ),
      TourStep(
        title: l10n.t('vault'),
        body: l10n.t('tourVaultBody'),
        target: () => slot(1),
      ),
      TourStep(
        title: l10n.t('quickAdd'),
        body: l10n.t('tourQuickAddBody'),
        target: () => slot(2),
        radius: 40,
      ),
      TourStep(
        title: l10n.t('alerts'),
        body: l10n.t('tourAlertsBody'),
        target: () => slot(3),
      ),
      TourStep(
        title: l10n.t('profile'),
        body: l10n.t('tourProfileBody'),
        target: () => slot(4),
      ),
      TourStep(
        title: l10n.t('voiceAssistant'),
        body: l10n.t('tourVoiceBody'),
        target: voiceCenter,
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
        _visitedTabs.contains(i) ? rawPages[i] : const SizedBox.shrink(),
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
      body: AnimatedBuilder(
        animation: _pageAnim,
        builder: (context, child) {
          final v = Curves.easeOutCubic.transform(_pageAnim.value);
          return Opacity(
            // Ramp from a soft 0.35 (never a harsh blank) up to fully opaque.
            opacity: 0.35 + 0.65 * v,
            child: FractionalTranslation(
              translation: Offset(
                0.06 * (1 - v),
                0,
              ), // enters from the right
              child: child,
            ),
          );
        },
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: InoBottomNav(
        index: _index,
        onSelect: _select,
        onQuickMenuAction: _onQuickAction,
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
