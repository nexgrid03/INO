-- ============================================================================
-- INO — Fix PGRST202 "Could not find the function public.invite_to_vault(...)"
-- ONE idempotent script: diagnose → recreate-if-missing → grant → reload → verify.
-- Backend only. No Flutter changes. Safe to run multiple times.
-- Run in the SQL editor of the project the app connects to (ref: ilfzppryyojoponkomrw).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (1)(2)(3) DIAGNOSE — current schema, existence, and authenticated EXECUTE.
--   to_regprocedure() returns NULL (never errors) when the function is absent.
-- ----------------------------------------------------------------------------
do $$
declare
  v_oid    regprocedure := to_regprocedure('public.invite_to_vault(uuid,text,text,text)');
  v_schema text;
  v_auth   boolean;
begin
  if v_oid is null then
    raise notice 'DIAGNOSE: invite_to_vault(uuid,text,text,text) NOT FOUND — will recreate.';
  else
    select n.nspname into v_schema
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.oid = v_oid;
    v_auth := has_function_privilege('authenticated', v_oid, 'EXECUTE');
    raise notice 'DIAGNOSE: found % in schema "%", authenticated EXECUTE = %',
                 v_oid, v_schema, v_auth;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- (7) RECREATE ONLY IF MISSING. (If it already exists it is left untouched.)
--     Nested dollar-quoting: $do$ (block) / $body$ (DDL text) / $fn$ (fn body).
--     Depends on helpers/tables from the base migration; they already exist in
--     your project (the function itself exists), so this branch is a safety net.
-- ----------------------------------------------------------------------------
do $do$
begin
  if to_regprocedure('public.invite_to_vault(uuid,text,text,text)') is null then
    execute $body$
create function public.invite_to_vault(
  p_vault uuid, p_role text, p_email text default null, p_phone text default null)
  returns public.vault_invitations
  language plpgsql security definer set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_email text := nullif(lower(trim(p_email)), '');
  v_phone text := nullif(trim(p_phone), '');
  v_vault_name text; v_inviter text; v_target_uid uuid; v_row public.vault_invitations;
begin
  if v_uid is null then raise exception 'You must be signed in' using errcode='28000'; end if;
  if not public.is_vault_admin(p_vault) then
    raise exception 'Only an owner or admin can invite members' using errcode='42501'; end if;
  if p_role not in ('admin','editor','viewer') then
    raise exception 'Invalid role (owner cannot be invited)' using errcode='22023'; end if;
  if v_email is null and v_phone is null then
    raise exception 'Provide an email or phone number' using errcode='22023'; end if;
  if (v_email is not null and v_email = lower(coalesce(public.ino_current_email(), '')))
     or (v_phone is not null and v_phone = coalesce(public.ino_current_phone(), '')) then
    raise exception 'You can''t invite yourself' using errcode='22023'; end if;
  select u.auth_user_id into v_target_uid from public.users u
   where (v_email is not null and lower(u.email) = v_email)
      or (v_phone is not null and u.phone = v_phone) limit 1;
  if v_target_uid is not null and exists (
       select 1 from public.vault_members m
        where m.vault_id = p_vault and m.auth_user_id = v_target_uid) then
    raise exception 'That person is already a member of this vault' using errcode='23505'; end if;
  if exists (select 1 from public.vault_invitations i
        where i.vault_id = p_vault and i.status='pending'
          and ((v_email is not null and lower(i.email)=v_email)
            or (v_phone is not null and i.phone=v_phone))) then
    raise exception 'There is already a pending invitation for that contact' using errcode='23505'; end if;
  select name into v_vault_name from public.family_vaults where id = p_vault;
  select full_name into v_inviter from public.users where auth_user_id = v_uid;
  insert into public.vault_invitations
    (vault_id, invited_by, role, email, phone, status, vault_name, invited_by_name)
  values
    (p_vault, v_uid, p_role, v_email, v_phone, 'pending',
     coalesce(v_vault_name,'Family Vault'), v_inviter)
  returning * into v_row;
  return v_row;
end;
$fn$;
    $body$;
    raise notice 'invite_to_vault was missing — recreated.';
  else
    raise notice 'invite_to_vault already exists — left as-is.';
  end if;
end
$do$;

-- ----------------------------------------------------------------------------
-- (4)(5) GRANT EXECUTE (idempotent). authenticated is required; anon is safe
--        (the function raises "You must be signed in" when auth.uid() is null).
-- ----------------------------------------------------------------------------
grant execute on function public.invite_to_vault(uuid,text,text,text) to authenticated;
grant execute on function public.invite_to_vault(uuid,text,text,text) to anon;

-- ----------------------------------------------------------------------------
-- (6) Force PostgREST to rebuild its schema cache so the RPC becomes callable.
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;

-- ----------------------------------------------------------------------------
-- (8) FINAL VERIFICATION — signature, schema, EXECUTE grants, proacl.
--     Expect: 1 row, schema = public, both *_execute = true.
-- ----------------------------------------------------------------------------
select
  p.oid::regprocedure                                        as function_signature,
  n.nspname                                                  as schema,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')  as authenticated_execute,
  has_function_privilege('anon',          p.oid, 'EXECUTE')  as anon_execute,
  p.proacl                                                   as proacl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname = 'invite_to_vault'
  and n.nspname = 'public';
