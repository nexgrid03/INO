import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_profile.dart';
import '../../services/voice_greeting_service.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../home/home_screen.dart';
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

class _MainShellState extends State<MainShell> {
  int _index = ShellController.tab.value;

  /// Held in state so a profile edit (from the Profile tab) propagates to every
  /// destination that shows the user's details.
  late UserProfile _profile = widget.profile;

  @override
  void initState() {
    super.initState();
    ShellController.tab.addListener(_onTabChanged);
    // Smart voice greeting — spoken once per launch when the authenticated shell
    // first appears (covers both a fresh login and opening while signed in).
    // Deferred a beat so it doesn't compete with the first-frame work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceGreetingService.instance.greetOnce(userName: _profile.fullName);
    });
  }

  @override
  void dispose() {
    ShellController.tab.removeListener(_onTabChanged);
    super.dispose();
  }

  // Driven by the shared controller so pushed routes can switch tabs too.
  void _onTabChanged() {
    if (mounted && _index != ShellController.tab.value) {
      setState(() => _index = ShellController.tab.value);
    }
  }

  void _select(int i) {
    // The centre "Scan" destination opens the focused Scan & OCR flow rather
    // than switching the IndexedStack to a static page.
    if (i == 2) {
      HapticFeedback.selectionClick();
      launchScanFlow(context);
      return;
    }
    if (i == _index) return;
    HapticFeedback.selectionClick();
    ShellController.tab.value = i;
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

    return Scaffold(
      // Let content (and the nav's blur) sit behind the floating nav bar.
      extendBody: true,
      // Keep the bottom nav planted at all times: it lives in
      // `bottomNavigationBar` (so it never scrolls with the page), and this
      // stops the keyboard inset from ever pushing it upward. The nav stays
      // pinned to the bottom edge no matter what the body does.
      resizeToAvoidBottomInset: false,
      // The voice assistant now lives as a small icon in each page's top bar
      // (beside the notification bell), so there's no floating mic here anymore.
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: InoBottomNav(index: _index, onSelect: _select),
    );
  }
}
