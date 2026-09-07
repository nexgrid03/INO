import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Account Deletion Hardening & Schema Audit', () {
    late File migrationFile;
    late String migrationSql;

    setUpAll(() {
      migrationFile = File('supabase/migrations/20260907120000_harden_account_deletion.sql');
      expect(migrationFile.existsSync(), isTrue,
          reason: 'Hardened account deletion migration must exist');
      migrationSql = migrationFile.readAsStringSync();
    });

    test('Migration strictly fixes production bug on public.expenses (auth_user_id)', () {
      // Must NOT reference WHERE user_id on public.expenses
      expect(migrationSql.contains('DELETE FROM public.expenses WHERE user_id'), isFalse,
          reason: 'public.expenses does not have user_id; this caused the production crash');
      
      // Must reference WHERE auth_user_id
      expect(migrationSql.contains('DELETE FROM public.expenses WHERE auth_user_id = v_uid'), isTrue,
          reason: 'public.expenses must be queried via auth_user_id');
    });

    test('Migration strictly fixes vault_members ordering (created_at instead of joined_at)', () {
      // Must NOT reference joined_at in SQL statements
      final sqlStatementsOnly = migrationSql.replaceAll(RegExp(r'--.*'), '');
      expect(sqlStatementsOnly.contains('joined_at'), isFalse,
          reason: 'vault_members does not have joined_at; must not be referenced');

      // Must reference created_at ASC
      expect(migrationSql.contains('created_at ASC'), isTrue,
          reason: 'vault_members handover must order by created_at');
    });

    test('Migration strictly fixes public.wallets primary key reference (slug instead of id)', () {
      // Must NOT reference id on public.wallets
      expect(migrationSql.contains('DELETE FROM public.wallets WHERE id'), isFalse,
          reason: 'public.wallets primary key is slug, not id');
      expect(migrationSql.contains('SELECT slug, id FROM public.wallets'), isFalse,
          reason: 'public.wallets does not have id column');

      // Must reference slug
      expect(migrationSql.contains('DELETE FROM public.wallets WHERE slug = r.slug'), isTrue,
          reason: 'public.wallets must delete by primary key slug');
    });

    test('Defensive protection: all optional tables guarded with to_regclass checks', () {
      final guardedTables = [
        'public.users',
        'public.reminders',
        'public.expenses',
        'public.notes',
        'public.tax_documents',
        'public.vault_keys',
        'public.vault_meta',
        'public.device_tokens',
        'public.user_sessions',
        'public.user_consents',
        'public.user_qr_codes',
        'public.offline_documents',
        'public.w_identity_wallet',
        'public.w_document_wallet',
        'public.w_property_wallet',
        'public.w_insurance_wallet',
        'public.w_health_wallet',
        'public.w_investment_wallet',
        'public.w_banking_wallet',
        'public.w_cards_wallet',
        'public.w_password_vault',
        'public.w_ino_share_cache',
        'public.wallets',
        'public.share_views',
        'public.share_downloads',
        'public.document_shares',
        'public.view_once_shares',
        'public.family_vaults',
        'public.vault_members',
        'public.vault_documents',
        'public.vault_join_requests',
        'public.vault_invite_audit_logs',
        'public.vault_audit_log',
        'public.vault_notification_events',
        'public.vault_invitations',
        'public.notification_outbox',
        'public.push_log',
      ];

      for (final table in guardedTables) {
        expect(
          migrationSql.contains("to_regclass('$table') IS NOT NULL"),
          isTrue,
          reason: 'Table $table must be guarded by to_regclass check to prevent runtime crashes if table is dropped',
        );
      }
    });

    test('Defensive protection: individual table blocks are isolated with exception handlers', () {
      // Sub-block exception isolation ensures a schema change in an optional table never aborts deletion
      expect(migrationSql.contains('EXCEPTION WHEN OTHERS THEN'), isTrue,
          reason: 'Sub-blocks must catch and isolate table-level exceptions');
      expect(migrationSql.contains("RAISE WARNING 'expenses cleanup notice: %'"), isTrue);
      expect(migrationSql.contains("RAISE WARNING 'reminders cleanup notice: %'"), isTrue);
      expect(migrationSql.contains("RAISE WARNING 'users cleanup notice: %'"), isTrue);
    });

    test('Schema audit: delete_account() contains zero forbidden/non-existent columns', () {
      // Disallow known mismatched column patterns
      final invalidPatterns = [
        'expenses WHERE user_id',
        'wallets WHERE id =',
        'vault_members.joined_at',
        'vault_members WHERE joined_at',
        'ORDER BY joined_at',
      ];

      for (final pattern in invalidPatterns) {
        expect(migrationSql.contains(pattern), isFalse,
            reason: 'delete_account() must not reference invalid column pattern: $pattern');
      }
    });

    test('Final step strictly purges user from auth.users (triggering cascade)', () {
      expect(migrationSql.contains('DELETE FROM auth.users WHERE id = v_uid;'), isTrue,
          reason: 'Final step must permanently remove row from auth.users');
    });

    test('Permissions strictly granted to authenticated and service_role, revoked from public', () {
      expect(migrationSql.contains('REVOKE EXECUTE ON FUNCTION public.delete_account() FROM PUBLIC;'), isTrue);
      expect(migrationSql.contains('GRANT EXECUTE ON FUNCTION public.delete_account() TO authenticated, service_role;'), isTrue);
    });
  });
}
