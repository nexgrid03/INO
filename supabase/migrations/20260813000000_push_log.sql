-- ============================================================================
-- INO - Push delivery log
-- ----------------------------------------------------------------------------
-- `notification_outbox` is a QUEUE: rows arrive, get sent, and are purged after
-- 30 days. That makes it the wrong place to answer "what did we send this user
-- last month, and did it actually arrive?" — and it never sees reminders at
-- all, because send-reminder-push delivers straight from `public.reminders`.
--
-- This table is the AUDIT: one durable row per notification actually attempted,
-- from BOTH senders, recording how many devices it targeted, how many took it,
-- and how long it sat between being raised and being delivered.
--
-- Queue vs log is a deliberate split. The queue must stay small and hot so the
-- every-two-minutes drain is a cheap indexed scan; the log can grow, be indexed
-- for reporting, and outlive the thing it describes.
--
-- Idempotent - safe to re-run. Core Postgres only.
-- ============================================================================

create table if not exists public.push_log (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid references auth.users (id) on delete cascade,

  -- Which sender produced it: 'reminder' | 'doc.expiry' | 'card.expiry' |
  -- 'security.*' | 'vault.invite'. Same vocabulary as notification_outbox.kind
  -- so the two can be read together.
  kind          text not null,

  -- What the user actually saw. Kept because "a notification was sent" is
  -- rarely the question — "what did it say" is.
  title         text,
  body          text,

  -- Fan-out result. targeted 3 / delivered 0 is the signature of dead tokens;
  -- targeted 0 means the user had no registered device at all.
  devices_targeted   integer not null default 0,
  devices_delivered  integer not null default 0,

  -- When the underlying event happened (a reminder falling due, a sign-in),
  -- versus when FCM finally accepted it. The gap is the real latency, and it is
  -- the number that tells you whether the 2-minute drain is keeping up.
  queued_at     timestamptz,
  delivered_at  timestamptz not null default now(),

  -- Last FCM error, when nothing got through.
  error         text
);

comment on table public.push_log is
  'Durable audit of every push notification attempted, by both senders. notification_outbox is the transient queue; this is the permanent record.';

create index if not exists push_log_user_idx
  on public.push_log (auth_user_id, delivered_at desc);
create index if not exists push_log_kind_idx
  on public.push_log (kind, delivered_at desc);
create index if not exists push_log_delivered_idx
  on public.push_log (delivered_at desc);

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
-- Titles carry real user data — document names, the last four digits of a card.
-- A user may read their own history; only the service role (the senders) writes.
alter table public.push_log enable row level security;

drop policy if exists "push_log: owner reads own" on public.push_log;
create policy "push_log: owner reads own" on public.push_log
  for select using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- A readable view for operators
-- ----------------------------------------------------------------------------
-- Answers the two questions you actually ask of a log: did it land, and how
-- long did it take. `security_invoker` keeps each user's RLS applied when a
-- signed-in client reads it, while the service role still sees everything.
create or replace view public.push_activity
with (security_invoker = on) as
select
  l.id,
  l.auth_user_id,
  l.kind,
  l.title,
  l.devices_targeted,
  l.devices_delivered,
  case
    when l.devices_delivered > 0                            then 'delivered'
    when l.devices_targeted  = 0                            then 'no device registered'
    else                                                         'failed'
  end                                                        as status,
  l.queued_at,
  l.delivered_at,
  -- Seconds between the event being raised and FCM accepting it. Null for
  -- reminders, which are found and sent in the same pass.
  case
    when l.queued_at is null then null
    else round(extract(epoch from (l.delivered_at - l.queued_at)))
  end                                                        as latency_seconds,
  l.error
from public.push_log l;

comment on view public.push_activity is
  'Human-readable push history: what was sent, to how many devices, whether it landed, and how long it took.';

grant select on public.push_activity to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Retention
-- ----------------------------------------------------------------------------
-- Long enough to investigate a complaint ("I never got my passport reminder"),
-- short enough that the table does not grow without bound.
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
    where delivered_at < now() - interval '180 days'
    returning 1
  )
  select count(*) into v_count from gone;
  return v_count;
end;
$$;

revoke all on function public.purge_push_log() from public;
grant execute on function public.purge_push_log() to service_role;
