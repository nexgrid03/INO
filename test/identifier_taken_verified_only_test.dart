import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String fix;
  late String accountExists;

  setUpAll(() {
    fix = File(
      'supabase/migrations/20261119173600_identifier_taken_verified_auth_only.sql',
    ).readAsStringSync();
    accountExists = File(
      'supabase/migrations/20260907130000_single_account_identity.sql',
    ).readAsStringSync();
  });

  String live(String sql) => sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  String functionBody(String sql) {
    final start = sql.indexOf('create or replace function public.identifier_taken');
    final end = sql.indexOf(r'$$;', start);
    return sql.substring(start, end);
  }

  test('verified email is registered only through account_exists', () {
    final body = functionBody(fix);
    expect(body, contains('return public.account_exists(p_identifier)'));
    expect(accountExists, contains('email_confirmed_at is not null'));
    expect(body.contains('public.users'), isFalse);
  });

  test('verified phone is registered only through account_exists', () {
    expect(accountExists, contains('phone_confirmed_at is not null'));
    expect(
      functionBody(fix),
      contains('return public.account_exists(p_identifier)'),
    );
  });

  test('an unverified profile phone is not an independent match', () {
    final body = functionBody(fix);
    expect(body.contains('from public.users'), isFalse);
    expect(body.contains('u.phone'), isFalse);
  });

  test('an unverified profile email is not an independent match', () {
    final body = functionBody(fix);
    expect(body.contains('from public.users'), isFalse);
    expect(body.contains('u.email'), isFalse);
  });

  test('an identifier with no confirmed Auth owner is not taken', () {
    final body = functionBody(fix);
    expect(body, isNot(contains('return true')));
    expect(body, contains('account_exists'));
  });

  test('signature, security, and grants are unchanged', () {
    expect(fix, contains(
      'create or replace function public.identifier_taken(p_identifier text)',
    ));
    expect(fix, contains('returns boolean'));
    expect(fix, contains('security definer'));
    expect(fix, contains('set search_path = public, auth, pg_temp'));
    expect(
      fix,
      contains(
        'revoke all on function public.identifier_taken(text) from public',
      ),
    );
    expect(
      fix,
      contains(
        'grant execute on function public.identifier_taken(text) to anon, authenticated',
      ),
    );
    expect(live(fix).toLowerCase().contains('grant execute'), isTrue);
    expect(live(fix).toLowerCase().contains('service_role'), isFalse);
  });

  test('the correction deletes nothing and does not alter account_exists', () {
    final sql = live(fix).toLowerCase();
    expect(sql.contains('delete from'), isFalse);
    expect(sql.contains('drop table'), isFalse);
    expect(sql.contains('truncate'), isFalse);
    expect(sql.contains('account_exists(p_identifier text)'), isFalse);
    expect(sql.contains('create or replace function public.account_exists'), isFalse);
  });
}
