import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 1 — Wallet Hub header.
///
/// Avatar + search/notification controls, then the "My Wallets" title, a warm
/// subtitle, and a green "items secured" badge. Mirrors the home header's
/// styling so the two tabs feel like one product.
class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.fullName,
    required this.itemsSecured,
    required this.onSearch,
    required this.onNotifications,
    this.notificationCount = 0,
  });

  final String fullName;
  final int itemsSecured;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final int notificationCount;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const Spacer(),
            _HeaderIcon(
              icon: Icons.search_rounded,
              tooltip: 'Search wallets',
              onTap: onSearch,
            ),
            const SizedBox(width: 8),
            _HeaderIcon(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              onTap: onNotifications,
              badge: notificationCount,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'My Wallets',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Securely manage every important part of your life.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryGreen.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user_rounded,
                  size: 15, color: AppColors.primaryGreen),
              const SizedBox(width: 7),
              Text(
                '$itemsSecured Items Secured',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 21, color: palette.textPrimary),
                  if (badge > 0)
                    Positioned(
                      top: 9,
                      right: 9,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.critical,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.surface, width: 1.5),
                        ),
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
