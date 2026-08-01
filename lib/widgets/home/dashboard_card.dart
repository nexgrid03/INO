import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/fade_slide_in.dart';
import '../pressable_scale.dart';

/// The Home hero block, replicating the reference vault layout:
///
///   1. A luminous glass hero card - the bobbing shield mascot on the left,
///      an eyebrow / headline / subtitle column with a gradient CTA on the
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
    this.onDocumentsExpiring,
    this.onEmiDues,
    this.onRemindersToday,
    this.onInsuranceRenewals,
    this.onCta,
    this.onAssets,
    this.onPending,
    this.onProtected,
  });

  final HomeHero hero;

  // Real counts for the four summary tiles - 0 when there's nothing to show.
  final int documentsExpiring;
  final int remindersToday;
  final int insuranceRenewals;
  final int emiDue;
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
  // One slow, perpetual loop drives every ambient motion in the hero - the
  // drifting backdrop and the subtle gradient shift - so the whole surface
  // breathes together at ~12s per cycle.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- 1. Hero card: mascot left, copy + CTA right -------------------
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: palette.cardGradient,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Stack(
            children: [
              // Animated sky-wash backdrop (gradient shift + drifting
              // graphics). Only this layer repaints each frame.
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _ambient,
                    builder: (context, _) {
                      final t = Curves.easeInOut.transform(_ambient.value);
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1 + t * 0.4, -1),
                            end: Alignment(1, 1 - t * 0.4),
                            colors: [
                              AppColors.tealFoam.withValues(
                                  alpha: palette.isDark ? 0.0 : 0.35),
                              AppColors.tealMist.withValues(
                                  alpha: palette.isDark ? 0.06 : 0.55),
                            ],
                          ),
                        ),
                        child: CustomPaint(painter: _OverviewBackdrop(t: t)),
                      );
                    },
                  ),
                ),
              ),

              // Foreground hero row. IntrinsicHeight lets the mascot column
              // stretch to exactly the text column's height, so the
              // illustration is always vertically centred against the copy
              // (no empty corner above it).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The shield mascot, enlarged into the reference's
                      // illustration slot and centred on the card's height.
                      SizedBox(
                        width: 118,
                        child: Center(
                          child: Transform.scale(
                            scale: 2.1,
                            child: const _MascotBadge(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // The copy column is anchored to the card's RIGHT edge:
                      // every line and the CTA share one clean right-aligned
                      // axis, balancing the mascot on the left.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Eyebrow - small caps in the brand teal.
                            const Text(
                              'YOUR VAULT',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your Vault is 100% Protected',
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All your documents are safe and backed up',
                              textAlign: TextAlign.right,
                              maxLines: 2,
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
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // --- 2. Compact summary strip: four tiles in one row ---------------
        _SummaryStrip(
          documentsExpiring: widget.documentsExpiring,
          remindersToday: widget.remindersToday,
          insuranceRenewals: widget.insuranceRenewals,
          emiDue: widget.emiDue,
          onDocumentsExpiring: widget.onDocumentsExpiring ?? widget.onPending,
          onEmiDues: widget.onEmiDues ?? widget.onCta,
          onRemindersToday: widget.onRemindersToday ?? widget.onCta,
          onInsuranceRenewals:
              widget.onInsuranceRenewals ?? widget.onProtected,
        ),
      ],
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
    );
  }
}

/// The header "character": a glassy shield badge that gently bobs, ringed by a
/// soft pulse and two floating sparkle accents.
class _MascotBadge extends StatefulWidget {
  const _MascotBadge();

  @override
  State<_MascotBadge> createState() => _MascotBadgeState();
}

class _MascotBadgeState extends State<_MascotBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value; // 0..1..0
        final bob = math.sin(t * math.pi) * 3; // gentle vertical float
        final ring = 0.9 + t * 0.3; // pulse ring scale
        return SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Soft pulsing halo ring.
              Transform.scale(
                scale: ring,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryGreen
                          .withValues(alpha: 0.30 * (1 - t)),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // Floating sparkle accents.
              Positioned(
                top: 2 - bob,
                right: 4,
                child: _Sparkle(size: 7, opacity: 0.85 * t + 0.15),
              ),
              Positioned(
                bottom: 3 + bob,
                left: 3,
                child: _Sparkle(size: 5, opacity: 0.9 * (1 - t) + 0.1),
              ),
              // The glassy shield badge, bobbing - a brand-gradient chip.
              Transform.translate(
                offset: Offset(0, -bob),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            AppColors.primaryGreen.withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.auto_awesome_rounded,
      size: size + 6,
      color: AppColors.skyBlue.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
  }
}

/// The four summary counts as one compact row - the reference "Reminders"
/// strip alignment: small label on top, big count bottom-left, a pastel icon
/// chip bottom-right. Same counts, same taps as the old 2×2 grid.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.documentsExpiring,
    required this.remindersToday,
    required this.insuranceRenewals,
    required this.emiDue,
    this.onDocumentsExpiring,
    this.onEmiDues,
    this.onRemindersToday,
    this.onInsuranceRenewals,
  });

  final int documentsExpiring;
  final int remindersToday;
  final int insuranceRenewals;
  final int emiDue;
  final VoidCallback? onDocumentsExpiring;
  final VoidCallback? onEmiDues;
  final VoidCallback? onRemindersToday;
  final VoidCallback? onInsuranceRenewals;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _StripTile(
        label: 'Expiring',
        value: '$documentsExpiring',
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFF59E0B),
        onTap: onDocumentsExpiring,
      ),
      _StripTile(
        label: 'EMI Due',
        value: '$emiDue',
        icon: Icons.account_balance_wallet_rounded,
        accent: const Color(0xFF2563EB),
        onTap: onEmiDues,
      ),
      _StripTile(
        label: 'Reminders',
        value: '$remindersToday',
        icon: Icons.alarm_rounded,
        accent: const Color(0xFFF5704A),
        onTap: onRemindersToday,
      ),
      _StripTile(
        label: 'Insurance',
        value: '$insuranceRenewals',
        icon: Icons.shield_rounded,
        accent: const Color(0xFF8B6CEF),
        onTap: onInsuranceRenewals,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: FadeSlideIn(
              delay: Duration(milliseconds: 120 + i * 90),
              offset: 18,
              child: tiles[i],
            ),
          ),
        ],
      ],
    );
  }
}

/// One compact summary tile: label on top, count + icon chip below.
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

    final tile = Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
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

/// Paints the drifting abstract graphics over the hero wash: soft blobs, a
/// gentle wave band and thin geometric ring accents. Everything moves with
/// [t] (0→1→0) so the section feels alive without distracting.
class _OverviewBackdrop extends CustomPainter {
  _OverviewBackdrop({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final drift = (t - 0.5) * 22; // −11 → +11 px slow travel

    // Soft radial blobs - layered translucent sky light.
    void blob(Offset c, double r, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.skyBlue.withValues(alpha: alpha),
            AppColors.skyBlue.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    blob(Offset(size.width * 0.92, -20 + drift), size.width * 0.42, 0.16);
    blob(
      Offset(size.width * 0.08, size.height * 0.72 - drift),
      size.width * 0.38,
      0.12,
    );

    // Thin geometric ring accents, top-right.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.skyBlue.withValues(alpha: 0.30);
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.30 + drift * 0.5),
      30,
      ring,
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.30 + drift * 0.5),
      46,
      ring..color = AppColors.skyBlue.withValues(alpha: 0.16),
    );

    // A gentle wave band across the lower third.
    final wave = Paint()..color = AppColors.skyBlue.withValues(alpha: 0.10);
    final path = Path();
    final baseY = size.height * 0.62;
    const amp = 12.0;
    path.moveTo(0, baseY);
    for (double x = 0; x <= size.width; x += 1) {
      final y =
          baseY +
          math.sin((x / size.width * 2 * math.pi) + t * math.pi * 2) * amp;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, wave);

    // Faint dotted accent cluster, mid-left.
    final dot = Paint()..color = AppColors.skyBlue.withValues(alpha: 0.25);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        canvas.drawCircle(
          Offset(
            size.width * 0.14 + c * 9,
            size.height * 0.22 + r * 9 + drift * 0.3,
          ),
          1.3,
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OverviewBackdrop old) => old.t != t;
}
