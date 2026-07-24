import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One bottom-navigation destination.
class NavItem {
  const NavItem(this.label, this.active, this.inactive);
  final String label;
  final IconData active;
  final IconData inactive;
}

/// The INO floating, glassmorphic bottom navigation bar.
///
/// Shared between [MainShell] and pushed routes (e.g. the Wallet Detail screen)
/// so navigation looks and behaves identically everywhere. A detached rounded
/// pill container with a blurred translucent fill, hairline teal border and a
/// soft ambient glow.
///
/// The bar is **icons only** — no labels. Every tab is an equal-width slot with
/// a fixed 26px glyph that never resizes; only a soft rounded highlight and the
/// icon colour animate (~300ms) to mark the active tab, so switching feels
/// smooth while the icons stay perfectly steady.
class InoBottomNav extends StatelessWidget {
  const InoBottomNav({super.key, required this.index, required this.onSelect});

  final int index;
  final void Function(int) onSelect;

  /// The five primary destinations — single source of truth for every surface.
  static const List<NavItem> tabs = [
    NavItem('Home', Icons.home_rounded, Icons.home_outlined),
    NavItem(
      'Vault',
      Icons.account_balance_wallet_rounded,
      Icons.account_balance_wallet_outlined,
    ),
    NavItem('Add', Icons.add_circle_rounded, Icons.add_circle_outline_rounded),
    NavItem(
      'Alerts',
      Icons.notifications_rounded,
      Icons.notifications_none_rounded,
    ),
    NavItem('Profile', Icons.person_rounded, Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 60,
              // A slim inner margin lets the five equal slots spread evenly
              // across the bar rather than bunching in the centre with big
              // empty ends.
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                // Frosted glass: a top-lit translucent gradient riding over the
                // live backdrop blur, so the bar reads as a pane of glass rather
                // than a flat fill.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: palette.isDark
                      ? [
                          palette.bgElevated.withValues(alpha: 0.82),
                          palette.bgElevated.withValues(alpha: 0.60),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.92),
                          Colors.white.withValues(alpha: 0.68),
                        ],
                ),
                borderRadius: BorderRadius.circular(24),
                // Brand-teal glass edge (#30ACB3), matching the active icons —
                // kept fine and soft so it reads as a hairline, not a frame.
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.4),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(
                      alpha: palette.isDark ? 0.18 : 0.16,
                    ),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: palette.shadow.withValues(
                      alpha:
                          (palette.isDark ? 0.5 : 0.04) *
                          palette.shadowStrength,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
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

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Icons only — a constant 26px glyph in every state. The active tab gains a
    // soft teal highlight pill behind the icon and switches to the primary
    // colour; nothing scales, so the icon never grows or shrinks.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          width: 46,
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryGreen.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(
            selected ? item.active : item.inactive,
            size: 26,
            color: selected ? AppColors.primaryGreen : palette.textFaint,
          ),
        ),
      ),
    );
  }
}
