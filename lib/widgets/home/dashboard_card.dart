import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/sparkline.dart';
import '../pressable_scale.dart';

/// Section 2 — the Dashboard hero card (light, CRED-style).
///
/// Net worth as the single focal point on a clean white surface with a faint
/// mint wash: monthly growth (% + amount), a green trend graph, a "View
/// details" CTA, then a metric strip (Assets · Pending · Protected) with
/// soft-tinted icon chips. Those are the ONLY counts on Home — every other
/// module's numbers live on its own page.
class DashboardCard extends StatelessWidget {
  const DashboardCard({super.key, required this.hero, this.onCta});

  final HomeHero hero;
  final VoidCallback? onCta;

  static const _assets = AppColors.primaryGreen;
  static const _pending = AppColors.warning;
  static const _protected = Color(0xFF8B6CEF);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // White surface with a faint mint wash at the top-left (theme-aware).
    final tint = Color.alphaBlend(
        AppColors.primaryGreen.withValues(alpha: 0.06), palette.surface);

    return PressableScale(
      pressedScale: 0.99,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint, palette.surface],
            stops: const [0.0, 0.6],
          ),
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: palette.border),
          boxShadow: palette.cardShadow,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.internal),
              child: _NetWorth(hero: hero, onCta: onCta),
            ),
            Divider(height: 1, thickness: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: 14),
              child: Row(
                children: [
                  _Stat(
                      icon: Icons.account_balance_wallet_rounded,
                      color: _assets,
                      value: '${hero.assets}',
                      label: 'Assets'),
                  _Stat(
                      icon: Icons.assignment_rounded,
                      color: _pending,
                      value: '${hero.pendingTasks}',
                      label: 'Pending'),
                  _Stat(
                      icon: Icons.verified_user_rounded,
                      color: _protected,
                      value: '${hero.protectedItems}',
                      label: 'Protected'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _NetWorth extends StatelessWidget {
  const _NetWorth({required this.hero, this.onCta});

  final HomeHero hero;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = hero.isUp;
    final growthColor = up ? AppColors.positive : AppColors.negative;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Net Worth',
                  style: AppText.caption.copyWith(color: palette.textSecondary)),
              const SizedBox(height: AppSpacing.xxs),
              Text(hero.netWorth,
                  style: AppText.bigNumber.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                      up
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                      color: growthColor),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text:
                              '${up ? '+' : ''}${hero.growthPercent.toStringAsFixed(1)}% (${hero.growthAmount}) ',
                          style: AppText.caption.copyWith(
                              color: growthColor, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: 'this month',
                          style: AppText.caption
                              .copyWith(color: palette.textFaint),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _CtaButton(onTap: onCta),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Right: growth pill above a green trend graph.
        SizedBox(
          width: 116,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GrowthPill(percent: hero.growthPercent),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 64,
                child: Sparkline(
                  values: hero.trend,
                  color: AppColors.primaryGreen,
                  strokeWidth: 2.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GrowthPill extends StatelessWidget {
  const _GrowthPill({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = up ? AppColors.positive : AppColors.negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 13, color: color),
          const SizedBox(width: 2),
          Text('${percent.abs().toStringAsFixed(1)}%',
              style: AppText.label.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: AppColors.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('View details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                          color: AppColors.primaryGreen, fontSize: 13)),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: AppColors.primaryGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One metric in the hero strip: soft-tinted icon chip + label/value.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppText.title
                .copyWith(color: palette.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style:
                AppText.label.copyWith(color: palette.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
