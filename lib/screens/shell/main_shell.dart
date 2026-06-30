import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/dashboard_models.dart';
import '../../models/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../home/home_screen.dart';
import '../wallet/wallet_screen.dart';
import 'placeholder_tab.dart';
import 'shell_controller.dart';

/// The app shell: an [IndexedStack] of the five primary destinations behind a
/// custom bottom navigation bar, with the expandable "Add" FAB floating above.
///
/// Bottom nav: Home · Wallet · Scan · Reminders · Profile. The tabs are kept
/// deliberately flat and predictable; emphasis comes from the gradient FAB,
/// not a competing raised centre button.
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

  @override
  void initState() {
    super.initState();
    ShellController.tab.addListener(_onTabChanged);
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
    if (i == _index) return;
    HapticFeedback.selectionClick();
    ShellController.tab.value = i;
  }

  void _onFabAction(QuickAction action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${action.label} — coming soon'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        profile: widget.profile,
        themeMode: widget.themeMode,
        onToggleTheme: widget.onToggleTheme,
      ),
      WalletScreen(profile: widget.profile),
      const PlaceholderTab(
        title: 'Scan',
        icon: Icons.document_scanner_rounded,
        message: 'Scan documents straight into your secure vault.',
      ),
      const PlaceholderTab(
        title: 'Reminders',
        icon: Icons.notifications_rounded,
        message: 'Renewals, premiums and family events in one feed.',
      ),
      PlaceholderTab(
        title: 'Profile',
        icon: Icons.person_rounded,
        message: 'Signed in as ${widget.profile.email}.',
        showSignOut: true,
      ),
    ];

    // FAB only on Home & Wallet, where "add" actions make sense.
    final showFab = _index == 0 || _index == 1;

    return Scaffold(
      // Let content (and the nav's blur) sit behind the floating nav bar.
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          if (showFab)
            Positioned.fill(
              child: Padding(
                // Clear the floating nav bar at the bottom.
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                child: ExpandableFab(
                  // Wallet tab gets vault-centric add actions.
                  actions: _index == 1 ? _walletFabActions : _fabActions,
                  onAction: _onFabAction,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: InoBottomNav(
        index: _index,
        onSelect: _select,
      ),
    );
  }
}

// FAB actions mirror the repository's fabActions; duplicated here as a const so
// the shell needn't await a load just to show the menu.
const List<QuickAction> _fabActions = [
  QuickAction(
      label: 'Add Document',
      icon: Icons.note_add_rounded,
      color: AppColors.lightBlue),
  QuickAction(
      label: 'Add Reminder',
      icon: Icons.alarm_add_rounded,
      color: Color(0xFFF5704A)),
  QuickAction(
      label: 'Add Investment',
      icon: Icons.savings_rounded,
      color: Color(0xFF2BB6A3)),
  QuickAction(
      label: 'Add Property',
      icon: Icons.add_home_rounded,
      color: Color(0xFF8B6CEF)),
  QuickAction(
      label: 'Add Insurance',
      icon: Icons.add_moderator_rounded,
      color: AppColors.warning),
  QuickAction(
      label: 'Add Health Record',
      icon: Icons.medical_services_rounded,
      color: Color(0xFFEC6A8C)),
];

// Wallet Hub FAB actions (vault-centric).
const List<QuickAction> _walletFabActions = [
  QuickAction(
      label: 'Add Document',
      icon: Icons.note_add_rounded,
      color: AppColors.lightBlue),
  QuickAction(
      label: 'Add Property',
      icon: Icons.add_home_rounded,
      color: Color(0xFF38BDF8)),
  QuickAction(
      label: 'Add Insurance',
      icon: Icons.add_moderator_rounded,
      color: AppColors.secondaryGreen),
  QuickAction(
      label: 'Add Investment',
      icon: Icons.savings_rounded,
      color: Color(0xFF34D399)),
  QuickAction(
      label: 'Add Password',
      icon: Icons.password_rounded,
      color: Color(0xFF0EA5A5)),
  QuickAction(
      label: 'Scan',
      icon: Icons.document_scanner_rounded,
      color: AppColors.primaryGreen),
];
