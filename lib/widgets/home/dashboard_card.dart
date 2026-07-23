import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Today's Overview — Main Hero Section of the INO Home Screen.
///
/// Features a prominent brand-gradient container (#0CB7A3 → #3EC7FF) housing:
/// 1. Header: "Today's Overview" & "Your important summary for today" + Security Shield badge.
/// 2. 4 Summary Cards in a 2x2 grid (Documents Expiring, EMI Due Tomorrow, Reminders Today, Insurance Renewals).
/// 3. Bottom Information Bar: "Last Backup: Today, 08:30 AM" & "View Backup →" button.
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.hero,
    this.onDocumentsExpiring,
    this.onEmiDues,
    this.onRemindersToday,
    this.onInsuranceRenewals,
    this.onBackup,
    this.onCta,
    this.onAssets,
    this.onPending,
    this.onProtected,
  });

  final HomeHero hero;
  final VoidCallback? onDocumentsExpiring;
  final VoidCallback? onEmiDues;
  final VoidCallback? onRemindersToday;
  final VoidCallback? onInsuranceRenewals;
  final VoidCallback? onBackup;
  final VoidCallback? onCta;
  final VoidCallback? onAssets;
  final VoidCallback? onPending;
  final VoidCallback? onProtected;

  @override
  Widget build(BuildContext context) {
    final expiringCount = hero.pendingTasks > 0 ? hero.pendingTasks : 2;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with title, subtitle & protection badge.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's Overview",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Your important summary for today",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Security Illustration / Protection Badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          // 2. Grid of 4 Summary Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCardTile(
                        title: 'Documents Expiring',
                        value: '$expiringCount',
                        icon: Icons.warning_amber_rounded,
                        accentColor: AppColors.warning,
                        onTap: onDocumentsExpiring ?? onPending,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCardTile(
                        title: 'EMI Due Tomorrow',
                        value: '1',
                        icon: Icons.account_balance_wallet_rounded,
                        accentColor: const Color(0xFF3EC7FF),
                        onTap: onEmiDues ?? onCta,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12, height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCardTile(
                        title: 'Reminders Today',
                        value: '3',
                        icon: Icons.alarm_rounded,
                        accentColor: AppColors.primaryGreen,
                        onTap: onRemindersToday ?? onCta,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCardTile(
                        title: 'Insurance Renewals',
                        value: '1',
                        icon: Icons.security_rounded,
                        accentColor: const Color(0xFF8B6CEF),
                        onTap: onInsuranceRenewals ?? onProtected,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 3. Bottom Information Bar: Last Backup & View Backup CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_done_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Last Backup: ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const TextSpan(
                          text: 'Today, 08:30 AM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PressableScale(
                  pressedScale: 0.95,
                  child: GestureDetector(
                    onTap: onBackup ?? onProtected ?? onCta,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View Backup',
                            style: TextStyle(
                              color: AppColors.darkGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: AppColors.darkGreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCardTile extends StatelessWidget {
  const _SummaryCardTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSmall = context.isMobileSmall;
    final tile = Container(
      padding: EdgeInsets.all(isSmall ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: isSmall ? 18.rsp : 22.rsp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: EdgeInsets.all(isSmall ? 4 : 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: isSmall ? 14 : 16,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: isSmall ? 10.5.rsp : 11.5.rsp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );
  }
}
