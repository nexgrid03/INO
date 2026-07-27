-- ============================================================================
-- INO — Backend health check (run in the Supabase SQL editor)
-- ----------------------------------------------------------------------------
-- Read-only. Answers, in order:
--   #1  Is `documents` a VIEW (why inserts fail) and do the per-wallet base
--       tables exist?
--   #2  Do the Family Vault tables + policies exist?
--   #3  Which module tables exist, and is RLS enabled on each?
-- Nothing here writes data.
-- ============================================================================

-- #1 — Is `public.documents` a table or a view?  (view => inserts must target
--      the per-wallet w_* base tables, which the current app already does.)
select 'documents object type' as check,
       table_type
  from information_schema.tables
 where table_schema = 'public' and table_name = 'documents';   -- expect: VIEW

-- The per-wallet BASE tables the app writes to (from 20260727). All should be
-- BASE TABLE. If any are missing, the 20260727 migration wasn't fully applied.
select table_name, table_type
  from information_schema.tables
 where table_schema = 'public' and table_name like 'w\_%'
 order by table_name;   -- expect w_identity_wallet, w_document_wallet, w_property_wallet,
                        --        w_insurance_wallet, w_health_wallet, w_investment_wallet,
                        --        w_banking_wallet, w_cards_wallet, w_password_vault,
                        --        w_ino_share_cache (all BASE TABLE)

-- The wallet registry the app reads to resolve slugs.
select slug, label, kind from public.wallets order by kind, slug;

-- #2 — Family Vault schema (from 20260728).
select table_name, table_type
  from information_schema.tables
 where table_schema = 'public' and table_name in ('family_vaults', 'vault_members')
 order by table_name;   -- expect BOTH as BASE TABLE

-- The SECURITY DEFINER helpers + owner trigger the RLS relies on.
select proname
  from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('is_vault_member', 'is_vault_admin', 'add_owner_membership');

-- The FK vault_members.vault_id -> family_vaults.id (PostgREST embed relies on
-- this; the app no longer needs it after the two-step query, but it should exist).
select conname, conrelid::regclass as on_table
  from pg_constraint
 where conname like '%vault_members%' and contype = 'f';

-- #3 — RLS status across every module table.  rls_enabled must be TRUE for all.
select c.relname as table, c.relrowsecurity as rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relkind = 'r'
   and c.relname in (
     'users', 'reminders', 'notes', 'expenses', 'tax_documents',
     'family_vaults', 'vault_members', 'document_shares',
     'w_identity_wallet', 'w_document_wallet', 'w_property_wallet',
     'w_insurance_wallet', 'w_health_wallet', 'w_investment_wallet',
     'w_banking_wallet', 'w_cards_wallet', 'w_password_vault'
   )
 order by c.relname;

-- Policy count per module table (0 with RLS on = table is fully locked -> reads
-- return empty / writes fail; that is itself a common "nothing loads" cause).
select tablename, count(*) as policies
  from pg_policies
 where schemaname = 'public'
 group by tablename
 order by tablename;
