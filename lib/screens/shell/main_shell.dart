import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_profile.dart';
import '../../services/voice_greeting_service.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../expenses/add_expense_screen.dart';
import '../home/home_screen.dart';
import '../notes/notes_screen.dart';
import '../profile/profile_screen.dart';
import '../reminders/reminders_screen.dart';
import '../scan/scan_flow_screen.dart';
import '../wallet/wallet_screen.dart';
import 'placeholder_tab.dart';
import 'shell_controller.dart';

/// The app shell: an [IndexedStack] of the five primary destinations behind a
/// custom bottom navigation bar, with the voice mic floating above.
///
/// Bottom nav: Home · Wallet · Scan · Reminders · Profile. The nav bar is
/// always fixed to the bottom and stays visible while content scrolls
/// beneath it (`extendBody` lets the blur show the page through). The single
/// floating affordance is the hands-free voice mic at the bottom-right —
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
    // Smart voice greeting — spoken once per session when the authenticated
    // shell first appears (covers both a fresh login and opening while signed
    // in). Deferred a beat so it doesn't compete with the first-frame work.
    // greetOnce() is self-guarding: rebuilds, navigation back, or a second
    // shell mount can never replay it (see VoiceGreetingService).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGreetingService.instance.greetOnce(userName: _profile.fullName);
    });
  }

  @override
  void dispose() {
    ShellController.tab.removeListener(_onTabChanged);
    _pageAnim.dispose();
    super.dispose();
  }

  // Driven by the shared controller so pushed routes can switch tabs too.
  void _onTabChanged() {
    final next = ShellController.tab.value;
    if (mounted && _index != next) {
      setState(() {
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

  /// The centre "+" button's quick-action menu resolves to one of three
  /// destinations. Scanning still lives here; OCR / camera are save options
  /// inside the Scan flow, not top-level menu items.
  void _onScanAction(ScanAction action) {
    switch (action) {
      case ScanAction.expenses:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
        );
      case ScanAction.scan:
        launchScanFlow(context);
      case ScanAction.notes:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotesScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        profile: _profile,
        themeMode: widget.themeMode,
        onToggleTheme: widget.onToggleTheme,
      ),
      WalletScreen(profile: _profile),
      const PlaceholderTab(
        title: 'Scan',
        icon: Icons.document_scanner_rounded,
        message: 'Scan documents straight into your secure vault.',
      ),
      RemindersScreen(profile: _profile),
      ProfileScreen(
        profile: _profile,
        themeMode: widget.themeMode,
        onToggleTheme: widget.onToggleTheme,
        onProfileUpdated: (updated) => setState(() => _profile = updated),
      ),
    ];

    return PopScope(
      // We handle the back gesture ourselves so it retraces tabs instead of
      // closing the app; only _handleBack() exits (once tab history is empty).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        // Let content (and the nav's blur) sit behind the floating nav bar.
        extendBody: true,
      // Keep the bottom nav planted at all times: it lives in
      // `bottomNavigationBar` (so it never scrolls with the page), and this
      // stops the keyboard inset from ever pushing it upward. The nav stays
      // pinned to the bottom edge no matter what the body does.
      resizeToAvoidBottomInset: false,
      // The voice assistant now lives as a small icon in each page's top bar
      // (beside the notification bell), so there's no floating mic here anymore.
      body: AnimatedBuilder(
        animation: _pageAnim,
        builder: (context, child) {
          final v = Curves.easeOutCubic.transform(_pageAnim.value);
          return Opacity(
            // Ramp from a soft 0.35 (never a harsh blank) up to fully opaque.
            opacity: 0.35 + 0.65 * v,
            child: FractionalTranslation(
              translation: Offset(0.06 * (1 - v), 0), // enters from the right
              child: child,
            ),
          );
        },
        child: IndexedStack(index: _index, children: pages),
      ),
        bottomNavigationBar: InoBottomNav(
          index: _index,
          onSelect: _select,
          onScanAction: _onScanAction,
        ),
      ),
    );
  }
}
