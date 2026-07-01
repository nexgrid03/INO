import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/reminder_store.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/screens/reminders/reminders_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

UserProfile _profile() => UserProfile(
      id: '1',
      authUserId: 'a',
      fullName: 'Tanishq Sharma',
      email: 't@example.com',
      preferredLanguage: 'en',
      biometricEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

// Wide canvas so the horizontally-scrolling filter chips all lay out (a lazy
// ListView won't build chips past the viewport edge).
Future<void> _pumpReminders(WidgetTester tester, {Size size = const Size(2400, 7000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RemindersScreen(profile: _profile()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400)); // repo load
  await tester.pumpAndSettle(); // entrance animations
}

void main() {
  // Each test hydrates the shared store fresh for isolation.
  setUp(() => ReminderStore.instance.reset());

  testWidgets('Main screen is minimal: header, summary, filters, priorities',
      (tester) async {
    await _pumpReminders(tester);
    expect(tester.takeException(), isNull);

    // Header + compact 2x2 summary (short labels).
    expect(find.text('Reminders'), findsOneWidget);
    for (final label in const ['Today', 'This Week', 'Expiring Soon', 'Completed']) {
      expect(find.text(label), findsWidgets, reason: '$label summary card');
    }

    // Curated six filters.
    for (final chip in const [
      'All', 'Documents', 'Insurance', 'Health', 'Property', 'Family',
    ]) {
      expect(find.text(chip), findsWidgets, reason: '$chip filter chip');
    }

    // Today's Priorities is the hero + a real due-today item surfaces.
    expect(find.text("Today's Priorities"), findsOneWidget);
    expect(find.text('Passport Renewal'), findsWidgets);

    // One clean entry to the full list.
    expect(find.text('View All Reminders'), findsOneWidget);

    // Sections that were moved off the home screen must NOT appear here.
    for (final gone in const [
      'Month View',
      'Upcoming Events',
      'Quick Actions',
      'Recently Completed',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone should be gone');
    }
  });

  testWidgets('Filtering by a category narrows the priorities', (tester) async {
    // Wide canvas so the "Health" chip is on-screen without horizontal scroll.
    await _pumpReminders(tester, size: const Size(2400, 7000));

    // The chip renders above the cards, so `.first` is the filter chip.
    final healthChip = find.text('Health').first;
    await tester.ensureVisible(healthChip);
    await tester.tap(healthChip);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Medical Checkup'), findsWidgets);
    // A documents reminder should no longer be a priority.
    expect(find.text('Passport Renewal'), findsNothing);
  });

  testWidgets('View All opens the grouped full-list screen', (tester) async {
    await _pumpReminders(tester);

    await tester.tap(find.text('View All Reminders'));
    await tester.pumpAndSettle();

    // The dedicated All Reminders screen with its grouped list.
    expect(find.text('All Reminders'), findsOneWidget);
    expect(find.text('Today'), findsWidgets); // a time-bucket header
    expect(find.text('Passport Renewal'), findsWidgets);
  });
}
