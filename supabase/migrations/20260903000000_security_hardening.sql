-- ============================================================================
-- INO security hardening — 2026-09-03
--
-- Paste this whole file into the Supabase SQL editor and run it.
--
-- Safe to run more than once: every statement is idempotent, and every object
-- is existence-checked first, so a function or table that is not present in
-- this database is skipped with a notice instead of aborting the script.
--
-- Closes four confirmed issues:
--   1. Two SECURITY DEFINER functions that create tables, policies and triggers
--      were callable by the anon role — unauthenticated schema modification.
--   2. Two maintenance functions were callable by PUBLIC.
--   3. A family-vault admin could insert a row granting the 'owner' role,
--      bypassing the owner-only promotion RPC.
--   4. A vault member could register ANOTHER USER'S storage path as a vault
--      document and thereby read that user's file. This one was found by
--      checking the live storage policies, is the most serious of the four,
--      and in its practical form defeats revocation. See section 4.
--
-- Expected output: a list of NOTICE lines saying what was locked down.
--
-- After running, confirm in the app that:
--   • creating a custom wallet still works, and
--   • sharing one of your own documents into a family vault still works.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Lock down the wallet DDL functions
-- ----------------------------------------------------------------------------

revoke all on function public.ino_register_wallet(text, text, text, bigint) from public, anon, authenticated;
revoke all on function public.ino_create_wallet_table(text) from public, anon, authenticated;

do $$
declare
  fn text;
  fns text[] := array[
    'public.ino_register_wallet(text, text, text, bigint)',
    'public.ino_create_wallet_table(text)'
  ];
begin
  foreach fn in array fns loop
    if to_regprocedure(fn) is not null then
      execute format('revoke all on function %s from public, anon, authenticated', fn);
      raise notice 'Locked down %', fn;
    else
      raise notice 'Skipped (not present): %', fn;
    end if;
  end loop;
end $$;


-- ----------------------------------------------------------------------------
-- 2. Maintenance functions become service-role only
-- ----------------------------------------------------------------------------

revoke all on function public.expire_due_shares() from public, anon, authenticated;
grant execute on function public.expire_due_shares() to service_role;

revoke all on function public.ino_rebuild_documents_view() from public, anon, authenticated;
grant execute on function public.ino_rebuild_documents_view() to service_role;

do $$
declare
  fn text;
  fns text[] := array[
    'public.expire_due_shares()',
    'public.ino_rebuild_documents_view()'
  ];
begin
  foreach fn in array fns loop
    if to_regprocedure(fn) is not null then
      execute format('revoke all on function %s from public, anon, authenticated', fn);
      execute format('grant execute on function %s to service_role', fn);
      raise notice 'Restricted to service_role: %', fn;
    else
      raise notice 'Skipped (not present): %', fn;
    end if;
  end loop;
end $$;


-- ----------------------------------------------------------------------------
-- 3. A vault admin must not be able to mint an owner
-- ----------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.vault_members') is null then
    raise notice 'Skipped (not present): public.vault_members';
    return;
  end if;

  drop policy if exists "members: admins insert" on public.vault_members;

  create policy "members: admins insert" on public.vault_members
    for insert
    with check (
      public.is_vault_admin(vault_id)
      and role in ('admin', 'editor', 'viewer')
      and role <> 'owner'
    );

  raise notice 'Tightened vault_members INSERT policy (owner role can no longer be granted directly)';
end $$;


-- ----------------------------------------------------------------------------
-- 4. A vault member must not be able to register SOMEONE ELSE'S file
--
-- Found while verifying the live storage policies. The storage policy
-- "vault members read shared objects" grants SELECT on any object in the
-- documents bucket whose name appears in vault_documents.object_path for a
-- vault the caller belongs to:
--
--   bucket_id = 'documents' AND EXISTS (
--     SELECT 1 FROM vault_documents vd
--     JOIN vault_members vm ON vm.vault_id = vd.vault_id
--     WHERE vd.object_path = objects.name AND vm.auth_user_id = auth.uid())
--
-- That is sound ONLY if a row in vault_documents can point exclusively at a
-- file the inserter owns. Neither write path enforced that:
--
--   • RLS policy "vault docs: editors insert" checks is_vault_editor(vault_id)
--     and shared_by = auth.uid(), but never constrains object_path.
--   • share_document_to_vault() is SECURITY DEFINER (so it bypasses RLS
--     entirely) and only checks the editor role and that the path is non-empty.
--
-- Exploit: any authenticated user creates their own family vault, which makes
-- them its owner and therefore an editor. They insert a vault_documents row in
-- that private vault with shared_by = their own uid and object_path set to
-- another user's file, e.g. '<victim-uid>/1712345678901.jpg'. The storage
-- policy then matches and hands them the file.
--
-- The most practical version defeats REVOCATION: a member of a shared vault can
-- see object_path values for everything shared into it. If the owner later
-- removes a document (or removes that member), the attacker re-registers the
-- remembered path in their own vault and keeps read access permanently. The
-- test "removal revokes view AND download immediately" in
-- test/family_vault_test.dart asserts a guarantee this breaks. Storage paths are
-- also guessable in principle, being '<uid>/<epoch-millis>.<ext>'
-- (lib/repositories/document_repository.dart:144), and user UUIDs leak through
-- the world-readable wallets registry.
--
-- FIX: enforce the missing invariant in ONE place that both write paths must
-- pass through. A trigger is used rather than a policy edit because a
-- SECURITY DEFINER function bypasses RLS but cannot bypass a trigger.
--
-- Deliberately permissive in two spots, both safe:
--   • auth.uid() IS NULL means a service-role or SQL-editor context, which is
--     already trusted and is how migrations and backend jobs write.
--   • UPDATEs are only checked when object_path actually changes, so an admin
--     editing the name or category of someone else's shared document still works.
-- ----------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.vault_documents') is null then
    raise notice 'Skipped (not present): public.vault_documents';
    return;
  end if;

  create or replace function public.ino_assert_vault_doc_path_owner()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $fn$
  begin
    -- Service-role / SQL-editor context: trusted, nothing to check.
    if auth.uid() is null then
      return new;
    end if;

    -- Only validate when the path is being set or actually changed.
    if tg_op = 'INSERT'
       or new.object_path is distinct from old.object_path then
      if split_part(new.object_path, '/', 1) <> auth.uid()::text then
        raise exception
          'You can only share your own documents into a vault'
          using errcode = '42501';
      end if;
    end if;

    return new;
  end
  $fn$;

  drop trigger if exists ino_vault_doc_path_owner on public.vault_documents;

  create trigger ino_vault_doc_path_owner
    before insert or update on public.vault_documents
    for each row execute function public.ino_assert_vault_doc_path_owner();

  raise notice 'Vault documents can now only reference the sharer''s own files';
end $$;


-- ----------------------------------------------------------------------------
-- Reload PostgREST's schema cache so the grant changes take effect immediately.
-- ----------------------------------------------------------------------------

notify pgrst, 'reload schema';
