-- ============================================================================
-- INO Migration: 20260904070000_harden_document_share_rpc.sql
--
-- Security & System Alignment:
-- 1. Updates create_document_share RPC signature to accept optional p_is_view_only
--    and p_password arguments (matching client ShareRepository payload).
-- 2. Hashes p_password using bcrypt (pgcrypto crypt()) and sets view_only.
-- ============================================================================

begin;

create extension if not exists pgcrypto with schema extensions;

set local search_path = public, extensions;

-- Drop obsolete 2-argument signature to prevent signature ambiguity in PostgREST
drop function if exists public.create_document_share(uuid[], integer);

create or replace function public.create_document_share(
  p_document_ids  uuid[],
  p_ttl_seconds   integer,
  p_is_view_only  boolean default false,
  p_password      text default null
)
returns public.document_shares
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_owned integer;
  v_row   public.document_shares;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_document_ids is null or array_length(p_document_ids, 1) is null then
    raise exception 'Select at least one document to share';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds < 60 then
    raise exception 'Invalid expiry duration';
  end if;

  -- Every requested document must belong to the caller.
  select count(*) into v_owned
  from public.documents d
  where d.id = any (p_document_ids)
    and d.auth_user_id = v_uid;

  if v_owned <> array_length(p_document_ids, 1) then
    raise exception 'One or more documents are not yours to share';
  end if;

  insert into public.document_shares (
    owner_id, document_ids, view_only, password_hash, status, expires_at
  )
  values (
    v_uid,
    p_document_ids,
    coalesce(p_is_view_only, false),
    case
      when p_password is null or length(p_password) = 0 then null
      else crypt(p_password, gen_salt('bf'))
    end,
    'active',
    now() + make_interval(secs => p_ttl_seconds)
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.create_document_share(uuid[], integer, boolean, text) from public;
grant execute on function public.create_document_share(uuid[], integer, boolean, text) to authenticated;

notify pgrst, 'reload schema';

commit;
