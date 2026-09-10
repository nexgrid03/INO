import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../services/family_vault_store.dart';
import '../../services/guest_mode.dart';
import '../../services/voice_greeting_service.dart';
import '../../theme/ino_scroll_behavior.dart';
import '../../widgets/profile/security_reminder_dialog.dart';
import '../../widgets/shell/feature_tour.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/shell/quick_actions.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../reminders/reminders_screen.dart';
import '../wallet/wallet_screen.dart';
import 'shell_controller.dart';

/// The app shell: a horizontal pager of the primary destinations behind a
/// custom bottom navigation bar.
///
/// Bottom nav: Home · Wallet · **+** · Reminders · Profile. The nav bar is
/// always fixed to the bottom and stays visible while content scrolls beneath
/// it (`extendBody` lets the page show through).
///
/// **Destinations swipe.** Dragging left or right moves between them, with the
/// content following the finger and snapping to the next tab in bottom-bar
/// order; tapping a tab glides to it. The centre "+" is a menu, not a page, so
/// it is not in the swipe set - swiping from Wallet lands on Reminders. See
/// [_pageOrder].
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

class _MainShellState extends State<MainShell> {
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

  /// The destinations that are actually pages, in swipe order.
  ///
  /// Bottom-bar slot 2 is the centre "+" quick menu, not a destination, so it
  /// is deliberately absent: swiping from Wallet lands on Reminders, and the
  /// swipe never dead-ends on a page that does not exist.
  ///
  /// Guests may only rest on Home (every other tab prompts sign-in), so their
  /// swipe set is Home alone rather than three pages they would be bounced off
  /// the moment they arrived.
  List<int> get _pageOrder =>
      GuestMode.active ? const [_homeTab] : const [0, 1, 3, 4];

  /// The pager position showing [tab], or Home's if that tab is not swipeable
  /// in the current auth state.
  int _pagePosFor(int tab) {
    final i = _pageOrder.indexOf(tab);
    return i < 0 ? 0 : i;
  }

  late final PageController _pager = PageController(
    initialPage: _pagePosFor(_index),
  );

  /// While a tap-driven glide is in flight, the destination it is heading for.
  ///
  /// A tap on a non-adjacent tab crosses a page we are only passing through,
  /// and [PageView.onPageChanged] fires for it. Without this gate that
  /// intermediate page would be applied as if the user had chosen it - flipping
  /// the nav highlight and firing the tab's arrival work en route.
  int? _navTarget;

  /// Whether the pager is currently moving - a finger swipe, or a tap-driven
  /// glide.
  ///
  /// Drives [TickerMode] for the pages either side of the current one. Resting
  /// off-screen destinations must stay frozen (their ambient drifts and
  /// skeletons would otherwise burn GPU while the user is elsewhere), but a
  /// page sliding INTO view has to be live, or a still-loading tab arrives with
  /// a frozen spinner painted on it.
  ///
  /// A notifier rather than plain state so a swipe rebuilds four [TickerMode]s
  /// instead of every destination's widget tree.
  final ValueNotifier<bool> _pagerMoving = ValueNotifier<bool>(false);

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
      } else if (!GuestMode.active) {
        // If tour was already seen, check if user needs to link their second entity
        Future<void>.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            SecurityReminderDialog.showIfEligible(
              context,
              profile: _profile,
              onProfileUpdated: (updated) {
                if (mounted) setState(() => _profile = updated);
              },
            );
          }
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
    _pagerMoving.dispose();
    _pager.dispose();
    super.dispose();
  }

  // Driven by the shared controller so pushed routes can switch tabs too.
  void _onTabChanged() {
    final next = ShellController.tab.value;
    if (!mounted) return;
    // Guests may only rest on Home - every other destination needs an account.
    // Gating HERE (not in _select) catches every path that switches tabs:
    // the nav bar, in-page shortcuts and voice navigation alike.
    if (GuestMode.active && next != _homeTab) {
      ShellController.tab.value = _index; // snap back (no-op re-entry)
      GuestMode.promptSignIn(context);
      return;
    }
    _goToTab(next);
  }

  /// Glides the pager to [tab].
  ///
  /// The nav highlight flips immediately - a tap has to feel answered - while
  /// the content glides underneath.
  ///
  /// For a non-adjacent tap we hop to the neighbouring page first, so the
  /// animation only ever crosses ONE page. The destinations we would otherwise
  /// scroll past never get built (no wasted first-build work, no network
  /// fetches for a tab nobody asked for), and it reads as a clean single-step
  /// glide rather than a blur through everything in between.
  void _goToTab(int tab) {
    final pos = _pageOrder.indexOf(tab);
    if (pos < 0) return; // not a page (the "+"), or guest-locked
    if (_index != tab) setState(() => _index = tab);
    if (!_pager.hasClients) return;
    final current = _pager.page?.round() ?? _pagePosFor(_index);
    if (pos == current) return;
    _navTarget = tab;
    if ((pos - current).abs() > 1) {
      _pager.jumpToPage(pos > current ? pos - 1 : pos + 1);
    }
    _pager
        .animateToPage(
          pos,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        )
        // Release the gate on arrival, or when a swipe interrupts the glide -
        // but only if a newer tap has not already claimed a different target.
        .then((_) {
          if (mounted && _navTarget == tab) _navTarget = null;
        });
  }

  /// A page settled - from a finger swipe, or the tail of a tap-driven glide.
  void _onPageChanged(int pos) {
    if (pos < 0 || pos >= _pageOrder.length) return;
    final tab = _pageOrder[pos];
    // Mid-glide: ignore the page we are only passing through.
    if (_navTarget != null) {
      if (tab != _navTarget) return;
      _navTarget = null;
    }
    if (_index != tab) setState(() => _index = tab);
    // Keep the shared controller in step, so a route pushed from here reads the
    // tab the user actually swiped to. Re-entrant by design: this fires
    // _onTabChanged, which lands on _goToTab and finds nothing left to do.
    if (ShellController.tab.value != tab) ShellController.tab.value = tab;
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
    ShellController.tab.value = _homeTab;
    _goToTab(_homeTab);
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
  /// button, then the voice assistant up top. Target *bounds* are resolved live
  /// via GlobalKey + RenderBox.localToGlobal() on every frame tick, so the
  /// spotlight is sized by the widget itself instead of a hand-tuned radius
  /// that drifts the moment a tile's icon or label changes size.
  List<TourStep> _tourSteps(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);

    Rect resolveBounds(GlobalKey key, String name, {GlobalKey? fallbackKey}) {
      var ctx = key.currentContext;
      if (ctx == null && fallbackKey != null) {
        ctx = fallbackKey.currentContext;
      }
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.attached) {
          return box.localToGlobal(Offset.zero) & box.size;
        }
      }
      // Unresolvable target (tab not built yet): a modest circle dead centre,
      // so the step still reads rather than punching a hole over nothing.
      return Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 68,
        height: 68,
      );
    }

    return [
      TourStep(
        name: 'HomeTab',
        title: l10n.t('home'),
        body: l10n.t('tourHomeBody'),
        target: () => resolveBounds(_homeTabKey, 'HomeTab'),
      ),
      TourStep(
        name: 'VaultTab',
        title: l10n.t('vault'),
        body: l10n.t('tourVaultBody'),
        target: () => resolveBounds(_vaultTabKey, 'VaultTab'),
      ),
      TourStep(
        name: 'QuickAddFAB',
        title: l10n.t('quickAdd'),
        body: l10n.t('tourQuickAddBody'),
        target: () => resolveBounds(_quickAddKey, 'QuickAddFAB'),
      ),
      TourStep(
        name: 'NotificationBell',
        title: l10n.t('alerts'),
        body: l10n.t('tourAlertsBody'),
        target: () => resolveBounds(
          _notificationsKey,
          'NotificationBell',
          fallbackKey: _alertsTabKey,
        ),
      ),
      TourStep(
        name: 'ProfileTab',
        title: l10n.t('profile'),
        body: l10n.t('tourProfileBody'),
        target: () => resolveBounds(_profileTabKey, 'ProfileTab'),
      ),
      TourStep(
        name: 'VoiceAssistant',
        title: l10n.t('voiceAssistant'),
        body: l10n.t('tourVoiceBody'),
        target: () => resolveBounds(_voiceKey, 'VoiceAssistant'),
      ),
    ];
  }

  /// The screen behind bottom-bar slot [tab].
  ///
  /// Only ever called for a slot in [_pageOrder], so the centre "+" (slot 2)
  /// has no page here. Guests reach only Home, so the guest-facing placeholders
  /// the old stack carried for the locked tabs are gone with it - the gate in
  /// [_onTabChanged] is what they actually hit.
  Widget _pageFor(int tab) {
    switch (tab) {
      case 1:
        return WalletScreen(profile: _profile);
      case 3:
        return RemindersScreen(profile: _profile);
      case 4:
        return ProfileScreen(
          profile: _profile,
          themeMode: widget.themeMode,
          onToggleTheme: widget.onToggleTheme,
          onProfileUpdated: (updated) => setState(() => _profile = updated),
        );
      case _homeTab:
      default:
        return HomeScreen(
          profile: _profile,
          themeMode: widget.themeMode,
          onToggleTheme: widget.onToggleTheme,
          voiceTourKey: _voiceKey,
          notificationsTourKey: _notificationsKey,
        );
    }
  }

  void _finishTour() {
    setState(() => _tourActive = false);
    AppSettings.instance.setTourSeen(true);
    if (!GuestMode.active) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          SecurityReminderDialog.showIfEligible(
            context,
            profile: _profile,
            onProfileUpdated: (updated) {
              if (mounted) setState(() => _profile = updated);
            },
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _pageOrder;

    final shell = Scaffold(
      // Let content sit behind the floating nav bar.
      extendBody: true,
      // Keep the bottom nav planted at all times: it lives in
      // `bottomNavigationBar` (so it never scrolls with the page), and this
      // stops the keyboard inset from ever pushing it upward. The nav stays
      // pinned to the bottom edge no matter what the body does.
      resizeToAvoidBottomInset: false,
      // The voice assistant now lives as a small icon in each page's top bar
      // (beside the notification bell), so there's no floating mic here anymore.
      //
      // Swipe left/right to move between destinations: the content follows the
      // finger and snaps to the next tab in bottom-bar order. The app's shared
      // bouncing physics gives it the same soft deceleration as every list in
      // INO, and PageView's own page-snapping rides on top of that.
      body: NotificationListener<ScrollNotification>(
        // depth 0 is the pager itself; anything deeper is a page's own list.
        onNotification: (n) {
          if (n.depth == 0) {
            if (n is ScrollStartNotification) {
              _pagerMoving.value = true;
            } else if (n is ScrollEndNotification) {
              _pagerMoving.value = false;
            }
          }
          return false; // observe only - never swallow the notification
        },
        child: PageView.builder(
          controller: _pager,
          physics: inoScrollPhysics,
          onPageChanged: _onPageChanged,
          itemCount: order.length,
          itemBuilder: (context, pos) {
            final tab = order[pos];
            // Built lazily - a destination costs nothing until it is swiped
            // near - and then kept alive, so going back to it restores its
            // scroll position and loaded data instead of refetching. That is
            // the one thing the IndexedStack this replaced did well, and the
            // one thing a plain PageView would have thrown away.
            return _KeepAlivePage(
              child: ValueListenableBuilder<bool>(
                valueListenable: _pagerMoving,
                // The page is passed through as `child`, so flipping the flag
                // rebuilds the TickerMode and nothing below it.
                child: RepaintBoundary(child: _pageFor(tab)),
                builder: (context, moving, child) => TickerMode(
                  enabled: tab == _index || moving,
                  child: child!,
                ),
              ),
            );
          },
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

/// Holds a destination's state once it has been built.
///
/// A [PageView] disposes pages that leave its cache extent, which for a tab bar
/// is exactly wrong: swiping to Reminders and back would rebuild Home from
/// scratch, losing its scroll position and refetching everything it had already
/// loaded. Keeping each page alive gives the pager the state retention of the
/// IndexedStack it replaced, while still building each one lazily on first
/// arrival.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by the mixin
    return widget.child;
  }
}
