import 'package:flutter/material.dart';

import '../../models/metal_rates.dart';
import '../../providers/metal_rates_provider.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';

/// The LIVE Gold & Silver rates card.
///
/// Self-contained: it drives itself from the app-wide [MetalRatesProvider]
/// singleton (starting the 15-min auto-refresh + background refresh on first
/// mount) and rebuilds via [ListenableBuilder]. Handles every state — loading,
/// loaded, offline (last-known values) and error — and offers a manual refresh.
class LiveMetalRatesCard extends StatefulWidget {
  const LiveMetalRatesCard({super.key});

  @override
  State<LiveMetalRatesCard> createState() => _LiveMetalRatesCardState();
}

class _LiveMetalRatesCardState extends State<LiveMetalRatesCard>
    with SingleTickerProviderStateMixin {
  final MetalRatesProvider _provider = MetalRatesProvider.instance;

  // Gentle pulse for the "LIVE" dot.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    // Idempotent — safe to call on every mount.
    _provider.ensureStarted();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        final p = _provider;
        return InoCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, p),
              const SizedBox(height: AppSpacing.md),
              _body(context, p),
            ],
          ),
        );
      },
    );
  }

  // ---- Header: LIVE/OFFLINE badge · title · refresh ------------------------

  Widget _header(BuildContext context, MetalRatesProvider p) {
    final palette = AppPalette.of(context);
    final offline = p.isOffline;
    return Row(
      children: [
        offline ? _offlineBadge() : _liveBadge(),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Precious Metals',
            style: AppText.subtitle.copyWith(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _RefreshButton(
          spinning: p.isRefreshing,
          onTap: () => p.refresh(force: true),
        ),
      ],
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.primaryGreen,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: AppText.label.copyWith(
              color: AppColors.primaryGreen,
              fontSize: 10.5,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 12,
            color: AppColors.warning,
          ),
          const SizedBox(width: 5),
          Text(
            'OFFLINE',
            style: AppText.label.copyWith(
              color: AppColors.warning,
              fontSize: 10.5,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Body: state machine -------------------------------------------------

  Widget _body(BuildContext context, MetalRatesProvider p) {
    // First load, nothing cached yet.
    if (!p.hasData && p.status == MetalRatesStatus.loading) {
      return _loading(context);
    }
    // Hard error with no data to fall back to.
    if (!p.hasData && p.status == MetalRatesStatus.error) {
      return _errorState(context, p);
    }

    final rates = p.rates;
    if (rates == null) return _loading(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetalTile(
                name: 'Gold',
                subtitle: '24K',
                icon: Icons.circle,
                color: AppColors.gold,
                priceText: _inr(rates.goldPerGram),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetalTile(
                name: 'Silver',
                subtitle: 'Fine',
                icon: Icons.circle,
                color: AppColors.silver,
                priceText: _inr(rates.silverPerGram),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _footer(context, p, rates),
      ],
    );
  }

  Widget _footer(BuildContext context, MetalRatesProvider p, MetalRates rates) {
    final palette = AppPalette.of(context);
    final updated = p.lastUpdated;
    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: 13,
          color: palette.textFaint,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            updated == null
                ? 'Updating…'
                : 'Last updated ${_fmtTime(updated)}'
                      '${p.isOffline ? ' · showing last known' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _loading(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(child: _ShimmerTile(pulse: _pulse)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _ShimmerTile(pulse: _pulse)),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.primaryGreen,
            backgroundColor: palette.surfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _errorState(BuildContext context, MetalRatesProvider p) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 20,
          color: AppColors.critical,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            p.error ?? 'Could not load rates',
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PressableScale(
          pressedScale: 0.94,
          child: GestureDetector(
            onTap: () => p.refresh(force: true),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Text(
                'Retry',
                style: AppText.label.copyWith(
                  color: AppColors.primaryGreen,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Formatting ----------------------------------------------------------

  /// ₹ with 2 decimals and Indian digit grouping, e.g. 7032.5 → "₹7,032.50".
  static String _inr(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final whole = fixed.substring(0, dot);
    final frac = fixed.substring(dot + 1);
    return '₹${_indianGroup(whole)}.$frac';
  }

  static String _indianGroup(String s) {
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var head = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (head.length > 2) {
      groups.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) groups.insert(0, head);
    return '${groups.join(',')},$last3';
  }

  /// 24-hour → "11:42 AM".
  static String _fmtTime(DateTime dt) {
    final h24 = dt.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = h24 < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

class _MetalTile extends StatelessWidget {
  const _MetalTile({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.priceText,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String priceText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 11, color: color),
              ),
              const SizedBox(width: 7),
              Text(
                name,
                style: AppText.subtitle.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                subtitle,
                style: AppText.label.copyWith(
                  color: palette.textFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              priceText,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 20,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'per gram',
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.spinning, required this.onTap});

  final bool spinning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.88,
      child: Material(
        color: palette.surfaceVariant,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: spinning ? null : onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: spinning
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primaryGreen,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    size: 19,
                    color: AppColors.primaryGreen,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A softly pulsing placeholder tile shown during the first load.
class _ShimmerTile extends StatelessWidget {
  const _ShimmerTile({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(pulse),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: palette.border),
        ),
      ),
    );
  }
}
