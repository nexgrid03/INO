import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/screens/networth/net_worth_analytics_screen.dart';
import 'package:inoapp/screens/notifications/notifications_screen.dart';
import 'package:inoapp/screens/search/global_search_screen.dart';
import 'package:inoapp/services/net_worth_service.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  group('NetWorthService', () {
    test('formatInr renders compact Indian units', () {
      expect(formatInr(12400000), '₹1.24 Cr');
      expect(formatInr(4860000), '₹48.60 L');
      expect(formatInr(7412), '₹7,412');
      expect(formatInr(-5200), '-₹5,200');
    });

    test('each range series ends exactly at the current total', () {
      final total = NetWorthService.instance.total;
      for (final range in NetWorthRange.values) {
        final series = NetWorthService.instance.seriesFor(range);
        expect(series.length, range.points);
        expect(series.last.value, closeTo(total, 0.01),
            reason: '${range.label} should end at the current total');
      }
    });

    test('net worth reports a positive month-over-month growth', () {
      final data = NetWorthService.instance.data;
      expect(data.total, greaterThan(0));
      expect(data.isUp, isTrue);
      expect(data.allocations, isNotEmpty);
    });
  });

  testWidgets('Net Worth Analytics renders the chart + distribution',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: NetWorthAnalyticsScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Total net worth'), findsOneWidget);
    expect(find.text('Asset distribution'), findsOneWidget);
    // The interactive range selector is present.
    expect(find.text('30D'), findsOneWidget);
    expect(find.text('1Y'), findsOneWidget);
  });

  testWidgets('Global search shows suggestions before typing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const GlobalSearchScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('SUGGESTIONS'), findsOneWidget);
    expect(find.text('Insurance'), findsWidgets);
  });

  testWidgets('Notifications generate from security/backup posture',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const NotificationsScreen()),
    );
    // Let the async refresh() complete and rebuild the list.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    // With no biometric lock / 2FA / backup set in a fresh test, security and
    // backup notifications are generated.
    expect(find.text('Add a biometric lock'), findsOneWidget);
  });
}
