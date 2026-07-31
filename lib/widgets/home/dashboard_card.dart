import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/shiny_border.dart';
import '../dashboard/fade_slide_in.dart';
import '../pressable_scale.dart';

/// Today's Overview - the hero highlight of the INO Home Screen.
///
/// A living teal section: a primary-only gradient washed with slowly drifting
/// organic blobs, a soft wave, and geometric ring accents (all painted, no
/// assets), fronted by a gently bobbing "shield mascot" badge. The four summary
/// tiles break away from the section with their own soft pastel fills, hairline
/// borders and staggered entrance - connected to the teal world, yet clearly
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
  // One slow, perpetual loop drives every ambient motion in the section - the
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
    // Divine Glass: the hero is a luminous white glass card - a hairline
    // light-blue edge, whisper shadow and a slowly drifting sky wash behind
    // the content (in place of the old saturated teal flood).
    final palette = AppPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Stack(
        children: [
          // Animated sky-wash backdrop (gradient shift + drifting graphics).
          // Only this layer repaints each frame; the content in front is
          // static.
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
                        // wash alive without changing its hue.
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
    final palette = AppPalette.of(context);
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
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Today's Overview",
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
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
                    color: palette.textSecondary,
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

/// A small translucent "Live" pill with a pulsing dot - a soft accent graphic
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
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
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
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'Live',
            style: TextStyle(
              color: AppColors.success,
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
        onTap: onDocumentsExpiring,
      ),
      _OverviewTile(
        title: 'EMI Due Tomorrow',
        value: '$emiDue',
        icon: Icons.account_balance_wallet_rounded,
        // Blue, not the brand teal: a teal border here disappeared into the
        // section's own teal backdrop. Also clear of the other three tiles
        // (amber / coral / purple).
        accent: const Color(0xFF2563EB),
        fill: const Color(0xFFE9EFFD),
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
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Color fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSmall = context.isMobileSmall;
    final themeStyle = InoStyle.of(context);
    final bold = themeStyle == ThemeStyle.bold;
    final soft = themeStyle == ThemeStyle.soft;

    // Bold: the colour that used to live on the small inner icon badge floods
    // the whole tile (run deeper), and the glyph stays in place in plain
    // white. Soft: the pastel fill lifts lighter and the badge goes glass, so
    // the glyph shows in its own colour (handled inside ShinyIcon); the border
    // keeps the classic accent and gains a glass sheen (ShinyBorder below).
    final Color tileFill = bold
        ? InoStyle.boldFill(accent)
        : soft
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.45), fill)
        : fill;
    final Color edge = bold ? InoStyle.boldBorder(accent) : accent;
    final badgeSize = isSmall ? 34.0 : 38.0;
    // With the badge body gone in bold the bare glyph reads small - let it
    // grow into the freed slot.
    final glyphSize = bold ? (isSmall ? 26.0 : 30.0) : (isSmall ? 18.0 : 20.0);

    final tile = Container(
      padding: EdgeInsets.all(isSmall ? 11 : 13),
      decoration: BoxDecoration(
        color: tileFill,
        borderRadius: BorderRadius.circular(20),
        // Bold keeps its thick accent edge; classic/soft wear the Divine
        // Glass hairline in the tile's own accent.
        border: Border.all(
          color: bold ? edge : edge.withValues(alpha: 0.30),
          width: bold ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: bold ? 0.24 : 0.10),
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
                      color: bold ? Colors.white : AppColors.textDark,
                      fontSize: isSmall ? 22.rsp : 25.rsp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Bold keeps the glyph in exactly the same slot but drops the
              // badge body - the tile itself is now the coloured container.
              bold
                  ? SizedBox(
                      width: badgeSize,
                      height: badgeSize,
                      child: Icon(icon, color: Colors.white, size: glyphSize),
                    )
                  : Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        // Pastel chip: the accent as a soft tint behind its
                        // own coloured glyph.
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: glyphSize),
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
              color: bold ? InoStyle.boldTextSecondary : AppColors.textMuted,
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    // Soft: the hairline accent border picks up a glass sheen.
    final styled = ShinyBorder(
      radius: 20,
      width: 1,
      enabled: soft,
      child: tile,
    );

    if (onTap == null) return styled;
    return PressableScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: styled,
      ),
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
