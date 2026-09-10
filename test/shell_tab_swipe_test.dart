// The shell's destinations swipe. These pin the two things that are easy to
// get wrong and invisible in a screenshot:
//
//  * the swipe set skips the centre "+" (bottom-bar slot 2 is a menu, not a
//    page), so a swipe from Wallet must land on Reminders — not on a blank
//    page, and not back on Wallet; and
//  * a tap on a NON-ADJACENT tab must not apply the destinations it passes
//    through. PageView.onPageChanged fires for those, and without the
//    _navTarget gate the nav highlight flips through them en route.
//
// Driving the real MainShell would drag in Supabase, so these exercise the same
// pager contract against stand-in pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bottom-bar slots that are real destinations. Slot 2 is the centre "+".
const List<int> kPageOrder = [0, 1, 3, 4];

/// A minimal stand-in for the shell's pager, carrying the same contract.
class _Pager extends StatefulWidget {
  const _Pager({super.key, required this.onTabApplied});

  final ValueChanged<int> onTabApplied;

  @override
  State<_Pager> createState() => _PagerState();
}

class _PagerState extends State<_Pager> {
  int _index = 0;
  int? _navTarget;
  late final PageController _pager = PageController();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void goToTab(int tab) {
    final pos = kPageOrder.indexOf(tab);
    if (pos < 0) return;
    if (_index != tab) setState(() => _index = tab);
    if (!_pager.hasClients) return;
    final current = _pager.page?.round() ?? 0;
    if (pos == current) return;
    _navTarget = tab;
    if ((pos - current).abs() > 1) {
      _pager.jumpToPage(pos > current ? pos - 1 : pos + 1);
    }
    _pager
        .animateToPage(
          pos,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (mounted && _navTarget == tab) _navTarget = null;
        });
  }

  void _onPageChanged(int pos) {
    if (pos < 0 || pos >= kPageOrder.length) return;
    final tab = kPageOrder[pos];
    if (_navTarget != null) {
      if (tab != _navTarget) return;
      _navTarget = null;
    }
    if (_index != tab) setState(() => _index = tab);
    widget.onTabApplied(tab);
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pager,
      onPageChanged: _onPageChanged,
      itemCount: kPageOrder.length,
      itemBuilder: (context, pos) => Center(
        child: Text('tab-${kPageOrder[pos]}', textDirection: TextDirection.ltr),
      ),
    );
  }
}

void main() {
  testWidgets('swiping from Wallet lands on Reminders, skipping the "+"',
      (tester) async {
    final applied = <int>[];
    final key = GlobalKey<_PagerState>();
    await tester.pumpWidget(
      MaterialApp(home: _Pager(key: key, onTabApplied: applied.add)),
    );

    await tester.pumpAndSettle();

    key.currentState!.goToTab(1); // Wallet
    await tester.pumpAndSettle();
    expect(find.text('tab-1'), findsOneWidget);

    // Drag left: the next destination in bottom-bar order is Reminders (3).
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('tab-3'), findsOneWidget);
    expect(applied.last, 3);
  });

  testWidgets('a swipe back returns to the previous destination',
      (tester) async {
    final applied = <int>[];
    final key = GlobalKey<_PagerState>();
    await tester.pumpWidget(
      MaterialApp(home: _Pager(key: key, onTabApplied: applied.add)),
    );

    await tester.pumpAndSettle();

    key.currentState!.goToTab(3);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('tab-1'), findsOneWidget);
    expect(applied.last, 1);
  });

  testWidgets('tapping a far tab applies only the destination, not the tabs '
      'it passes', (tester) async {
    final applied = <int>[];
    final key = GlobalKey<_PagerState>();
    await tester.pumpWidget(
      MaterialApp(home: _Pager(key: key, onTabApplied: applied.add)),
    );
    await tester.pumpAndSettle();

    // Home (pos 0) → Profile (pos 3). Wallet and Reminders sit between them and
    // must never be applied.
    key.currentState!.goToTab(4);
    await tester.pumpAndSettle();

    expect(find.text('tab-4'), findsOneWidget);
    expect(applied, [4], reason: 'passed-through tabs leaked through the gate');
  });
}
