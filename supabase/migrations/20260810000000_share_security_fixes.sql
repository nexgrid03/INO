-- ============================================================================
-- INO Migration: 20260810000000_share_security_fixes.sql
--
-- Two findings from the 9 Aug 2026 live API audit:
--   1. create_processed_share fails with "function digest(text, unknown) does
--      not exist" (SQLSTATE 42883).
--   2. peek_view_once_share is executable by a normal authenticated user.
-- ============================================================================

begin;

-- The migration session needs the same path the fixed function will use, or the
-- verification block below fails for the very reason it is checking for.
set local search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. create_processed_share: resolve digest() again.
--
-- ROOT CAUSE IS NOT THE ARGUMENT TYPES. pgcrypto ships both digest(text, text)
-- and digest(bytea, text), and Postgres resolves the 'sha256' unknown literal
-- to text without help - so casting the password to bytea would only change the
-- error to "function digest(bytea, unknown) does not exist".
--
-- The real problem is name resolution. Supabase installs pgcrypto into the
-- `extensions` schema, and this function is SECURITY DEFINER with
-- `set search_path = public`, so `digest` is simply not on the path inside the
-- function body. `create extension if not exists pgcrypto` at the top of the
-- original migration is a no-op on Supabase for exactly this reason: the
-- extension already exists, just not in public.
--
-- Fix: put `extensions` on the function's search_path. Listing both schemas
-- keeps this correct whether pgcrypto lives in `extensions` (Supabase) or in
-- `public` (a plain self-hosted Postgres).
--
-- search_path stays explicit rather than being dropped: a SECURITY DEFINER
-- function with a mutable search_path is a privilege-escalation vector, which
-- is why it was pinned in the first place.
-- ---------------------------------------------------------------------------
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
      else encode(digest(p_password, 'sha256'), 'hex')
    end,
    'active',
    now() + make_interval(secs => p_ttl_seconds)
  )
  returning * into v_row;

  return v_row;
end;
$$;

-- `create or replace function` re-grants EXECUTE to PUBLIC, and on Supabase any
-- ALTER DEFAULT PRIVILEGES rule re-grants to `authenticated` as well. Restate
-- the intended grants so replacing the function cannot widen access.
revoke all on function public.create_processed_share(
  text[], text[], text[], integer, boolean, text
) from public;
grant execute on function public.create_processed_share(
  text[], text[], text[], integer, boolean, text
) to authenticated;

-- Fail loudly at migration time rather than at the first user share.
do $check$
begin
  perform encode(digest('probe', 'sha256'), 'hex');
exception when undefined_function then
  raise exception
    'pgcrypto digest() is still unresolvable. Install it with: '
    'create extension if not exists pgcrypto with schema extensions;';
end
$check$;

-- ---------------------------------------------------------------------------
-- 2. View-once RPCs: close them to normal authenticated users.
--
-- 20260735000000 already did `revoke all ... from public` and granted only
-- service_role, which reads as correct - but the audit still executed
-- peek_view_once_share as a signed-in demo user, and that is consistent with
-- how Supabase provisions a project: an ALTER DEFAULT PRIVILEGES rule grants
-- EXECUTE on new functions in `public` to `authenticated` at CREATE time.
-- That is an EXPLICIT grant to the `authenticated` role, and revoking from
-- PUBLIC does not remove it - PUBLIC and `authenticated` are different
-- grantees. So the revoke was necessary but not sufficient.
--
-- These three must only ever be reached through the share Edge Function, which
-- holds the service-role key:
--     client → share Edge Function → RPC → database
-- Direct client access would let a signed-in user enumerate or burn other
-- people's one-time links by guessing tokens, bypassing the Edge Function's
-- rate limiting and audit trail entirely.
--
-- create_view_once_share is deliberately NOT revoked: the owner mints their own
-- link from the app, and it is scoped to auth.uid() internally.
-- ---------------------------------------------------------------------------
revoke execute on function public.peek_view_once_share(text)
  from authenticated, anon;
revoke execute on function public.claim_view_once_share(text, text)
  from authenticated, anon;
revoke execute on function public.resolve_view_once_file(text, text)
  from authenticated, anon;
revoke execute on function public.purge_expired_view_once_shares()
  from authenticated, anon;

-- Restate the intended grantee so the end state is unambiguous.
grant execute on function public.peek_view_once_share(text)         to service_role;
grant execute on function public.claim_view_once_share(text, text)  to service_role;
grant execute on function public.resolve_view_once_file(text, text) to service_role;
grant execute on function public.purge_expired_view_once_shares()   to service_role;

-- Same exposure, same reasoning: the processed-share resolver is an Edge
-- Function concern, not a client one. Guarded so this migration still applies
-- cleanly on a database where that function was never created.
do $vo$
begin
  execute 'revoke execute on function public.resolve_view_once_share(text, text) '
          'from authenticated, anon';
exception when undefined_function then
  null;  -- not present in this schema version; nothing to lock down
end
$vo$;

-- Reload PostgREST so the changed grants take effect immediately.
notify pgrst, 'reload schema';

commit;
