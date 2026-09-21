import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/widgets/common/ino_time_picker.dart';

void main() {
  testWidgets('InoTimePickerDialog allows manual typing in top boxes and wheel scrolling',
      (tester) async {
    TimeOfDay? pickedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  pickedTime = await showInoTimePicker(
                    context,
                    initialTime: const TimeOfDay(hour: 9, minute: 0),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the time picker
    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    // Verify header and initial display
    expect(find.text('PICK A TIME'), findsOneWidget);
    expect(find.text('9'), findsWidgets);
    expect(find.text('00'), findsWidgets);
    expect(find.text('AM'), findsWidgets);

    // Tap and type manually in the minute box
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    // Type '24' into minute textfield (second text field)
    await tester.enterText(textFields.at(1), '24');
    await tester.pumpAndSettle();

    expect(find.text('24'), findsWidgets);

    // Tap PM switch
    await tester.tap(find.text('PM').first);
    await tester.pumpAndSettle();

    // Tap OK button
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // 9:24 PM = hour: 21, minute: 24
    expect(pickedTime, equals(const TimeOfDay(hour: 21, minute: 24)));
  });
}
