-- ============================================================================
-- INO Migration: 20260904030000_harden_notifications_privacy.sql
--
-- Privacy & Compliance Hardening:
-- 1. Create `user_consents` table for auditing Terms, Privacy, and Notification consent.
-- 2. Update `purge_push_log()` function to enforce a 30-day retention policy.
-- 3. Add `purge_notification_outbox()` retention cleanup function.
-- ============================================================================

begin;

set local search_path = public, extensions;

-- 1. Consent Audit Trail Table
create table if not exists public.user_consents (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  consent_type  text not null check (consent_type in ('terms_and_privacy', 'push_notifications')),
  version       text not null default '1.0',
  accepted_at   timestamptz not null default now(),
  platform      text
);

comment on table public.user_consents is
  'Audit trail of user consent records (Terms of Service, Privacy Policy, Push Notifications).';

create index if not exists user_consents_user_idx
  on public.user_consents (user_id, accepted_at desc);

alter table public.user_consents enable row level security;

drop policy if exists "user_consents: owner reads own" on public.user_consents;
drop policy if exists "user_consents: owner inserts own" on public.user_consents;

create policy "user_consents: owner reads own" on public.user_consents
  for select using (user_id = auth.uid());

create policy "user_consents: owner inserts own" on public.user_consents
  for insert with check (user_id = auth.uid());

-- 2. Update push log retention to 30 days
create or replace function public.purge_push_log()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with gone as (
    delete from public.push_log
    where delivered_at < now() - interval '30 days'
    returning 1
  )
  select count(*) into v_count from gone;
  return v_count;
end;
$$;

revoke all on function public.purge_push_log() from public;
grant execute on function public.purge_push_log() to service_role;

-- 3. Retention policy for sent notification_outbox entries (30 days)
create or replace function public.purge_notification_outbox()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with gone as (
    delete from public.notification_outbox
    where sent_at is not null and created_at < now() - interval '30 days'
    returning 1
  )
  select count(*) into v_count from gone;
  return v_count;
end;
$$;

revoke all on function public.purge_notification_outbox() from public;
grant execute on function public.purge_notification_outbox() to service_role;

notify pgrst, 'reload schema';

commit;
