import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/storage/shared_prefs_cache.dart';

import '../models/dashboard_models.dart';
import '../models/investment_models.dart';
import '../theme/app_theme.dart';
import 'investment_store.dart';
import 'property_store.dart';

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
        NetWorthRange.quarter => 12,
        NetWorthRange.halfYear => 24,
        NetWorthRange.year => 12,
      };

  Duration get window => switch (this) {
        NetWorthRange.week => const Duration(days: 6),
        NetWorthRange.month => const Duration(days: 29),
        NetWorthRange.quarter => const Duration(days: 84),
        NetWorthRange.halfYear => const Duration(days: 168),
        NetWorthRange.year => const Duration(days: 365),
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

  final double total;
  final double growthPercent;
  final double growthAmount;
  final List<AssetAllocation> allocations;

  bool get isUp => growthPercent >= 0;
}

/// Aggregates **real** wallet values (Property + Investments) into net worth,
/// allocation, and a chart series built from persisted daily snapshots.
///
/// No illustrative / fallback figures. An empty portfolio reads as ₹0.
class NetWorthService extends ChangeNotifier {
  NetWorthService._() {
    InvestmentStore.instance.addListener(_onStoresChanged);
    PropertyStore.instance.addListener(_onStoresChanged);
  }

  static final NetWorthService instance = NetWorthService._();

  static const _historyKey = 'ino_net_worth_history';

  bool _ready = false;
  final bool _listening = true;
  List<_Snapshot> _history = const [];

  bool get isReady => _ready;

  Future<void> ensureReady() async {
    await Future.wait([
      InvestmentStore.instance.ensureLoaded(),
      PropertyStore.instance.ensureLoaded(),
    ]);
    await _loadHistory();
    await _recordToday();
    _ready = true;
    notifyListeners();
  }

  void _onStoresChanged() {
    if (!_listening || !_ready) return;
    // Fire-and-forget: keep the chart history honest as holdings change.
    _recordToday().then((_) => notifyListeners());
  }

  double get investmentsValue => InvestmentStore.instance.totalValue;

  double get propertyValue => PropertyStore.instance.totalValue;

  double get total => investmentsValue + propertyValue;

  /// Non-zero buckets only, sourced from live stores.
  List<AssetAllocation> get allocations {
    final list = <AssetAllocation>[];
    final property = propertyValue;
    if (property > 0) {
      list.add(AssetAllocation(
        label: 'Property',
        value: property,
        color: const Color(0xFF8B6CEF),
      ));
    }

    var investments = 0.0;
    var gold = 0.0;
    var digital = 0.0;
    for (final i in InvestmentStore.instance.items) {
      final v = i.value;
      if (v <= 0) continue;
      switch (i.type) {
        case InvestmentType.gold:
          gold += v;
        case InvestmentType.crypto:
          digital += v;
        default:
          investments += v;
      }
    }
    if (investments > 0) {
      list.add(AssetAllocation(
        label: 'Investments',
        value: investments,
        color: const Color(0xFF059669),
      ));
    }
    if (gold > 0) {
      list.add(AssetAllocation(
        label: 'Gold',
        value: gold,
        color: AppColors.gold,
      ));
    }
    if (digital > 0) {
      list.add(AssetAllocation(
        label: 'Digital Assets',
        value: digital,
        color: AppColors.skyBrandSecondary,
      ));
    }
    return List.unmodifiable(list);
  }

  NetWorthData get data {
    final t = total;
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final past = _valueAtOrBefore(monthAgo);
    final start = past ?? t;
    final growthAmount = t - start;
    final growthPercent = start == 0
        ? 0.0
        : double.parse(((growthAmount / start) * 100).toStringAsFixed(1));
    return NetWorthData(
      total: t,
      growthPercent: growthPercent,
      growthAmount: growthAmount,
      allocations: allocations,
    );
  }

  /// Series for [range] from persisted snapshots. Flat at [total] when history
  /// is thinner than two distinct points (honest empty / new-user state).
  List<NetWorthPoint> seriesFor(NetWorthRange range, {DateTime? now}) {
    final end = now ?? DateTime.now();
    final start = end.subtract(range.window);
    final t = total;
    final n = range.points;

    final inWindow = [
      for (final s in _history)
        if (!s.day.isBefore(_dateOnly(start)) && !s.day.isAfter(_dateOnly(end)))
          s,
    ];

    // Always end on today's live total.
    final samples = <_Snapshot>[
      ...inWindow.where((s) => !_isSameDay(s.day, end)),
      _Snapshot(_dateOnly(end), t),
    ];

    if (samples.length == 1) {
      // No prior history — flat line (not a fabricated trend).
      return [
        for (var i = 0; i < n; i++)
          NetWorthPoint(
            end.subtract(range.window * ((n - 1 - i) / (n - 1))),
            t,
          ),
      ];
    }

    final points = <NetWorthPoint>[];
    for (var i = 0; i < n; i++) {
      final f = n == 1 ? 1.0 : i / (n - 1);
      final date = start.add(range.window * f);
      final value = i == n - 1 ? t : _interpolate(samples, date);
      points.add(NetWorthPoint(date, value));
    }
    return points;
  }

  /// Home hero from the same live totals so Home and Analytics agree.
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

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) {
        _history = const [];
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _history = const [];
        return;
      }
      final list = <_Snapshot>[];
      for (final row in decoded) {
        if (row is! Map) continue;
        final d = DateTime.tryParse('${row['d']}');
        final v = row['v'];
        final value = v is num ? v.toDouble() : double.tryParse('$v');
        if (d == null || value == null) continue;
        list.add(_Snapshot(_dateOnly(d), value));
      }
      list.sort((a, b) => a.day.compareTo(b.day));
      _history = List.unmodifiable(list);
    } catch (_) {
      _history = const [];
    }
  }

  Future<void> _recordToday() async {
    final today = _dateOnly(DateTime.now());
    final value = total;
    final next = [..._history];
    if (next.isNotEmpty && _isSameDay(next.last.day, today)) {
      next[next.length - 1] = _Snapshot(today, value);
    } else {
      next.add(_Snapshot(today, value));
    }
    // Keep ~2 years of daily points max.
    while (next.length > 800) {
      next.removeAt(0);
    }
    _history = List.unmodifiable(next);
    try {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      await prefs.setString(
        _historyKey,
        jsonEncode([
          for (final s in _history)
            {
              'd': s.day.toIso8601String().substring(0, 10),
              'v': s.value,
            },
        ]),
      );
    } catch (_) {
      // Preferences unavailable (tests) — keep in-memory history only.
    }
  }

  double? _valueAtOrBefore(DateTime day) {
    final target = _dateOnly(day);
    _Snapshot? best;
    for (final s in _history) {
      if (s.day.isAfter(target)) break;
      best = s;
    }
    return best?.value;
  }

  static double _interpolate(List<_Snapshot> samples, DateTime date) {
    final day = _dateOnly(date);
    if (samples.isEmpty) return 0;
    if (!day.isAfter(samples.first.day)) return samples.first.value;
    if (!day.isBefore(samples.last.day)) return samples.last.value;
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      if (day.isBefore(b.day) || _isSameDay(day, b.day)) {
        final span = b.day.difference(a.day).inDays;
        if (span <= 0) return b.value;
        final f = day.difference(a.day).inDays / span;
        return a.value + (b.value - a.value) * f;
      }
    }
    return samples.last.value;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Snapshot {
  const _Snapshot(this.day, this.value);
  final DateTime day;
  final double value;
}

/// Formats a rupee amount into a compact Indian label: ₹1.24 Cr, ₹48.6 L, ₹7,400.
String formatInr(double amount) {
  final v = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (v >= 10000000) return '$sign₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '$sign₹${(v / 100000).toStringAsFixed(2)} L';
  if (v >= 1000) {
    final s = v.toStringAsFixed(0);
    return '$sign₹${_indianGroup(s)}';
  }
  return '$sign₹${v.toStringAsFixed(0)}';
}

/// Groups an integer string in the Indian system (last 3, then pairs).
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
