import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A small contextual "satellite" chip floating around the main onboarding
/// icon (e.g. an Aadhaar card, a shield, a rupee symbol).
class _SatelliteData {
  const _SatelliteData(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// Fixed "crown" positions (offset from the circle's centre, in logical
/// pixels). Five chips arranged across the top and sides of the 160px circle,
/// deliberately kept clear of the title below (no chips low/centre).
const List<Offset> _positions = [
  Offset(0, -88), // top-centre
  Offset(-92, -48), // upper-left
  Offset(92, -48), // upper-right
  Offset(-108, 14), // mid-left
  Offset(108, 14), // mid-right
];

/// Per-chip phase offset so they don't all bob in unison.
const List<double> _floatPhases = [0.0, 0.4, 0.7, 0.2, 0.55];

/// Contextual chips per screen (4–6 elements, kept uncrowded). Matched to that
/// screen's theme.
const List<List<_SatelliteData>> _byScreen = [
  // Screen 0 — Documents.
  [
    _SatelliteData(Icons.verified_user_rounded, AppColors.primaryGreen),
    _SatelliteData(Icons.badge_rounded, AppColors.lightBlue),
    _SatelliteData(Icons.credit_card_rounded, AppColors.primaryGreen),
    _SatelliteData(Icons.menu_book_rounded, AppColors.lightBlue),
    _SatelliteData(Icons.cloud_done_rounded, AppColors.primaryGreen),
  ],
  // Screen 1 — Wealth & Health.
  [
    _SatelliteData(Icons.savings_rounded, AppColors.primaryGreen),
    _SatelliteData(Icons.account_balance_rounded, AppColors.lightBlue),
    _SatelliteData(Icons.home_rounded, AppColors.primaryGreen),
    _SatelliteData(Icons.favorite_rounded, AppColors.lightBlue),
    _SatelliteData(Icons.currency_rupee_rounded, AppColors.primaryGreen),
  ],
  // Screen 2 — Share & Secure.
  [
    _SatelliteData(Icons.share_rounded, AppColors.primaryGreen),
    _SatelliteData(Icons.lock_rounded, AppColors.lightBlue),
    _SatelliteData(Icons.fingerprint_rounded, AppColors.primaryGreen),
    _SatelliteData(Icons.verified_rounded, AppColors.lightBlue),
    _SatelliteData(Icons.check_circle_rounded, AppColors.primaryGreen),
  ],
];

/// Lays out the floating satellite chips around the centre of a 160px box.
///
/// Keeps the laid-out size at 160 (so the surrounding layout/spacing is
/// untouched); chips are translated outwards and rendered beyond that box via
/// `Clip.none`. Each chip pops in (staggered) using [pop] and bobs forever
/// using [float].
class FloatingSatellites extends StatelessWidget {
  const FloatingSatellites({
    super.key,
    required this.index,
    required this.pop,
    required this.float,
  });

  /// Which screen's chip set to show.
  final int index;

  /// Entrance progress 0→1 (drives the staggered pop-in).
  final Animation<double> pop;

  /// Perpetual 0→1 loop (drives the gentle bobbing).
  final Animation<double> float;

  @override
  Widget build(BuildContext context) {
    final data = _byScreen[index];
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < data.length; i++)
            _Satellite(
              data: data[i],
              offset: _positions[i],
              // Stagger the pops AFTER the main circle has fully appeared
              // (~0.34) and BEFORE the title starts (~0.81).
              popStart: 0.38 + i * 0.07,
              floatPhase: _floatPhases[i],
              pop: pop,
              float: float,
            ),
        ],
      ),
    );
  }
}

class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.data,
    required this.offset,
    required this.popStart,
    required this.floatPhase,
    required this.pop,
    required this.float,
  });

  final _SatelliteData data;
  final Offset offset;
  final double popStart;
  final double floatPhase;
  final Animation<double> pop;
  final Animation<double> float;

  static const double _popLength = 0.14;
  static const double _floatAmplitude = 5.0; // px of vertical bob

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pop, float]),
      builder: (context, child) {
        // Staggered pop-in: scale (soft overshoot) + fade.
        final double raw =
            ((pop.value - popStart) / _popLength).clamp(0.0, 1.0);
        final double scale = Curves.easeOutBack.transform(raw);
        final double opacity = raw;

        // Gentle, perpetual vertical bob.
        final double bob =
            math.sin(2 * math.pi * (float.value + floatPhase)) *
                _floatAmplitude;

        return Transform.translate(
          offset: offset + Offset(0, bob),
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: _chip(),
    );
  }

  Widget _chip() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          // Soft depth shadow.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          // Subtle coloured glow.
          BoxShadow(
            color: data.color.withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(data.icon, size: 22, color: data.color),
    );
  }
}
