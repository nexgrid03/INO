import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

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
/// so navigation looks and behaves identically everywhere. Detached from the
/// edges, blurred translucent fill, hairline glass border + ambient glow; the
/// active tab is a green pill with a soft light-blue glow.
class InoBottomNav extends StatelessWidget {
  const InoBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final void Function(int) onSelect;

  /// The five primary destinations — single source of truth for every surface.
  static const List<NavItem> tabs = [
    NavItem('Home', Icons.home_rounded, Icons.home_outlined),
    NavItem('Wallet', Icons.account_balance_wallet_rounded,
        Icons.account_balance_wallet_outlined),
    NavItem('Scan', Icons.document_scanner_rounded,
        Icons.document_scanner_outlined),
    NavItem('Reminders', Icons.notifications_rounded,
        Icons.notifications_none_rounded),
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

  final NavItem item;
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
