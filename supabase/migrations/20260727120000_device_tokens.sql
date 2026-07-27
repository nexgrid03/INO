-- ============================================================================
-- INO - Reminder push notifications: device token registry
-- ----------------------------------------------------------------------------
-- Firebase Cloud Messaging is used ONLY as the delivery pipe. The reminders
-- stay in `public.reminders` and the "who is due today" decision is made by the
-- `send-reminder-push` Edge Function; this table is the address book that maps
-- a signed-in user to the devices they should be reached on.
--
-- Follows the same owner-scoped RLS model as reminders / notes / expenses
-- (see 20260710000000_user_data_isolation.sql):
--   1. an `auth_user_id uuid` owner column (default auth.uid()),
--   2. Row Level Security ENABLED, and
--   3. owner-only policies.
--
-- Idempotent - safe to run multiple times. Uses ONLY core Postgres.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- device_tokens - one row per (device install), holding its current FCM
-- registration token. Written by lib/services/push_service.dart.
--
-- The FCM token is the PRIMARY KEY, not a surrogate id. A token identifies an
-- app install, and the same install must never appear twice - otherwise a user
-- who signs out and back in accumulates rows and receives one duplicate
-- notification per stale row. Making the token itself the key lets the client
-- do a plain `upsert` and lets an account switch simply re-stamp the owner.
-- ----------------------------------------------------------------------------
create table if not exists public.device_tokens (
  token         text primary key,
  auth_user_id  uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  platform      text not null default 'android',   -- android | ios | web
  updated_at    timestamptz not null default now()
);

comment on table public.device_tokens is
  'FCM registration tokens per device install. Owner-scoped by auth_user_id via RLS. Rows are deleted on sign-out by the client and pruned by the sender when FCM reports the token is dead.';

-- The sender's hot path: "give me every token for these user ids".
create index if not exists device_tokens_auth_user_id_idx
  on public.device_tokens (auth_user_id);

-- ----------------------------------------------------------------------------
-- Row Level Security. With RLS on and NO policy the table denies all access;
-- the owner-only policies below are what let a user manage their own devices.
--
-- Note the Edge Function reads this table with the SERVICE ROLE key, which
-- bypasses RLS by design - that is how one cron run can fan out to every user.
-- ----------------------------------------------------------------------------
alter table public.device_tokens enable row level security;

drop policy if exists "device_tokens: owner reads own"   on public.device_tokens;
drop policy if exists "device_tokens: owner inserts own" on public.device_tokens;
drop policy if exists "device_tokens: owner updates own" on public.device_tokens;
drop policy if exists "device_tokens: owner deletes own" on public.device_tokens;

create policy "device_tokens: owner reads own" on public.device_tokens
  for select using (auth_user_id = auth.uid());
create policy "device_tokens: owner inserts own" on public.device_tokens
  for insert with check (auth_user_id = auth.uid());
-- UPDATE is what re-stamps a token onto a new account after a device changes
-- hands. `using` must NOT require prior ownership here, or the upsert would
-- fail for exactly that case and the phone would keep notifying the old owner.
create policy "device_tokens: owner updates own" on public.device_tokens
  for update using (true) with check (auth_user_id = auth.uid());
create policy "device_tokens: owner deletes own" on public.device_tokens
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- reminders.last_push_sent_on - idempotency guard for the sender.
--
-- The cron can legitimately run more than once for the same calendar day (a
-- manual re-run, a retry after a partial failure, a schedule change). Without a
-- marker every one of those re-notifies the whole user base. The sender stamps
-- this after a successful send and skips rows already stamped with today.
-- ----------------------------------------------------------------------------
alter table public.reminders
  add column if not exists last_push_sent_on date;

comment on column public.reminders.last_push_sent_on is
  'Date this reminder last triggered a push. Prevents duplicate sends when the cron runs twice in a day.';

-- Partial index: the sender only ever scans ACTIVE reminders by due date.
create index if not exists reminders_due_push_idx
  on public.reminders (due_date)
  where completed = false;
