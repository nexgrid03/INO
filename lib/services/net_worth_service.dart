import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/dashboard_models.dart';
import '../theme/app_theme.dart';

/// The selectable ranges on the net-worth chart.
enum NetWorthRange { week, month, quarter, halfYear, year }

extension NetWorthRangeX on NetWorthRange {
  String get label => switch (this) {
        NetWorthRange.week => '7D',
        NetWorthRange.month => '30D',
        NetWorthRange.quarter => '3M',
        NetWorthRange.halfYear => '6M',
        NetWorthRange.year => '1Y',
      };

  int get points => switch (this) {
        NetWorthRange.week => 7,
        NetWorthRange.month => 30,
        NetWorthRange.quarter => 12, // weekly points
        NetWorthRange.halfYear => 24, // weekly points
        NetWorthRange.year => 12, // monthly points
      };
}

/// A single ₹-valued point on the chart with its date.
class NetWorthPoint {
  const NetWorthPoint(this.date, this.value);
  final DateTime date;
  final double value; // in rupees
}

/// The aggregate net-worth read model for the dashboard + analytics page.
class NetWorthData {
  const NetWorthData({
    required this.total,
    required this.growthPercent,
    required this.growthAmount,
    required this.allocations,
  });

  final double total; // current net worth in rupees
  final double growthPercent; // month-over-month %
  final double growthAmount; // month-over-month ₹ change
  final List<AssetAllocation> allocations;

  bool get isUp => growthPercent >= 0;
}

/// Computes the net-worth figure, its month-over-month change, the asset
/// allocation breakdown, and a deterministic time-series for each chart range.
///
/// The app has no live brokerage/bank feed, so these are **realistic, stable
/// fallback values** (the spec explicitly allows realistic fallback data). The
/// series is generated deterministically from a fixed seed so it never jumps
/// between builds, and every range is internally consistent (they all end at the
/// same current total). Swap this single service for a real aggregator later and
/// the whole dashboard + analytics page update unchanged.
class NetWorthService {
  NetWorthService._();
  static final NetWorthService instance = NetWorthService._();

  // Current allocation snapshot (₹). Sums to the total net worth.
  static const List<AssetAllocation> _allocations = [
    AssetAllocation(label: 'Investments', value: 4860000, color: Color(0xFF1B9C85)),
    AssetAllocation(label: 'Property', value: 5200000, color: Color(0xFF8B6CEF)),
    AssetAllocation(label: 'Bank & Cash', value: 1450000, color: Color(0xFF4FC3F7)),
    AssetAllocation(label: 'Gold', value: 760000, color: Color(0xFFE0A100)),
    AssetAllocation(label: 'Digital Assets', value: 130000, color: AppColors.secondaryGreen),
  ];

  double get total =>
      _allocations.fold<double>(0, (sum, a) => sum + a.value); // ₹1.24 Cr

  List<AssetAllocation> get allocations => _allocations;

  NetWorthData get data {
    final t = total;
    // Month-over-month change derived from the 30-day series.
    final month = seriesFor(NetWorthRange.month);
    final start = month.first.value;
    final growthAmount = t - start;
    final growthPercent = start == 0 ? 0.0 : (growthAmount / start) * 100;
    return NetWorthData(
      total: t,
      growthPercent: double.parse(growthPercent.toStringAsFixed(1)),
      growthAmount: growthAmount,
      allocations: _allocations,
    );
  }

  /// A deterministic series for [range], ending exactly at [total] today.
  List<NetWorthPoint> seriesFor(NetWorthRange range, {DateTime? now}) {
    final end = now ?? DateTime.now();
    final n = range.points;
    final t = total;

    // Overall drift across the whole range (longer ranges → more total growth).
    final drift = switch (range) {
      NetWorthRange.week => 0.015,
      NetWorthRange.month => 0.042,
      NetWorthRange.quarter => 0.086,
      NetWorthRange.halfYear => 0.14,
      NetWorthRange.year => 0.27,
    };
    final startValue = t / (1 + drift);

    final stepDuration = switch (range) {
      NetWorthRange.week => const Duration(days: 1),
      NetWorthRange.month => const Duration(days: 1),
      NetWorthRange.quarter => const Duration(days: 7),
      NetWorthRange.halfYear => const Duration(days: 7),
      NetWorthRange.year => const Duration(days: 30),
    };

    final points = <NetWorthPoint>[];
    for (var i = 0; i < n; i++) {
      final f = n == 1 ? 1.0 : i / (n - 1); // 0 → 1
      // Smooth base interpolation + a small deterministic wave for texture.
      final base = startValue + (t - startValue) * f;
      final wave = math.sin((i / n) * math.pi * 3 + range.index) *
          (t * 0.008); // ±0.8% ripple
      final value = i == n - 1 ? t : base + wave;
      final date = end.subtract(stepDuration * (n - 1 - i));
      points.add(NetWorthPoint(date, value));
    }
    return points;
  }

  /// The home hero, derived from the same numbers so Home and Analytics agree.
  HomeHero heroFrom({
    required int assets,
    required int documents,
    required int pendingTasks,
    required int protectedItems,
  }) {
    final d = data;
    final week = seriesFor(NetWorthRange.month).map((p) => p.value).toList();
    return HomeHero(
      netWorth: formatInr(d.total),
      growthPercent: d.growthPercent,
      growthAmount: formatInr(d.growthAmount),
      trend: week,
      assets: assets,
      documents: documents,
      pendingTasks: pendingTasks,
      protectedItems: protectedItems,
    );
  }
}

/// Formats a rupee amount into a compact Indian label: ₹1.24 Cr, ₹48.6 L, ₹7,400.
String formatInr(double amount) {
  final v = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (v >= 10000000) return '$sign₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '$sign₹${(v / 100000).toStringAsFixed(2)} L';
  if (v >= 1000) {
    // Indian grouping for thousands (₹7,412).
    final s = v.toStringAsFixed(0);
    return '$sign₹${_indianGroup(s)}';
  }
  return '$sign₹${v.toStringAsFixed(0)}';
}

/// Groups an integer string in the Indian system (last 3, then pairs).
/// e.g. "1234567" → "12,34,567", "7412" → "7,412".
String _indianGroup(String number) {
  if (number.length <= 3) return number;
  final last3 = number.substring(number.length - 3);
  var rest = number.substring(0, number.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}
