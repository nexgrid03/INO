import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../dashboard/fade_slide_in.dart';
import '../pressable_scale.dart';
import 'launcher_glass_icon_tile.dart';

/// The Home hero block, replicating the reference vault layout:
///
///   1. A luminous glass hero card - static lock badge on the left, an
///      eyebrow / headline / subtitle column with a gradient CTA on the
///      right ("Your Vault is … / View Documents →").
///   2. A strip of four compact summary tiles beneath it (label on top, big
///      count + icon chip below) - the reference "Reminders" tile alignment.
///
/// All counts and tap targets are the same as before; only the arrangement
/// changed.
class DashboardCard extends StatefulWidget {
  const DashboardCard({
    super.key,
    required this.hero,
    this.documentsExpiring = 0,
    this.remindersToday = 0,
    this.insuranceRenewals = 0,
    this.emiDue = 0,
    this.pendingCount = 0,
    this.showSummaryStrip = true,
    this.replaceRemindersWithPending = false,
    this.onDocumentsExpiring,
    this.onEmiDues,
    this.onRemindersToday,
    this.onInsuranceRenewals,
    this.onPending,
    this.onCta,
    this.onAssets,
    this.onProtected,
  });

  final HomeHero hero;

  // Real counts for the four summary tiles - 0 when there's nothing to show.
  final int documentsExpiring;
  final int remindersToday;
  final int insuranceRenewals;
  final int emiDue;
  final int pendingCount;

  /// When false, only the vault hero card is shown.
  final bool showSummaryStrip;

  /// Launcher theme: third tile is Pending (not Reminders).
  final bool replaceRemindersWithPending;
  final VoidCallback? onDocumentsExpiring;
  final VoidCallback? onEmiDues;
  final VoidCallback? onRemindersToday;
  final VoidCallback? onInsuranceRenewals;
  final VoidCallback? onCta;
  final VoidCallback? onAssets;
  final VoidCallback? onPending;
  final VoidCallback? onProtected;

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard>
    with SingleTickerProviderStateMixin {
  // Created in [initState] (never lazily) so [dispose] never looks up
  // TickerMode on a deactivated element when the light/dark hero path differs.
  AnimationController? _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ambient?.dispose();
    _ambient = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHero(palette),

        if (widget.showSummaryStrip) ...[
          const SizedBox(height: 12),
          HomeSummaryStrip(
            documentsExpiring: widget.documentsExpiring,
            remindersToday: widget.remindersToday,
            insuranceRenewals: widget.insuranceRenewals,
            emiDue: widget.emiDue,
            pendingCount: widget.pendingCount,
            replaceRemindersWithPending: widget.replaceRemindersWithPending,
            enlargedIcons: widget.replaceRemindersWithPending,
            onDocumentsExpiring: widget.onDocumentsExpiring ?? widget.onPending,
            onEmiDues: widget.onEmiDues ?? widget.onCta,
            onRemindersToday: widget.onRemindersToday ?? widget.onCta,
            onInsuranceRenewals:
                widget.onInsuranceRenewals ?? widget.onProtected,
            onPending: widget.onPending,
          ),
        ],
      ],
    );
  }

  /// Shared vault hero (dark layout) for both brightnesses — light uses
  /// warmer foam washes and brand teal eyebrow instead of skyBlue.
  Widget _buildHero(AppPalette palette) {
    final dark = palette.isDark;
    final eyebrow = AppColors.primaryGreen;
    final washCore = dark
        ? AppColors.primaryGreen.withValues(alpha: 0.12)
        : AppColors.secondaryGreen.withValues(alpha: 0.28);
    final washMid = dark
        ? AppColors.primaryGreen.withValues(alpha: 0.05)
        : AppColors.skyBlue.withValues(alpha: 0.12);

    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.large),
      // Opaque frost — BackdropFilter on the hero + tile grid tanks Flutter web.
      enableBlur: false,
      frost: dark ? 1.15 : 0.78,
      shadow: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: palette.cardGradient),
            ),
          ),
          // Soft brand wash behind the shield.
          Positioned(
            left: -24,
            top: -36,
            bottom: -36,
            width: 190,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    washCore,
                    washMid,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // Gentle ambient shift (light only — keeps dark cards calmer).
          if (!dark && _ambient != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ambient!,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_ambient!.value);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 + t * 0.3, -1),
                          end: Alignment(1, 1 - t * 0.3),
                          colors: [
                            AppColors.tealFoam.withValues(alpha: 0.20),
                            AppColors.tealMist.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Shrink mascot on narrow phones so headline/CTA stay usable.
                final mascotW =
                    (constraints.maxWidth * 0.34).clamp(88.0, 124.0);
                final titleSize =
                    constraints.maxWidth < 280 ? 18.0 : 22.0;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: mascotW,
                        child: Center(
                          child: Transform.scale(
                            scale: mascotW / 124 * 2.1,
                            child: const _MascotBadge(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'YOUR VAULT',
                              style: TextStyle(
                                color: eyebrow,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your Vault is 100% Protected',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: titleSize,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All your documents are safe and backed up',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _HeroCta(onTap: widget.onCta),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero's gradient pill CTA - "View Documents →".
class _HeroCta extends StatelessWidget {
  const _HeroCta({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Documents',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Static lock badge for the hero header (no float / pulse).
class _MascotBadge extends StatelessWidget {
  const _MascotBadge();

  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.of(context).isDark;
    return SizedBox(
      width: 54,
      height: 54,
      child: Center(
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.brandGradient,
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.35 : 0.55),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.lock_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// The four summary counts as one compact row (Expiring · EMI Due ·
/// Reminders/Pending · Insurance). Used under the hero on Classic, or as a
/// lower section on Launcher.
class HomeSummaryStrip extends StatelessWidget {
  const HomeSummaryStrip({
    super.key,
    required this.documentsExpiring,
    required this.remindersToday,
    required this.insuranceRenewals,
    required this.emiDue,
    this.pendingCount = 0,
    this.replaceRemindersWithPending = false,
    this.enlargedIcons = false,
    this.onDocumentsExpiring,
    this.onEmiDues,
    this.onRemindersToday,
    this.onInsuranceRenewals,
    this.onPending,
  });

  final int documentsExpiring;
  final int remindersToday;
  final int insuranceRenewals;
  final int emiDue;
  final int pendingCount;
  final bool replaceRemindersWithPending;
  final bool enlargedIcons;
  final VoidCallback? onDocumentsExpiring;
  final VoidCallback? onEmiDues;
  final VoidCallback? onRemindersToday;
  final VoidCallback? onInsuranceRenewals;
  final VoidCallback? onPending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final third = replaceRemindersWithPending
        ? (
            label: l10n.t('pending'),
            value: pendingCount,
            icon: Icons.pending_actions_rounded,
            accent: AppColors.accentCoral,
            onTap: onPending ?? onRemindersToday,
          )
        : (
            label: l10n.t('reminders'),
            value: remindersToday,
            icon: Icons.alarm_rounded,
            accent: AppColors.accentCoral,
            onTap: onRemindersToday,
          );

    final tiles = <({
      String label,
      int value,
      IconData icon,
      Color accent,
      VoidCallback? onTap,
    })>[
      (
        label: l10n.t('expiring'),
        value: documentsExpiring,
        icon: Icons.warning_amber_rounded,
        accent: AppColors.warning,
        onTap: onDocumentsExpiring,
      ),
      (
        label: l10n.t('emiDue'),
        value: emiDue,
        icon: Icons.account_balance_wallet_rounded,
        accent: AppColors.accentBlue,
        onTap: onEmiDues,
      ),
      third,
      (
        label: l10n.t('insurance'),
        value: insuranceRenewals,
        icon: Icons.shield_rounded,
        accent: AppColors.vaultIdentity,
        onTap: onInsuranceRenewals,
      ),
    ];

    if (enlargedIcons) {
      // Launcher: same glass as My Vaults — no FadeSlideIn (web lag / blank).
      // Narrow phones: 2×2 so square tiles don't crush labels.
      final narrow = MediaQuery.sizeOf(context).width < 360;
      Widget tile(int i) => LauncherGlassIconTile(
            label: tiles[i].label,
            count: tiles[i].value,
            icon: tiles[i].icon,
            accent: tiles[i].accent,
            onTap: tiles[i].onTap ?? () {},
          );
      if (narrow) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: tile(0)),
                const SizedBox(width: 10),
                Expanded(child: tile(1)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: tile(2)),
                const SizedBox(width: 10),
                Expanded(child: tile(3)),
              ],
            ),
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tile(i)),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: FadeSlideIn(
              delay: Duration(milliseconds: 120 + i * 90),
              offset: 18,
              child: _StripTile(
                label: tiles[i].label,
                value: '${tiles[i].value}',
                icon: tiles[i].icon,
                accent: tiles[i].accent,
                onTap: tiles[i].onTap,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Classic compact summary tile: label + count + tint chip inside glass.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final tile = LiquidGlass(
      borderRadius: BorderRadius.circular(16),
      blur: 18,
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent, size: 15),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return PressableScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );
  }
}
