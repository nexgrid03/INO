import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/reminder_store.dart';
import 'package:inoapp/models/reminder_models.dart';
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

// Wide canvas so the horizontally-scrolling filter chips all lay out. Pumps the
// screen and advances time so the store's async load completes (the screen's
// initState kicks it off — we must NOT await the load ourselves, since its
// Future.delayed only fires when the test clock is pumped).
Future<void> _pump(WidgetTester tester,
    {Size size = const Size(2400, 7000)}) async {
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
  await tester.pump(const Duration(milliseconds: 400)); // repo load completes
  await tester.pump(const Duration(milliseconds: 600)); // entrance animations
}

Reminder _reminder(
  String id,
  String title,
  ReminderCategory category,
  int dayOffset,
) =>
    Reminder(
      id: id,
      title: title,
      subtitle: 'test',
      category: category,
      priority: ReminderPriority.important,
      date: dateOnly(DateTime.now()).add(Duration(days: dayOffset)),
    );

void main() {
  // Each test hydrates the shared store fresh for isolation.
  setUp(() => ReminderStore.instance.reset());

  testWidgets('Empty by default: shows the placeholder, no dummy data',
      (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);

    // The empty-state placeholder is shown.
    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.text('Create Reminder'), findsOneWidget);

    // None of the old seeded/dummy reminders exist anymore.
    expect(find.text('Passport Renewal'), findsNothing);
    expect(find.text('Medical Checkup'), findsNothing);
  });

  testWidgets('A created reminder surfaces in Today\'s Priorities',
      (tester) async {
    await _pump(tester);

    // Add a reminder after the (empty) load; the store notifies and rebuilds.
    ReminderStore.instance
        .add(_reminder('t1', 'Passport Renewal', ReminderCategory.documents, 0));
    await tester.pump(); // rebuild from notifyListeners
    await tester.pump(const Duration(milliseconds: 600)); // entrance animations

    expect(tester.takeException(), isNull);
    expect(find.text('No reminders yet'), findsNothing);
    expect(find.text("Today's Priorities"), findsOneWidget);
    expect(find.text('Passport Renewal'), findsWidgets);
  });

  testWidgets('Filtering by a category narrows the priorities', (tester) async {
    await _pump(tester);

    ReminderStore.instance
        .add(_reminder('t1', 'Passport Renewal', ReminderCategory.documents, 0));
    ReminderStore.instance
        .add(_reminder('t2', 'Medical Checkup', ReminderCategory.health, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The chip renders above the cards, so `.first` is the filter chip.
    final healthChip = find.text('Health').first;
    await tester.ensureVisible(healthChip);
    await tester.tap(healthChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Medical Checkup'), findsWidgets);
    // A documents reminder should no longer be a priority.
    expect(find.text('Passport Renewal'), findsNothing);
  });
}
