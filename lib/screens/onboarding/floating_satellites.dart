import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A small contextual "satellite" chip floating around the main onboarding
/// icon (e.g. an Aadhaar card, a shield, a rupee symbol).
class _SatelliteData {
  const _SatelliteData(this.icon, this.color);
  final IconData icon;

  /// Fixed accent — never the live brand getter, so Aqua/Launcher can't
  /// collapse every chip into the same teal.
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

/// Distinct palette accents (const) — readable in light and dark, independent
/// of [AppColors.primaryGreen] which tracks the Aqua style switch.
const Color _cTeal = Color(0xFF098F90);
const Color _cMint = Color(0xFF14B8A6);
const Color _cViolet = Color(0xFF8B5CF6);
const Color _cAmber = Color(0xFFF59E0B);
const Color _cCoral = Color(0xFFF43F5E);
const Color _cIndigo = Color(0xFF0D9488);
const Color _cEmerald = Color(0xFF10B981);

/// Contextual chips per screen — each icon gets its own accent.
const List<List<_SatelliteData>> _byScreen = [
  // Screen 0 - Documents.
  [
    _SatelliteData(Icons.verified_user_rounded, _cMint),
    _SatelliteData(Icons.badge_rounded, _cViolet),
    _SatelliteData(Icons.credit_card_rounded, _cIndigo),
    _SatelliteData(Icons.menu_book_rounded, _cAmber),
    _SatelliteData(Icons.cloud_done_rounded, _cTeal),
  ],
  // Screen 1 - Wealth & Health.
  [
    _SatelliteData(Icons.savings_rounded, _cAmber),
    _SatelliteData(Icons.account_balance_rounded, _cIndigo),
    _SatelliteData(Icons.home_rounded, _cEmerald),
    _SatelliteData(Icons.favorite_rounded, _cCoral),
    _SatelliteData(Icons.currency_rupee_rounded, _cMint),
  ],
  // Screen 2 - Share & Secure.
  [
    _SatelliteData(Icons.share_rounded, _cTeal),
    _SatelliteData(Icons.lock_rounded, _cViolet),
    _SatelliteData(Icons.fingerprint_rounded, _cIndigo),
    _SatelliteData(Icons.verified_rounded, _cEmerald),
    _SatelliteData(Icons.check_circle_rounded, _cMint),
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
              // Stagger pops after the main circle (~0.22) and before title (~0.68).
              popStart: 0.32 + i * 0.06,
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

  static const double _popLength = 0.12;
  static const double _floatAmplitude = 3.5; // subtle bob — premium, not playful

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    return AnimatedBuilder(
      animation: Listenable.merge([pop, float]),
      builder: (context, child) {
        // Entrance progress 0 -> 1
        final double raw =
            ((pop.value - popStart) / _popLength).clamp(0.0, 1.0);
        final double appear = Curves.easeOutBack.transform(raw);
        final double opacity = raw;

        // Gentle, perpetual vertical bob using the same math as SecuredIntroScreen
        // Note: float goes 0 -> 1 -> 0 because reverse: true
        final double bob =
            math.sin(float.value * math.pi + floatPhase * 1.6) *
                _floatAmplitude;

        // Dark: soft frosted disc + coloured glyph (high contrast).
        // Light: tinted wash + coloured glyph.
        final Color chipFill = dark
            ? Color.alphaBlend(
                data.color.withValues(alpha: 0.28),
                const Color(0xFF1A2A3A),
              )
            : Color.alphaBlend(
                data.color.withValues(alpha: 0.12),
                Colors.white,
              );
        final Color chipBorder = data.color.withValues(alpha: dark ? 0.55 : 0.40);
        final Color glyphColor = dark ? Colors.white : data.color;

        return Transform.translate(
          // Flies in from further out along its own axis, then floats
          offset: Offset(
            offset.dx * (0.55 + 0.45 * appear),
            offset.dy * appear + bob,
          ),
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: 0.7 + 0.3 * appear,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: chipFill,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: chipBorder),
                  boxShadow: [
                    BoxShadow(
                      color: data.color.withValues(alpha: dark ? 0.28 : 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(data.icon, color: glyphColor, size: 22),
              ),
            ),
          ),
        );
      },
    );
  }
}
