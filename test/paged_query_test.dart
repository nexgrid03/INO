import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/net/paged_query.dart';

/// A fake table of [total] rows that records every range it was asked for, so
/// the tests can assert both the data AND the request pattern (a correct result
/// fetched with a pointless extra round trip is still a bug worth catching).
class _FakeTable {
  _FakeTable(this.total);

  final int total;
  final List<List<int>> requestedRanges = [];

  Future<List<int>> page(int from, int to) async {
    requestedRanges.add([from, to]);
    if (from >= total) return const [];
    final end = (to + 1) > total ? total : to + 1;
    return [for (var i = from; i < end; i++) i];
  }
}

void main() {
  group('fetchAllPaged', () {
    test('a single short page costs exactly one request', () async {
      final table = _FakeTable(7);
      final rows = await fetchAllPaged(table.page, pageSize: 10);

      expect(rows, hasLength(7));
      expect(table.requestedRanges, [
        [0, 9]
      ]);
    });

    test('an empty table returns nothing without looping', () async {
      final table = _FakeTable(0);
      final rows = await fetchAllPaged(table.page, pageSize: 10);

      expect(rows, isEmpty);
      expect(table.requestedRanges, hasLength(1));
    });

    test('walks every page and preserves order across page boundaries',
        () async {
      final table = _FakeTable(25);
      final rows = await fetchAllPaged(table.page, pageSize: 10);

      // The whole table arrives - this is the bug the cap used to cause: rows
      // past the limit silently never existed.
      expect(rows, List.generate(25, (i) => i));
      expect(table.requestedRanges, [
        [0, 9],
        [10, 19],
        [20, 29],
      ]);
    });

    test('a total that is an exact multiple needs one confirming request',
        () async {
      // The boundary case: 20 rows at pageSize 10 returns a FULL second page,
      // so the loop cannot know it is done without asking once more.
      final table = _FakeTable(20);
      final rows = await fetchAllPaged(table.page, pageSize: 10);

      expect(rows, hasLength(20));
      expect(table.requestedRanges, [
        [0, 9],
        [10, 19],
        [20, 29],
      ]);
    });

    test('stops at the hard cap instead of paging forever', () async {
      // A runaway table must terminate. The cap is a backstop, not a product
      // limit, so it is allowed to overshoot to the end of the current page.
      final table = _FakeTable(1000);
      final rows = await fetchAllPaged(table.page, pageSize: 10, hardMax: 35);

      expect(rows.length, greaterThanOrEqualTo(35));
      expect(rows.length, lessThan(1000));
      expect(table.requestedRanges.length, lessThan(10));
    });

    test('propagates a failure rather than returning a partial list', () async {
      // Silently returning page 1 when page 2 failed would look identical to a
      // small table - exactly the class of bug paging is meant to remove.
      var calls = 0;
      Future<List<int>> flaky(int from, int to) async {
        calls++;
        if (calls == 2) throw StateError('network died');
        return List.generate(10, (i) => from + i);
      }

      expect(
        () => fetchAllPaged(flaky, pageSize: 10),
        throwsA(isA<StateError>()),
      );
    });
  });
}
