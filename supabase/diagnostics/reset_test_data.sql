-- ============================================================================
-- INO — Safe Database Reset for Testing
-- ----------------------------------------------------------------------------
-- Objective:
-- Wipes all user test data, auth users, sessions, uploaded storage objects,
-- and dynamically created test custom wallets, WHILE PRESERVING:
--   1. All database table schemas, columns, constraints, foreign keys, and indexes.
--   2. All Row Level Security (RLS) policies and permissions.
--   3. All SQL functions, procedures, triggers, and migrations.
--   4. The built-in wallet registrations in `public.wallets` (Identity, Document,
--      Property, Insurance, Health, Investment, Banking, Cards, Password Vault).
--   5. The `public.documents` view and storage buckets.
--
-- How to run:
--   Copy and paste this entire script into your Supabase Dashboard SQL Editor
--   and click "Run".
-- ============================================================================

DO $$
DECLARE
  r RECORD;
BEGIN
  -- --------------------------------------------------------------------------
  -- 1. Clean Supabase Storage objects (deletes all uploaded test files/attachments)
  -- --------------------------------------------------------------------------
  IF to_regclass('storage.objects') IS NOT NULL THEN
    BEGIN
      DELETE FROM storage.objects;
      RAISE NOTICE 'Cleared storage.objects';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Notice on storage.objects cleanup: %', SQLERRM;
    END;
  END IF;

  -- --------------------------------------------------------------------------
  -- 2. Clean all Wallet tables and custom test wallets
  -- --------------------------------------------------------------------------
  IF to_regclass('public.wallets') IS NOT NULL THEN
    -- Delete all rows from every registered wallet table (built-in and custom)
    FOR r IN (
      SELECT slug FROM public.wallets
      WHERE to_regclass('public.' || slug) IS NOT NULL
    ) LOOP
      BEGIN
        EXECUTE format('DELETE FROM public.%I', r.slug);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Notice on % cleanup: %', r.slug, SQLERRM;
      END;
    END LOOP;

    -- Drop any custom wallet tables created dynamically during testing
    FOR r IN (
      SELECT slug FROM public.wallets
      WHERE kind = 'custom' AND to_regclass('public.' || slug) IS NOT NULL
    ) LOOP
      BEGIN
        EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', r.slug);
        RAISE NOTICE 'Dropped custom wallet table %', r.slug;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Notice dropping custom table %: %', r.slug, SQLERRM;
      END;
    END LOOP;

    -- Remove custom wallet entries from registry, keep built-in wallets
    DELETE FROM public.wallets WHERE kind = 'custom';

    -- Reset creator reference on built-in wallets to prevent foreign key errors
    UPDATE public.wallets SET created_by = NULL;
  END IF;

  -- Clean password vault / share cache if created as separate tables
  IF to_regclass('public.w_password_vault') IS NOT NULL THEN
    DELETE FROM public.w_password_vault;
  END IF;
  IF to_regclass('public.w_ino_share_cache') IS NOT NULL THEN
    DELETE FROM public.w_ino_share_cache;
  END IF;

  -- --------------------------------------------------------------------------
  -- 3. Core User Tables
  -- --------------------------------------------------------------------------
  IF to_regclass('public.reminders') IS NOT NULL THEN
    DELETE FROM public.reminders;
  END IF;
  IF to_regclass('public.expenses') IS NOT NULL THEN
    DELETE FROM public.expenses;
  END IF;
  IF to_regclass('public.notes') IS NOT NULL THEN
    DELETE FROM public.notes;
  END IF;
  IF to_regclass('public.tax_documents') IS NOT NULL THEN
    DELETE FROM public.tax_documents;
  END IF;
  IF to_regclass('public.user_qr_codes') IS NOT NULL THEN
    DELETE FROM public.user_qr_codes;
  END IF;
  IF to_regclass('public.user_consents') IS NOT NULL THEN
    DELETE FROM public.user_consents;
  END IF;
  IF to_regclass('public.user_sessions') IS NOT NULL THEN
    DELETE FROM public.user_sessions;
  END IF;
  IF to_regclass('public.offline_documents') IS NOT NULL THEN
    DELETE FROM public.offline_documents;
  END IF;
  IF to_regclass('public.device_tokens') IS NOT NULL THEN
    DELETE FROM public.device_tokens;
  END IF;
  IF to_regclass('public.vault_keys') IS NOT NULL THEN
    DELETE FROM public.vault_keys;
  END IF;
  IF to_regclass('public.vault_meta') IS NOT NULL THEN
    DELETE FROM public.vault_meta;
  END IF;
  IF to_regclass('public.vault_items') IS NOT NULL THEN
    DELETE FROM public.vault_items;
  END IF;

  -- --------------------------------------------------------------------------
  -- 4. Sharing & Analytics Tables
  -- --------------------------------------------------------------------------
  IF to_regclass('public.share_views') IS NOT NULL THEN
    DELETE FROM public.share_views;
  END IF;
  IF to_regclass('public.share_downloads') IS NOT NULL THEN
    DELETE FROM public.share_downloads;
  END IF;
  IF to_regclass('public.share_rate_limits') IS NOT NULL THEN
    DELETE FROM public.share_rate_limits;
  END IF;
  IF to_regclass('public.view_once_shares') IS NOT NULL THEN
    DELETE FROM public.view_once_shares;
  END IF;
  IF to_regclass('public.document_shares') IS NOT NULL THEN
    DELETE FROM public.document_shares;
  END IF;

  -- --------------------------------------------------------------------------
  -- 5. Family Vault Tables
  -- --------------------------------------------------------------------------
  IF to_regclass('public.vault_documents') IS NOT NULL THEN
    DELETE FROM public.vault_documents;
  END IF;
  IF to_regclass('public.vault_join_requests') IS NOT NULL THEN
    DELETE FROM public.vault_join_requests;
  END IF;
  IF to_regclass('public.vault_invite_audit_logs') IS NOT NULL THEN
    DELETE FROM public.vault_invite_audit_logs;
  END IF;
  IF to_regclass('public.vault_audit_log') IS NOT NULL THEN
    DELETE FROM public.vault_audit_log;
  END IF;
  IF to_regclass('public.vault_notification_events') IS NOT NULL THEN
    DELETE FROM public.vault_notification_events;
  END IF;
  IF to_regclass('public.vault_invitations') IS NOT NULL THEN
    DELETE FROM public.vault_invitations;
  END IF;
  IF to_regclass('public.vault_members') IS NOT NULL THEN
    DELETE FROM public.vault_members;
  END IF;
  IF to_regclass('public.family_vaults') IS NOT NULL THEN
    DELETE FROM public.family_vaults;
  END IF;

  -- --------------------------------------------------------------------------
  -- 6. Notification Tables
  -- --------------------------------------------------------------------------
  IF to_regclass('public.notification_outbox') IS NOT NULL THEN
    DELETE FROM public.notification_outbox;
  END IF;
  IF to_regclass('public.push_log') IS NOT NULL THEN
    DELETE FROM public.push_log;
  END IF;

  -- --------------------------------------------------------------------------
  -- 7. Public Profile & Auth Schema Users
  -- --------------------------------------------------------------------------
  IF to_regclass('public.users') IS NOT NULL THEN
    DELETE FROM public.users;
  END IF;

  -- Deleting from auth.users automatically cascades to identities, sessions,
  -- refresh tokens, and MFA factors in the auth schema.
  DELETE FROM auth.users;

  -- --------------------------------------------------------------------------
  -- 8. Rebuild the documents view
  -- --------------------------------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'ino_rebuild_documents_view'
      AND pronamespace = 'public'::regnamespace
  ) THEN
    PERFORM public.ino_rebuild_documents_view();
  END IF;

  RAISE NOTICE 'Database reset finished: all rows and test data have been wiped.';
END $$;

-- ----------------------------------------------------------------------------
-- 9. Refresh PostgREST API schema cache
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

-- ----------------------------------------------------------------------------
-- 10. Verification query: returns row counts for all tables (should all be 0)
-- ----------------------------------------------------------------------------
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.reltuples::bigint AS approx_row_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'auth', 'storage')
  AND c.relkind = 'r'
  AND c.relname NOT IN (
    -- System schema metadata tables to ignore
    'schema_migrations', 'spatial_ref_sys', 'flow_state', 'saml_providers',
    'saml_relay_states', 'sso_providers', 'sso_domains', 'buckets'
  )
  AND (
    n.nspname = 'auth' AND c.relname = 'users'
    OR n.nspname = 'storage' AND c.relname = 'objects'
    OR n.nspname = 'public'
  )
ORDER BY schema_name, table_name;
