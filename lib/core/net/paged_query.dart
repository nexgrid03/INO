import 'dart:developer' as developer;

import 'net_guard.dart';

/// Fetches every row of a list query in bounded pages, instead of one request
/// capped with `.limit()`.
///
/// A single `.limit(500)` bounds the payload but silently loses data: an
/// account with 600 documents shows 500 and never learns the rest exist. That
/// is a correctness bug, not a performance one, and it is exactly what a volume
/// test surfaces. Paging keeps every individual response small (so no single
/// huge payload) while still returning the complete set.
///
/// [page] must run the query for the inclusive row range `[from, to]` -
/// typically `builder.range(from, to)`. Order the query by a **deterministic**
/// key (add a unique tiebreaker such as `id` after `created_at`), otherwise
/// rows can repeat or vanish between pages when sort keys tie.
///
/// [hardMax] is a runaway backstop, not a product limit. Hitting it is logged
/// rather than swallowed, so truncation is always visible in diagnostics.
Future<List<T>> fetchAllPaged<T>(
  Future<List<T>> Function(int from, int to) page, {
  int pageSize = NetGuard.pageSize,
  int hardMax = NetGuard.hardMaxRows,
  String label = 'query',
}) async {
  final all = <T>[];
  var from = 0;
  while (true) {
    final rows = await page(from, from + pageSize - 1);
    all.addAll(rows);
    // A short page means the server had nothing more to give - the normal exit.
    if (rows.length < pageSize) break;
    from += pageSize;
    if (all.length >= hardMax) {
      developer.log(
        '$label: stopped at $hardMax rows (hard cap). Some rows were not '
        'loaded - this account is far past the expected size.',
        name: 'paging',
      );
      break;
    }
  }
  return all;
}
