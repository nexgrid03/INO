import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 1 — Wallet Hub header (launcher style).
///
/// Avatar + search/notification controls, the "My Wallets" title, and a single
/// lightweight summary line ("8 Wallets • 128 Records"). Kept deliberately
/// compact so the wallet grid sits high on the screen.
class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.fullName,
    required this.walletCount,
    required this.recordCount,
    required this.onSearch,
    required this.onNotifications,
    this.notificationCount = 0,
  });

  final String fullName;
  final int walletCount;
  final int recordCount;
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
        const SizedBox(height: 14),
        Text(
          'My Wallets',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        // Lightweight quick summary.
        Row(
          children: [
            const Icon(Icons.verified_user_rounded,
                size: 14, color: AppColors.primaryGreen),
            const SizedBox(width: 6),
            Text(
              '$walletCount Wallets  •  $recordCount Records',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ],
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
