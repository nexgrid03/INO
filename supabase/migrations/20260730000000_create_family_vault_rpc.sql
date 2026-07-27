-- ============================================================================
-- INO — create_family_vault() RPC (fixes 42501 on vault creation)
-- ----------------------------------------------------------------------------
-- ROOT CAUSE of "new row violates row-level security policy for family_vaults"
-- (42501): the client INSERT sends owner_auth_user_id from the app's cached
-- currentUser.id, and the INSERT policy checks `owner_auth_user_id = auth.uid()`.
-- If the value sent ever differs from the server's auth.uid() — a stale/cached
-- user id, an account switch, or a token whose auth.uid() resolves to NULL —
-- the WITH CHECK fails and the insert is rejected. A client can't reliably
-- guarantee the two match.
--
-- FIX: create vaults through a SECURITY DEFINER function that stamps the owner
-- from the SERVER's own auth.uid() and never trusts a client-supplied id (the
-- same pattern already used by create_custom_wallet). The function bypasses the
-- table's RLS (definer), so the WITH CHECK can't reject it; it still refuses to
-- run when there is no authenticated user, so security is preserved. The
-- existing AFTER-INSERT trigger add_owner_membership still runs and adds the
-- creator as the 'owner' member.
--
-- Idempotent + production-safe. Requires 20260728 (family_vaults) applied first.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

begin;

create or replace function public.create_family_vault(p_name text)
  returns public.family_vaults
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.family_vaults;
begin
  -- No valid session → auth.uid() is null. Fail with a clear, catchable error
  -- instead of a cryptic RLS rejection.
  if v_uid is null then
    raise exception 'You must be signed in to create a vault'
      using errcode = '28000';   -- invalid_authorization_specification
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'A vault name is required' using errcode = '22023';
  end if;

  -- Owner is ALWAYS the server-verified caller — never a client-sent value.
  insert into public.family_vaults (name, owner_auth_user_id)
  values (trim(p_name), v_uid)
  returning * into v_row;   -- add_owner_membership trigger adds the owner member

  return v_row;
end;
$$;

revoke all on function public.create_family_vault(text) from public;
grant execute on function public.create_family_vault(text) to authenticated;

notify pgrst, 'reload schema';

commit;

-- Verify (as a signed-in user; returns the new row and auto-creates the owner
-- membership):
--   select * from public.create_family_vault('Test Vault');
--   select role from public.vault_members
--    where vault_id = (select id from public.family_vaults order by created_at desc limit 1)
--      and auth_user_id = auth.uid();   -- expect 'owner'
