-- ============================================================================
-- INO Migration: 20260904080000_share_security_hardening.sql
--
-- Security Hardening Pass:
-- 1. Legacy Password Cleanup: NULL all password_hash entries not starting with $2
--    (eliminates hash replay attack on legacy shares).
-- 2. Persistent Rate Limiting & Lockout: Create share_rate_limits table in Postgres
--    so brute-force tracking survives Edge Function cold starts and restarts.
-- 3. Password Lockout: 5 failed attempts locks the IP/token pair for 15 minutes.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Legacy Password Cleanup
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.document_shares') is not null then
    update public.document_shares
    set password_hash = null
    where password_hash is not null
      and password_hash not like '$2%';
  end if;

  if to_regclass('public.shares') is not null then
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'shares' and column_name = 'password_hash'
    ) then
      execute 'update public.shares set password_hash = null where password_hash is not null and password_hash not like ''$2%''';
    end if;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Persistent Share Rate Limits & Lockout Table
-- ----------------------------------------------------------------------------
create table if not exists public.share_rate_limits (
  id uuid primary key default gen_random_uuid(),
  ip text not null,
  token text not null,
  attempts integer not null default 0,
  last_attempt timestamptz not null default now(),
  lock_until timestamptz default null,
  created_at timestamptz not null default now(),
  constraint share_rate_limits_ip_token_unique unique (ip, token)
);

create index if not exists idx_share_rate_limits_ip_token
  on public.share_rate_limits (ip, token);

create index if not exists idx_share_rate_limits_lock_until
  on public.share_rate_limits (lock_until)
  where lock_until is not null;

alter table public.share_rate_limits enable row level security;

-- Rate limits are managed strictly server-side by the Edge Function via service_role
grant all on table public.share_rate_limits to service_role;

-- ----------------------------------------------------------------------------
-- 3. Atomic Lockout Functions
-- ----------------------------------------------------------------------------

-- Check whether the given IP and share token are currently locked out
create or replace function public.check_share_password_lock(
  p_ip text,
  p_token text
)
returns table (is_locked boolean, lock_until timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lock timestamptz;
begin
  select srl.lock_until into v_lock
  from public.share_rate_limits srl
  where srl.ip = p_ip and srl.token = p_token;

  if v_lock is not null and v_lock > now() then
    return query select true, v_lock;
  else
    return query select false, null::timestamptz;
  end if;
end;
$$;

-- Record a password attempt. If success: clear records.
-- If failure: increment attempts; if >= 5 attempts, lock for 15 minutes.
create or replace function public.record_share_password_attempt(
  p_ip text,
  p_token text,
  p_success boolean
)
returns table (is_locked boolean, attempts integer, lock_until timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_attempts integer;
  v_lock timestamptz := null;
begin
  if p_success then
    delete from public.share_rate_limits where ip = p_ip and token = p_token;
    return query select false, 0, null::timestamptz;
    return;
  end if;

  insert into public.share_rate_limits (ip, token, attempts, last_attempt, lock_until)
  values (p_ip, p_token, 1, now(), null)
  on conflict (ip, token) do update
  set attempts = share_rate_limits.attempts + 1,
      last_attempt = now(),
      lock_until = case
        when share_rate_limits.attempts + 1 >= 5 then now() + interval '15 minutes'
        else share_rate_limits.lock_until
      end
  returning share_rate_limits.attempts, share_rate_limits.lock_until
  into v_attempts, v_lock;

  return query select (v_lock is not null and v_lock > now()), v_attempts, v_lock;
end;
$$;

grant execute on function public.check_share_password_lock(text, text) to service_role;
grant execute on function public.record_share_password_attempt(text, text, boolean) to service_role;

commit;
