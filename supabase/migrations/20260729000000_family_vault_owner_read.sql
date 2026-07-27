-- ============================================================================
-- INO — Family Vault: let the owner read their own vault (fixes create)
-- ----------------------------------------------------------------------------
-- ROOT CAUSE of "Couldn't create the vault":
--   createVault() runs  insert(...).select().single()  → an INSERT … RETURNING.
--   Postgres applies the family_vaults SELECT policy to the RETURNING row. That
--   policy was `using (is_vault_member(id))`, but the creator only becomes a
--   member via the AFTER-INSERT trigger `add_owner_membership`, which fires
--   AFTER the RETURNING row is computed. So at RETURNING time the creator is not
--   yet a member → the row is filtered out → PostgREST returns 0 rows →
--   `.single()` throws → the app shows the generic error.
--
-- FIX: the owner must be able to SELECT their own vault directly (which is also
--   correct on its own — the owner always owns the row). With the owner clause,
--   the RETURNING row passes the SELECT policy immediately, before the trigger
--   runs, so create() returns the row. Reads for non-owner members are
--   unchanged (still gated by membership).
--
-- Idempotent + production-safe. Run with:  supabase db push  (or paste into the
-- SQL editor).  Requires 20260728000000_family_vaults.sql to be applied first.
-- ============================================================================

begin;

drop policy if exists "vaults: members read" on public.family_vaults;

create policy "vaults: members read" on public.family_vaults
  for select using (
    owner_auth_user_id = auth.uid()      -- owner always reads own vault (RETURNING-safe)
    or public.is_vault_member(id)         -- and any member reads a vault they belong to
  );

notify pgrst, 'reload schema';

commit;

-- Verify:
--   select polname, pg_get_expr(polqual, polrelid) as using_expr
--     from pg_policy
--    where polrelid = 'public.family_vaults'::regclass and polcmd = 'r';
--   -- expect the USING expression to include: owner_auth_user_id = auth.uid()
