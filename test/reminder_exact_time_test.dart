// Reminder times must land on the exact minute.
//
// Flutter's Material time picker opens on the dial by default, and the dial
// rounds the minute hand to the nearest 5 the moment the finger lifts
// (_Dial._getTimeForTheta(roundMinutes: true)). That is why reminders could
// only ever be set to 10:25 or 10:30 and never 10:26 — nothing in INO was
// rounding anything, the picker simply could not express it.
//
// The fix is to open on keyboard entry instead, so these pin the entry mode and
// prove an odd minute survives the round trip.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TimeOfDay?> _openPicker(
  WidgetTester tester, {
  required TimePickerEntryMode mode,
}) async {
  TimeOfDay? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 10, minute: 0),
                  initialEntryMode: mode,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('keyboard entry accepts a minute that is not a multiple of five',
      (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 10, minute: 0),
                    initialEntryMode: TimePickerEntryMode.input,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Two text fields: hour, then minute.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.at(0), '10');
    await tester.enterText(fields.at(1), '26');
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 10, minute: 26),
        reason: '26 must survive — the whole point of the entry mode');
  });

  testWidgets('the picker opens on keyboard entry, not the dial',
      (tester) async {
    await _openPicker(tester, mode: TimePickerEntryMode.input);
    // Entry mode is identifiable by its two text fields; the dial has none.
    expect(find.byType(TextField), findsNWidgets(2),
        reason: 'a dial-first picker would show no text fields, and its minute '
            'hand snaps to the nearest 5 on release');
  });
}
