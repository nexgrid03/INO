import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/local_collection_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// A minimal store so the shared machinery can be exercised without Supabase.
class _Rec {
  const _Rec(this.id, this.name);
  final String id;
  final String name;
}

class _FakeStore extends LocalCollectionStore<_Rec> {
  @override
  String get storageKey => 'test_records';
  @override
  String get syncTable => 'w_test_wallet';
  @override
  Map<String, dynamic> encode(_Rec i) => {'id': i.id, 'name': i.name};
  @override
  _Rec decode(Map<String, dynamic> j) =>
      _Rec(j['id'] as String, j['name'] as String);
  @override
  String idOf(_Rec i) => i.id;
}

void main() {
  group('missingColumnOf — naming the column the database lacks', () {
    test('PostgREST PGRST204 (schema cache)', () {
      // The exact message a partially-migrated w_property_wallet produces, and
      // the reason every property insert failed while the app looked fine.
      final e = PostgrestException(
        message: "Could not find the 'reminder_date' column of "
            "'w_property_wallet' in the schema cache",
        code: 'PGRST204',
      );
      expect(LocalCollectionStore.missingColumnOf(e), 'reminder_date');
    });

    test('Postgres 42703 (undefined column)', () {
      final e = PostgrestException(
        message:
            'column "consent" of relation "w_property_wallet" does not exist',
        code: '42703',
      );
      expect(LocalCollectionStore.missingColumnOf(e), 'consent');
    });

    test('anything else is not a missing column', () {
      // Critically: an RLS refusal must NOT be mistaken for a schema gap, or
      // the retry would strip real columns trying to satisfy a policy error.
      expect(
        LocalCollectionStore.missingColumnOf(PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        )),
        isNull,
      );
      expect(
        LocalCollectionStore.missingColumnOf(PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        )),
        isNull,
      );
      expect(LocalCollectionStore.missingColumnOf(Exception('offline')), isNull);
    });

    test('a malformed message does not produce a bogus column name', () {
      expect(
        LocalCollectionStore.missingColumnOf(
            PostgrestException(message: 'no quotes here', code: 'PGRST204')),
        isNull,
      );
      expect(
        LocalCollectionStore.missingColumnOf(
            PostgrestException(message: "''", code: 'PGRST204')),
        isNull,
      );
    });
  });

  group('LocalCollectionStore — a refused save is not a silent one', () {
    test('isServerId separates a synced record from a device-local one', () {
      expect(
        LocalCollectionStore.isServerId(
            '3f2504e0-4f89-11d3-9a0c-0305e82c3301'),
        isTrue,
      );
      // What newId() mints. A record still carrying one of these has never been
      // accepted by the server — which is what pendingCount counts.
      expect(LocalCollectionStore.isServerId('prop_1757000000000_0'), isFalse);
    });

    test('pendingCount reports records the server never accepted', () {
      final store = _FakeStore();
      store.items.addAll(const [
        _Rec('3f2504e0-4f89-11d3-9a0c-0305e82c3301', 'synced'),
        _Rec('prop_1757000000000_0', 'local only'),
        _Rec('prop_1757000000001_1', 'local only too'),
      ]);
      expect(store.pendingCount, 2);
    });

    test('lastSyncError starts clean', () {
      expect(_FakeStore().lastSyncError.value, isNull);
    });
  });
}
