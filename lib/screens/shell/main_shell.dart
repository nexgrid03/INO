import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/dashboard_models.dart';
import '../../models/user_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/pressable_scale.dart';
import '../home/home_screen.dart';
import 'placeholder_tab.dart';

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
  int _index = 0;

  static const _tabs = [
    _NavItem('Home', Icons.home_rounded, Icons.home_outlined),
    _NavItem('Wallet', Icons.account_balance_wallet_rounded,
        Icons.account_balance_wallet_outlined),
    _NavItem('Scan', Icons.document_scanner_rounded,
        Icons.document_scanner_outlined),
    _NavItem('Reminders', Icons.notifications_rounded,
        Icons.notifications_none_rounded),
    _NavItem('Profile', Icons.person_rounded, Icons.person_outline_rounded),
  ];

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
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
      const PlaceholderTab(
        title: 'Wallet',
        icon: Icons.account_balance_wallet_rounded,
        message: 'Your unified wallet ecosystem lives here.',
      ),
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
                  actions: _fabActions,
                  onAction: _onFabAction,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _InoBottomNav(
        tabs: _tabs,
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

class _NavItem {
  const _NavItem(this.label, this.active, this.inactive);
  final String label;
  final IconData active;
  final IconData inactive;
}

class _InoBottomNav extends StatelessWidget {
  const _InoBottomNav({
    required this.tabs,
    required this.index,
    required this.onSelect,
  });

  final List<_NavItem> tabs;
  final int index;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Floating, glassmorphic bar (Apple Wallet / iOS feel): detached from the
    // edges, blurred translucent fill, hairline glass border + ambient glow.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: palette.bgElevated
                    .withValues(alpha: palette.isDark ? 0.72 : 0.88),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(
                        alpha: (palette.isDark ? 0.5 : 0.10) *
                            palette.shadowStrength),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: palette.ambient
                        .withValues(alpha: palette.isDark ? 0.08 : 0.06),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _NavButton(
                        item: tabs[i],
                        selected: i == index,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = selected ? AppColors.primaryGreen : palette.textFaint;
    return PressableScale(
      pressedScale: 0.9,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  // Green active state with a soft light-blue glow.
                  gradient: selected
                      ? LinearGradient(
                          colors: [
                            AppColors.primaryGreen.withValues(alpha: 0.20),
                            AppColors.lightBlue.withValues(alpha: 0.18),
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.lightBlue.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  selected ? item.active : item.inactive,
                  size: 23,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
