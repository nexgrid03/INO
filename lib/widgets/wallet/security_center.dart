import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../dashboard/section_header.dart';

/// Section 6 — Security Center.
///
/// Pairs an animated circular security-score ring with a checklist of the
/// vault's protections (lock, biometric, backup, cloud sync). The ring sweeps
/// in once on mount for an Apple-quality reveal.
class SecurityCenter extends StatefulWidget {
  const SecurityCenter({super.key, required this.status});

  final SecurityStatus status;

  @override
  State<SecurityCenter> createState() => _SecurityCenterState();
}

class _SecurityCenterState extends State<SecurityCenter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _sweep =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final s = widget.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Security Center',
          subtitle: 'Your vault protection status',
          actionLabel: 'Manage',
          icon: Icons.security_rounded,
        ),
        InoCard(
          child: Row(
            children: [
              // Animated score ring.
              AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => _ScoreRing(
                  score: s.score,
                  progress: _sweep.value,
                  trackColor: palette.surfaceVariant,
                  labelColor: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusRow(
                      icon: Icons.lock_rounded,
                      label: 'Vault',
                      value: s.vaultLocked ? 'Locked & encrypted' : 'Unlocked',
                      ok: s.vaultLocked,
                    ),
                    _StatusRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'Biometric',
                      value: s.biometricEnabled ? 'Enabled' : 'Disabled',
                      ok: s.biometricEnabled,
                    ),
                    _StatusRow(
                      icon: Icons.cloud_done_rounded,
                      label: 'Cloud sync',
                      value: s.cloudSynced ? 'Synced' : 'Pending',
                      ok: s.cloudSynced,
                    ),
                    _StatusRow(
                      icon: Icons.backup_rounded,
                      label: 'Last backup',
                      value: s.lastBackup,
                      ok: true,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.progress,
    required this.trackColor,
    required this.labelColor,
  });

  final int score;
  final double progress;
  final Color trackColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(size),
            painter: _RingPainter(
              fraction: (score / 100) * progress,
              trackColor: trackColor,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(score * progress).round()}%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: labelColor,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Secure',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.trackColor});

  final double fraction;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    // Progress arc with a brand gradient.
    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    final paint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [AppColors.primaryGreen, AppColors.lightBlue, AppColors.primaryGreen],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.trackColor != trackColor;
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final statusColor = ok ? AppColors.primaryGreen : AppColors.warning;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.textFaint),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 15,
            color: statusColor,
          ),
        ],
      ),
    );
  }
}
