import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/widgets/common/liquid_glass.dart';

/// A form field living inside a glass card must keep its focus when a scroll
/// suspends backdrop blur. LiquidGlass used to wrap its child in a
/// BackdropFilter only while blur was on, so flipping blur reparented the
/// whole subtree: the TextField was rebuilt from scratch, focus was dropped,
/// and the on-screen keyboard opened and immediately closed — which is what
/// tapping a field does, since the auto-scroll that reveals it emits a
/// ScrollStartNotification.
void main() {
  testWidgets('a field inside glass keeps focus when scrolling drops blur',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        // Light theme + non-web is the only combination where LiquidGlass
        // actually mounts a BackdropFilter, so it is the only one that could
        // regress this way.
        theme: ThemeData.light(),
        home: Scaffold(
          body: GlassScrollListener(
            child: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 400),
                LiquidGlass(
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(16),
                  child: TextField(focusNode: focus),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );

    final element = tester.element(find.byType(TextField));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    // Drag the list: GlassScrollListener suspends blur for the gesture.
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pump();

    expect(focus.hasFocus, isTrue,
        reason: 'suspending blur must not rebuild the field from scratch');
    expect(identical(tester.element(find.byType(TextField)), element), isTrue,
        reason: 'the field element must survive the blur toggle');

    // …and when blur returns after the settle delay.
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(focus.hasFocus, isTrue);
    expect(identical(tester.element(find.byType(TextField)), element), isTrue);
  });
}
