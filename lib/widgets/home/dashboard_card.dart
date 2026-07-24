import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/fade_slide_in.dart';
import '../pressable_scale.dart';

/// Today's Overview — the hero highlight of the INO Home Screen.
///
/// A living teal section: a primary-only gradient washed with slowly drifting
/// organic blobs, a soft wave, and geometric ring accents (all painted, no
/// assets), fronted by a gently bobbing "shield mascot" badge. The four summary
/// tiles break away from the section with their own soft pastel fills, hairline
/// borders and staggered entrance — connected to the teal world, yet clearly
/// lifted off it.
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

  // Real counts for the four summary tiles — 0 when there's nothing to show.
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
  // One slow, perpetual loop drives every ambient motion in the section — the
  // drifting backdrop and the subtle gradient shift — so the whole surface
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated teal backdrop (gradient shift + drifting graphics). Only
          // this layer repaints each frame; the content in front is static.
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ambient,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_ambient.value);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        // A gentle 0→1 drift of the light source keeps the
                        // primary gradient alive without changing its hue.
                        begin: Alignment(-1 + t * 0.4, -1),
                        end: Alignment(1, 1 - t * 0.4),
                        // Primary-only: a lighter tint highlight easing into
                        // the anchor — never darker than #30ACB3 (brand rule).
                        colors: const [
                          Color(0xFF4FBEC4), // lighter tint highlight
                          AppColors.primaryGreen, // #30ACB3 anchor
                          Color(0xFF3BB6BC), // gentle lighter base
                        ],
                        stops: const [0.0, 0.58, 1.0],
                      ),
                    ),
                    child: CustomPaint(painter: _OverviewBackdrop(t: t)),
                  );
                },
              ),
            ),
          ),

          // Foreground content.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _SummaryGrid(
                  documentsExpiring: widget.documentsExpiring,
                  remindersToday: widget.remindersToday,
                  insuranceRenewals: widget.insuranceRenewals,
                  emiDue: widget.emiDue,
                  onDocumentsExpiring:
                      widget.onDocumentsExpiring ?? widget.onPending,
                  onEmiDues: widget.onEmiDues ?? widget.onCta,
                  onRemindersToday: widget.onRemindersToday ?? widget.onCta,
                  onInsuranceRenewals:
                      widget.onInsuranceRenewals ?? widget.onProtected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Section header: title + subtitle on the left, a bobbing shield mascot on the
/// right.
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      "Today's Overview",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LiveChip(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your important summary for today',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const _MascotBadge(),
        ],
      ),
    );
  }
}

/// A small translucent "Live" pill with a pulsing dot — a soft accent graphic
/// that flags the section as up-to-date.
class _LiveChip extends StatefulWidget {
  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(
              begin: 0.45,
              end: 1.0,
            ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'Live',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
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
                      color: Colors.white.withValues(alpha: 0.22 * (1 - t)),
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
              // The glassy shield badge, bobbing.
              Transform.translate(
                offset: Offset(0, -bob),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.16),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
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
      color: Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
  }
}

/// The 2×2 block of pastel summary tiles, each entering on a small stagger.
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
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
      _OverviewTile(
        title: 'Documents Expiring',
        value: '$documentsExpiring',
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFF59E0B),
        fill: const Color(0xFFFFF6E9),
        // Only draw attention when something actually needs it.
        pulse: documentsExpiring > 0,
        onTap: onDocumentsExpiring,
      ),
      _OverviewTile(
        title: 'EMI Due Tomorrow',
        value: '$emiDue',
        icon: Icons.account_balance_wallet_rounded,
        accent: AppColors.primaryGreen,
        fill: const Color(0xFFE4F5F6),
        onTap: onEmiDues,
      ),
      _OverviewTile(
        title: 'Reminders Today',
        value: '$remindersToday',
        icon: Icons.alarm_rounded,
        accent: const Color(0xFFF5704A),
        fill: const Color(0xFFFFF1EC),
        onTap: onRemindersToday,
      ),
      _OverviewTile(
        title: 'Insurance Renewals',
        value: '$insuranceRenewals',
        icon: Icons.shield_rounded,
        accent: const Color(0xFF8B6CEF),
        fill: const Color(0xFFF1ECFF),
        onTap: onInsuranceRenewals,
      ),
    ];

    Widget cell(int i) => FadeSlideIn(
      delay: Duration(milliseconds: 120 + i * 90),
      offset: 18,
      child: tiles[i],
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cell(0)),
            const SizedBox(width: 10),
            Expanded(child: cell(1)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: cell(2)),
            const SizedBox(width: 10),
            Expanded(child: cell(3)),
          ],
        ),
      ],
    );
  }
}

/// One pastel summary tile: soft fill, hairline accent border, a rounded icon
/// badge, big value and muted label.
class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.fill,
    this.pulse = false,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Color fill;
  final bool pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSmall = context.isMobileSmall;
    final tile = Container(
      padding: EdgeInsets.all(isSmall ? 11 : 13),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: the number sits beside the icon badge.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: isSmall ? 22.rsp : 25.rsp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Icon badge, with a small pulse dot overlay on the urgent tile.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: isSmall ? 34 : 38,
                    height: isSmall ? 34 : 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.20),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: isSmall ? 18 : 20, color: accent),
                  ),
                  if (pulse)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: _PulseDot(color: accent),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Label below, exactly as before.
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
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

/// A small pulsing dot used to flag the most time-sensitive tile.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
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
        final t = _c.value;
        return SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 8 + t * 10,
                height: 8 + t * 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.18 * (1 - t)),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paints the drifting abstract graphics over the teal gradient: soft white
/// blobs, a gentle wave band and thin geometric ring accents. Everything moves
/// with [t] (0→1→0) so the section feels alive without distracting.
class _OverviewBackdrop extends CustomPainter {
  _OverviewBackdrop({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final drift = (t - 0.5) * 22; // −11 → +11 px slow travel

    // Soft radial blobs — layered translucent light.
    void blob(Offset c, double r, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
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
      ..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.30 + drift * 0.5),
      30,
      ring,
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.30 + drift * 0.5),
      46,
      ring..color = Colors.white.withValues(alpha: 0.08),
    );

    // A gentle wave band across the lower third.
    final wave = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final path = Path();
    final baseY = size.height * 0.62;
    final amp = 12.0;
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
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.12);
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
