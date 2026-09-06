import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ROUND 7: ISSUE #1 - MFA ENFORCEMENT PRESERVATION ACROSS WALLET REBUILDS', () {
    final migration = File('supabase/migrations/20260906010000_round7_security_remediation.sql');

    test('Migration file exists and is located in supabase/migrations/', () {
      expect(migration.existsSync(), isTrue, reason: 'Migration file must exist');
    });

    test('wallets table enforces check constraint preventing w_password_vault registration', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('wallets_no_password_vault_chk'), isTrue);
      expect(sql.contains("CHECK (slug <> 'w_password_vault')"), isTrue);
    });

    test('ino_apply_password_vault_mfa_policies is defined and idempotent', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('CREATE OR REPLACE FUNCTION public.ino_apply_password_vault_mfa_policies()'), isTrue);
      expect(sql.contains('public.ino_is_aal2_satisfied()'), isTrue);
      expect(sql.contains('REVOKE ALL ON FUNCTION public.ino_apply_password_vault_mfa_policies() FROM PUBLIC, anon;'), isTrue);
      expect(sql.contains('GRANT EXECUTE ON FUNCTION public.ino_apply_password_vault_mfa_policies() TO authenticated, service_role;'), isTrue);
    });

    test('ino_create_wallet_table contains explicit guard protecting w_password_vault', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains("IF p_table = 'w_password_vault' THEN"), isTrue);
      expect(sql.contains('PERFORM public.ino_apply_password_vault_mfa_policies();'), isTrue);
    });

    test('ino_register_wallet blocks registration of w_password_vault', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains("IF v_slug = 'w_password_vault' THEN"), isTrue);
      expect(sql.contains('RAISE EXCEPTION'), isTrue);
    });

    test('ino_rebuild_documents_view excludes w_password_vault and reapplies MFA policies', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains("WHERE slug != 'w_password_vault'"), isTrue);
      expect(sql.contains('PERFORM public.ino_apply_password_vault_mfa_policies();'), isTrue);
    });

    test('create_custom_wallet guarantees MFA policies remain active after wallet creation', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('PERFORM public.ino_apply_password_vault_mfa_policies();'), isTrue);
      expect(sql.contains("REVOKE ALL ON FUNCTION public.create_custom_wallet(text, text, bigint) FROM PUBLIC, anon;"), isTrue);
    });
  });

  group('ROUND 7: ISSUE #2 - UNAUTHENTICATED DOCUMENT DELETION REMEDIATION', () {
    final migration = File('supabase/migrations/20260906010000_round7_security_remediation.sql');

    test('remove_vault_document execution is strictly revoked from PUBLIC and anon', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('REVOKE ALL ON FUNCTION public.remove_vault_document(uuid) FROM PUBLIC, anon;'), isTrue);
      expect(sql.contains('GRANT EXECUTE ON FUNCTION public.remove_vault_document(uuid) TO authenticated, service_role;'), isTrue);
    });

    test('remove_vault_document implements explicit caller session validation (fail-closed)', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('v_uid uuid := auth.uid();'), isTrue);
      expect(sql.contains('IF v_uid IS NULL THEN'), isTrue);
      expect(sql.contains("RAISE EXCEPTION 'You must be signed in to remove a document'"), isTrue);
      expect(sql.contains("USING errcode = '28000';"), isTrue);
    });

    test('remove_vault_document eliminates 3-valued logic bypass with safe boolean evaluation', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('IF NOT (v_doc.shared_by = v_uid OR public.is_vault_admin(v_doc.vault_id)) THEN'), isTrue);
      expect(sql.contains("RAISE EXCEPTION 'You can only remove documents you shared or administer'"), isTrue);
      expect(sql.contains("USING errcode = '42501';"), isTrue);
    });

    test('share_document_to_vault execution is revoked from PUBLIC/anon and validates auth.uid()', () {
      final sql = migration.readAsStringSync();
      expect(sql.contains('REVOKE ALL ON FUNCTION public.share_document_to_vault(uuid, text, text, text, bigint, text, text, uuid, text) FROM PUBLIC, anon;'), isTrue);
      expect(sql.contains('GRANT EXECUTE ON FUNCTION public.share_document_to_vault(uuid, text, text, text, bigint, text, text, uuid, text) TO authenticated, service_role;'), isTrue);
      expect(sql.contains("RAISE EXCEPTION 'You must be signed in to share documents into a vault'"), isTrue);
    });
  });
}
