-- ============================================================================
-- INO - Reminders: exact due TIME + fire-when-due push
-- ----------------------------------------------------------------------------
-- Until now a reminder carried only a DATE, and a daily 09:00 IST cron pushed
-- "due today / tomorrow / in 7 days". The app now requires a date AND a time
-- for every reminder, rings it on the device at that exact moment (local
-- scheduled notification), and the server backs that up with a push at the
-- same moment - nothing earlier, nothing later.
--
--   due_at       timestamptz  the exact instant (UTC on the wire; the client
--                             converts to/from the phone's local time)
--   notified_at  timestamptz  stamped by send-reminder-push once the due push
--                             has been delivered, so a per-minute cron can
--                             never send the same reminder twice
--
-- `due_date` stays (day-based queries, calendar, older rows) and is derived
-- from due_at when a writer omits it.
--
-- Idempotent - safe to re-run. Run with:  supabase db push   (or paste into
-- the SQL editor). Then re-deploy the function and switch the cron (see the
-- end of this file).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Columns
-- ----------------------------------------------------------------------------
alter table public.reminders
  add column if not exists due_at      timestamptz,
  add column if not exists notified_at timestamptz;

comment on column public.reminders.due_at is
  'Exact moment the reminder fires (timestamptz). Authoritative; due_date is the derived calendar day.';
comment on column public.reminders.notified_at is
  'When the due-time push was delivered. Null = not yet sent. Reset automatically when due_at changes.';

-- The client always sends both, but a writer that only knows due_at (older
-- app builds, SQL) must not be rejected - the trigger below fills due_date.
alter table public.reminders alter column due_date drop not null;

-- ----------------------------------------------------------------------------
-- 2. Backfill existing rows: date-only reminders fire at 09:00 IST, the hour
--    the old daily cron used to notify at, so nothing shifts for them.
-- ----------------------------------------------------------------------------
update public.reminders
   set due_at = ((due_date::text || ' 09:00')::timestamp at time zone 'Asia/Kolkata')
 where due_at is null and due_date is not null;

-- Anything already in the past has (by the old rules) been pushed. Stamp it so
-- the first per-minute run does not blast every stale row at once.
update public.reminders
   set notified_at = coalesce(notified_at, now())
 where completed = false and due_at is not null and due_at <= now();

-- ----------------------------------------------------------------------------
-- 3. Keep due_date / due_at / notified_at consistent on every write.
-- ----------------------------------------------------------------------------
create or replace function public.tg_reminder_due_sync()
  returns trigger language plpgsql as $$
begin
  if new.due_at is null and new.due_date is not null then
    new.due_at := ((new.due_date::text || ' 09:00')::timestamp at time zone 'Asia/Kolkata');
  end if;
  if new.due_date is null and new.due_at is not null then
    new.due_date := (new.due_at at time zone 'Asia/Kolkata')::date;
  end if;
  if new.due_at is null then
    raise exception 'A reminder needs a due date and time' using errcode = '22023';
  end if;
  -- Moving the due time re-arms the push; un-completing it does too.
  if tg_op = 'UPDATE' then
    if new.due_at is distinct from old.due_at then
      new.notified_at := null;
    end if;
    if old.completed and not new.completed and new.due_at > now() then
      new.notified_at := null;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_reminder_due_sync on public.reminders;
create trigger trg_reminder_due_sync
  before insert or update on public.reminders
  for each row execute function public.tg_reminder_due_sync();

-- ----------------------------------------------------------------------------
-- 4. The sender's hot path: "active, due, not yet notified", oldest first.
-- ----------------------------------------------------------------------------
create index if not exists reminders_due_at_pending_idx
  on public.reminders (due_at)
  where completed = false and notified_at is null;

-- The daily-lead index is no longer used by the sender; harmless to keep, but
-- dropping it saves writes on every insert.
drop index if exists public.reminders_due_push_idx;

notify pgrst, 'reload schema';

commit;

-- ============================================================================
-- AFTER APPLYING: deploy the sender and switch the schedule
-- ----------------------------------------------------------------------------
--   supabase functions deploy send-reminder-push
--
-- Then in the SQL editor (pg_cron + pg_net enabled under Database →
-- Extensions). Replace <project-ref> and <service-role-key>:
--
--   select cron.unschedule('reminder-push');          -- the old 09:00 daily job (ignore "not found")
--   select cron.schedule(
--     'reminder-push-due',
--     '* * * * *',                                     -- every minute
--     $$
--     select net.http_post(
--       url     := 'https://<project-ref>.supabase.co/functions/v1/send-reminder-push',
--       headers := '{"Authorization": "Bearer <service-role-key>", "Content-Type": "application/json"}'::jsonb
--     );
--     $$
--   );
--
-- Verify:   select jobname, schedule, active from cron.job;
--           select * from cron.job_run_details order by start_time desc limit 5;
-- Test:     create a reminder 2 minutes out in the app; within a minute of the
--           due time the function log shows {"ok":true,"reminders":1,"sent":1}
--           and public.reminders.notified_at is stamped.
-- ============================================================================
