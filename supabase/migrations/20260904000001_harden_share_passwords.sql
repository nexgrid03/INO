-- ============================================================================
-- INO Migration: 20260904000001_harden_share_passwords.sql
--
-- Security Hardening:
-- 1. Hashes document share passwords using bcrypt (`crypt(p_password, gen_salt('bf'))`)
--    instead of plain SHA-256.
-- 2. Restricts function execute permissions strictly to `authenticated` role.
-- ============================================================================

begin;

create extension if not exists pgcrypto with schema extensions;

set local search_path = public, extensions;

-- Update create_processed_share to store bcrypt hashes using pgcrypto's crypt()
create or replace function public.create_processed_share(
  p_paths        text[],
  p_names        text[],
  p_mimes        text[],
  p_ttl_seconds  integer,
  p_view_only    boolean default false,
  p_password     text default null
)
returns public.document_shares
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.document_shares;
begin
  if v_uid is null then
    raise exception 'You must be signed in to share documents.';
  end if;
  if p_paths is null or array_length(p_paths, 1) is null then
    raise exception 'No files to share.';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds <= 0 then
    raise exception 'Invalid expiry duration.';
  end if;
  -- Defense-in-depth: every processed path must live under the caller's folder.
  if exists (
    select 1 from unnest(p_paths) as pth
    where pth not like v_uid::text || '/%'
  ) then
    raise exception 'Processed files must be under your own folder.';
  end if;

  insert into public.document_shares (
    owner_id, document_ids,
    processed_paths, processed_names, processed_mimes,
    view_only, password_hash, status, expires_at
  )
  values (
    v_uid, '{}',
    p_paths, p_names, p_mimes,
    coalesce(p_view_only, false),
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

revoke all on function public.create_processed_share(
  text[], text[], text[], integer, boolean, text
) from public;

grant execute on function public.create_processed_share(
  text[], text[], text[], integer, boolean, text
) to authenticated;

notify pgrst, 'reload schema';

commit;
