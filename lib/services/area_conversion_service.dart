import 'dart:math' as math;

import '../models/area_unit.dart';

/// One converted value, ready to display.
class AreaConversion {
  const AreaConversion({
    required this.unit,
    required this.value,
    required this.display,
  });

  /// The target unit.
  final AreaUnit unit;

  /// The high-precision converted value (unrounded).
  final double value;

  /// [value] formatted for the UI (2 dp, trailing zeros stripped, smarter for
  /// small magnitudes). Never compute this in a widget — always read it here.
  final String display;
}

/// The single source of truth for property-area maths.
///
/// UI never hard-codes a factor: it calls [convert] / [convertToAll] /
/// [summary]. All arithmetic is done in `double` against the square-feet base in
/// [AreaUnitX.squareFeetPerUnit], and rounding happens only at display time via
/// [format].
class AreaConversionService {
  const AreaConversionService._();

  /// Shared instance (the service is stateless, so this is just a convenience).
  static const AreaConversionService instance = AreaConversionService._();

  /// The order units are shown in throughout the feature (small → large).
  static const List<AreaUnit> displayOrder = AreaUnit.values;

  /// Converts [value] from [from] to [to] with full `double` precision.
  double convert(double value, AreaUnit from, AreaUnit to) {
    if (from == to) return value;
    return value * from.squareFeetPerUnit / to.squareFeetPerUnit;
  }

  /// Every unit's value for [value] given as [from] (high precision, unrounded).
  Map<AreaUnit, double> convertToAll(double value, AreaUnit from) {
    return {for (final u in AreaUnit.values) u: convert(value, from, u)};
  }

  /// An ordered list of conversions for a summary card. Excludes the source
  /// [from] unit by default (pass [includeSource] to keep it).
  List<AreaConversion> summary(
    double value,
    AreaUnit from, {
    bool includeSource = false,
    List<AreaUnit> units = displayOrder,
  }) {
    final out = <AreaConversion>[];
    for (final u in units) {
      if (!includeSource && u == from) continue;
      final v = convert(value, from, u);
      out.add(AreaConversion(unit: u, value: v, display: format(v)));
    }
    return out;
  }

  /// Formats an area value for display:
  ///   • `|v| >= 1`  → 2 decimal places
  ///   • `|v| < 1`   → enough places to keep ~2 significant figures
  ///                   (so 0.0771 → "0.077", 0.0312 → "0.031", not "0.08")
  /// then strips any trailing zeros (and a dangling ".").
  String format(double value) {
    if (value == 0 || value.isNaN || value.isInfinite) return '0';

    final abs = value.abs();
    final int decimals;
    if (abs >= 1) {
      decimals = 2;
    } else {
      // Leading zeros after the decimal point, e.g. 0.077 → 1, 0.0031 → 2.
      final leadingZeros = (-(math.log(abs) / math.ln10)).floor();
      decimals = (leadingZeros + 2).clamp(2, 8);
    }

    var s = value.toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// "373.15 Sq.Yards" — a formatted value with its unit's short label.
  String formatWithUnit(double value, AreaUnit unit) =>
      '${format(value)} ${unit.shortLabel}';

  /// A plain-text block for the "Copy All" button / clipboard, e.g.
  ///
  ///   312 Sq.M =
  ///   3358.34 Sq.Ft
  ///   373.15 Sq.Yards
  ///   …
  String asCopyText(
    double value,
    AreaUnit from, {
    List<AreaUnit> units = displayOrder,
  }) {
    final buffer = StringBuffer('${format(value)} ${from.shortLabel} =\n');
    for (final c in summary(value, from, units: units)) {
      buffer.writeln('${c.display} ${c.unit.shortLabel}');
    }
    return buffer.toString().trimRight();
  }
}
