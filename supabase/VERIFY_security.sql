-- ============================================================================
-- INO security verification — READ ONLY
--
-- Paste into the Supabase SQL editor and run. Changes nothing.
-- Run it AFTER 20260903000000_security_hardening.sql and paste the output back
-- to Claude, or read the "what you want to see" note under each query.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- QUERY 1 — THE IMPORTANT ONE. Storage folder isolation.
--
-- The per-user folder policy on the `documents` bucket exists only in this
-- dashboard, not in any migration, so it could not be audited from the source.
-- It is the single control stopping one user from reading another user's files.
--
-- WHAT YOU WANT TO SEE: every row whose policy touches the documents bucket has
-- a qual/with_check containing something equivalent to
--     (storage.foldername(name))[1] = auth.uid()::text
-- meaning each user is confined to their own <uid>/ folder.
--
-- RED FLAG: any policy on the documents bucket whose condition is just `true`,
-- or that has no auth.uid() reference at all. That means users can read each
-- other's documents, which is a critical exposure.
--
-- One EXPECTED exception: a family-vault policy that lets vault members read a
-- shared document living under the sharer's folder. That one is intentional.
-- ----------------------------------------------------------------------------

select
  policyname,
  cmd            as operation,
  roles,
  qual           as using_condition,
  with_check
from pg_policies
where schemaname = 'storage'
  and tablename  = 'objects'
order by policyname;


-- ----------------------------------------------------------------------------
-- QUERY 2 — Confirm the documents bucket is private.
--
-- WHAT YOU WANT TO SEE: public = false for 'documents'.
-- If it is true, every stored file is readable by anyone with the URL,
-- regardless of the policies above.
-- ----------------------------------------------------------------------------

select id, name, public, file_size_limit
from storage.buckets
order by name;


-- ----------------------------------------------------------------------------
-- QUERY 3 — Confirm the hardening migration actually applied.
--
-- WHAT YOU WANT TO SEE: for all four functions, anon_can_execute and
-- authenticated_can_execute are both false.
-- If any is still true, the revoke did not take effect.
-- ----------------------------------------------------------------------------

select
  p.proname                                                   as function_name,
  pg_get_function_identity_arguments(p.oid)                   as arguments,
  has_function_privilege('anon',          p.oid, 'EXECUTE')   as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')   as authenticated_can_execute,
  has_function_privilege('service_role',  p.oid, 'EXECUTE')   as service_role_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'ino_register_wallet',
    'ino_create_wallet_table',
    'expire_due_shares',
    'ino_rebuild_documents_view'
  )
order by p.proname;


-- ----------------------------------------------------------------------------
-- QUERY 4 — Confirm the vault_members INSERT policy was tightened.
--
-- WHAT YOU WANT TO SEE: the with_check for "members: admins insert" contains
-- a role restriction listing admin, editor and viewer — and NOT owner.
-- ----------------------------------------------------------------------------

select policyname, cmd as operation, with_check
from pg_policies
where schemaname = 'public'
  and tablename  = 'vault_members'
order by policyname;


-- ----------------------------------------------------------------------------
-- QUERY 5 — Any table with row-level security switched OFF.
--
-- WHAT YOU WANT TO SEE: zero rows. Every table holding user data must have RLS
-- enabled, or the anon key can read it outright.
-- ----------------------------------------------------------------------------

select c.relname as table_without_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and not c.relrowsecurity
order by c.relname;


-- ----------------------------------------------------------------------------
-- QUERY 6 — Any policy that grants access unconditionally.
--
-- WHAT YOU WANT TO SEE: as few rows as possible, and every row you can explain.
-- A `true` condition means the check is "anyone in this role", not "the owner".
--
-- KNOWN and already reported: the wallets registry SELECT is intentionally
-- broad because custom wallet tables are shared objects, and device_tokens
-- UPDATE uses true for the account hand-off path. Both are on the fix list.
-- Anything else appearing here is worth investigating.
-- ----------------------------------------------------------------------------

select tablename, policyname, cmd as operation, qual as using_condition
from pg_policies
where schemaname = 'public'
  and (qual = 'true' or with_check = 'true')
order by tablename, policyname;


-- ----------------------------------------------------------------------------
-- QUERY 7 — Does delete_account() exist yet?
--
-- WHAT YOU WANT TO SEE: right now, zero rows — it does not exist, which is why
-- "Delete Account" in the app leaves the auth user and roughly eighteen tables
-- intact. After the deletion fix is written and applied, this should return one
-- row with security_definer = true.
-- ----------------------------------------------------------------------------

select
  p.proname                                  as function_name,
  p.prosecdef                                as security_definer,
  pg_get_function_identity_arguments(p.oid)  as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'delete_account';
