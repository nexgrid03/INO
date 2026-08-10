import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Centralized Performance Instrumentation Engine for INO Application.
///
/// Tracks and reports:
///   1. Query & API Execution Timings
///   2. Screen Open & Render Timings
///   3. Widget Rebuild Counts & High-Frequency Rebuild Alerts
///   4. Performance Metrics Report (Top 20 Slowest Queries/Screens/Widgets)
class PerfTracer {
  PerfTracer._();
  static final PerfTracer instance = PerfTracer._();

  static const bool _enabled = kDebugMode;

  final Map<String, List<double>> _queryDurationsMs = {};
  final Map<String, int> _queryCounts = {};

  final Map<String, List<double>> _screenRenderDurationsMs = {};
  final Map<String, int> _widgetRebuildCounts = {};

  /// Measures execution time of an async query or network call.
  static Future<T> traceQuery<T>(String queryName, Future<T> Function() queryFn) async {
    if (!_enabled) return queryFn();
    final stopwatch = Stopwatch()..start();
    try {
      final result = await queryFn();
      stopwatch.stop();
      instance._recordQuery(queryName, stopwatch.elapsedMicroseconds / 1000.0);
      return result;
    } catch (e) {
      stopwatch.stop();
      instance._recordQuery('$queryName [ERR]', stopwatch.elapsedMicroseconds / 1000.0);
      rethrow;
    }
  }

  /// Measures execution time of a synchronous operation or calculation.
  static T traceSync<T>(String name, T Function() fn) {
    if (!_enabled) return fn();
    final stopwatch = Stopwatch()..start();
    try {
      final result = fn();
      stopwatch.stop();
      instance._recordQuery(name, stopwatch.elapsedMicroseconds / 1000.0);
      return result;
    } catch (e) {
      stopwatch.stop();
      instance._recordQuery('$name [ERR]', stopwatch.elapsedMicroseconds / 1000.0);
      rethrow;
    }
  }

  /// Records screen open and first-render duration.
  static void recordScreenRender(String screenName, double durationMs) {
    if (!_enabled) return;
    instance._screenRenderDurationsMs.putIfAbsent(screenName, () => []).add(durationMs);
    developer.log('Screen Render: $screenName → ${durationMs.toStringAsFixed(1)} ms', name: 'perf.screen');
  }

  /// Increments widget rebuild count for diagnostic reporting.
  static void recordWidgetRebuild(String widgetName) {
    if (!_enabled) return;
    instance._widgetRebuildCounts[widgetName] = (instance._widgetRebuildCounts[widgetName] ?? 0) + 1;
  }

  void _recordQuery(String name, double durationMs) {
    _queryDurationsMs.putIfAbsent(name, () => []).add(durationMs);
    _queryCounts[name] = (_queryCounts[name] ?? 0) + 1;
    if (durationMs > 100) {
      developer.log('SLOW QUERY: $name took ${durationMs.toStringAsFixed(1)} ms (count=${_queryCounts[name]})', name: 'perf.query');
    }
  }

  /// Generates a comprehensive performance report summary.
  String generateReport() {
    final buffer = StringBuffer();
    buffer.writeln('====================================================');
    buffer.writeln('   INO PERFORMANCE INSTRUMENTATION REPORT');
    buffer.writeln('====================================================');

    // 1. Slowest Queries
    buffer.writeln('\n--- TOP QUERIES & APIS BY AVERAGE DURATION ---');
    final queryAvgs = _queryDurationsMs.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return MapEntry(e.key, MapEntry(avg, e.value.length));
    }).toList()
      ..sort((a, b) => b.value.key.compareTo(a.value.key));

    for (final e in queryAvgs.take(20)) {
      buffer.writeln('${e.key.padRight(40)} | avg: ${e.value.key.toStringAsFixed(1).padLeft(6)} ms | calls: ${e.value.value}');
    }

    // 2. Screen Renders
    buffer.writeln('\n--- SCREEN RENDER TIMINGS ---');
    for (final e in _screenRenderDurationsMs.entries) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      buffer.writeln('${e.key.padRight(40)} | avg: ${avg.toStringAsFixed(1).padLeft(6)} ms | views: ${e.value.length}');
    }

    // 3. Widget Rebuilds
    buffer.writeln('\n--- TOP REBUILT WIDGETS ---');
    final rebuilds = _widgetRebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in rebuilds.take(20)) {
      buffer.writeln('${e.key.padRight(40)} | rebuilds: ${e.value}');
    }

    buffer.writeln('====================================================');
    return buffer.toString();
  }
}
