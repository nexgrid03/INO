import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  testWidgets('Reminders Dashboard renders its command-center sections',
      (tester) async {
    // Tall canvas so every off-screen sliver child is laid out.
    tester.view.physicalSize = const Size(1200, 7000);
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
    // Repo's 260ms delayed load + entrance animations.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(tester.takeException(), isNull);

    // Header + all four summary cards.
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text("Today's Reminders"), findsOneWidget);
    expect(find.text('Upcoming This Week'), findsOneWidget);
    expect(find.text('Expiring Soon'), findsOneWidget);
    expect(find.text('Completed This Month'), findsOneWidget);

    // Filters, priorities, timeline, calendar, quick actions, completed.
    expect(find.text('All'), findsOneWidget);
    expect(find.text("Today's Priorities"), findsOneWidget);
    expect(find.text('Upcoming Events'), findsOneWidget);
    expect(find.text('Month View'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Recently Completed'), findsOneWidget);

    // Real sample data surfaces. "Passport Renewal" is due today, so it appears
    // both as a priority and in the calendar's today list.
    expect(find.text('Passport Renewal'), findsWidgets);
    expect(find.text('Insurance Premium Paid'), findsOneWidget); // completed
  });

  testWidgets('Filtering by a category narrows the reminders', (tester) async {
    // Wide canvas so the "Health" chip is visible without horizontal scroll.
    tester.view.physicalSize = const Size(2400, 9000);
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
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1200));

    // Tap the "Health" filter chip (first match; a quick-action tile also reads
    // "Health") → only health reminders remain anywhere.
    final healthChip = find.text('Health').first;
    await tester.ensureVisible(healthChip);
    await tester.tap(healthChip);
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Medical Checkup'), findsWidgets);
    // A documents reminder should no longer appear (filtered everywhere).
    expect(find.text('Passport Renewal'), findsNothing);
  });
}
