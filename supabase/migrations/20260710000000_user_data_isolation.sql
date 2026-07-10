-- ============================================================================
-- INO — User Data Isolation (Row Level Security hardening)
-- ----------------------------------------------------------------------------
-- Fixes a data-isolation defect where one account could see another account's
-- data (reported for reminders). The app scopes every table by `auth_user_id`
-- (= auth.uid()) and relies on RLS to enforce it. The `reminders`, `documents`
-- and `users` tables were created outside version control (dashboard), so this
-- migration GUARANTEES, idempotently:
--
--   1. an `auth_user_id uuid` owner column (default auth.uid()),
--   2. Row Level Security ENABLED, and
--   3. owner-only policies: a user can only SELECT/INSERT/UPDATE/DELETE rows
--      whose auth_user_id equals their own auth.uid().
--
-- Safe to run multiple times. Uses ONLY core Postgres (no extensions).
-- Run with:  supabase db push   (or paste into the SQL editor).
--
-- NOTE on pre-existing rows: if a table already had rows with no auth_user_id,
-- this adds the column as NULL for those rows. Under the policies below a NULL
-- owner never equals auth.uid(), so such orphan rows become invisible to every
-- user (fail-closed) rather than leaking. Assign them an owner manually if any
-- legitimate rows are affected:  update public.reminders set auth_user_id = '<uid>' where auth_user_id is null;
-- ============================================================================

-- ----------------------------------------------------------------------------
-- reminders  (create the table if it doesn't exist; otherwise just ensure the
--             owner column exists). Columns mirror the Flutter model
--             (lib/models/reminder_models.dart: Reminder.toInsert / fromMap).
-- ----------------------------------------------------------------------------
create table if not exists public.reminders (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  title         text not null,
  subtitle      text not null default '',
  category      text not null default 'custom',
  priority      text not null default 'normal',
  due_date      date not null,
  completed     boolean not null default false,
  completed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.reminders is
  'Per-user life-event / due-date reminders. Owner-scoped by auth_user_id via RLS.';

-- If the table already existed without the owner column, add it (nullable, so
-- the ALTER can''t fail on existing rows) and (re)assert its default.
alter table public.reminders
  add column if not exists auth_user_id uuid
  references auth.users (id) on delete cascade;
alter table public.reminders
  alter column auth_user_id set default auth.uid();

create index if not exists reminders_auth_user_id_idx
  on public.reminders (auth_user_id);

-- ----------------------------------------------------------------------------
-- Ensure the owner column exists on the other user-owned tables too. (These
-- tables already exist and use auth_user_id; this is a no-op safety net.)
-- ----------------------------------------------------------------------------
alter table public.documents
  add column if not exists auth_user_id uuid
  references auth.users (id) on delete cascade;
alter table public.documents
  alter column auth_user_id set default auth.uid();

alter table public.users
  add column if not exists auth_user_id uuid
  references auth.users (id) on delete cascade;

-- ----------------------------------------------------------------------------
-- Enable Row Level Security everywhere. Enabling an already-enabled table is a
-- no-op. With RLS enabled and NO policy, a table denies all access — so the
-- policies below are what let authenticated users reach their OWN rows.
-- ----------------------------------------------------------------------------
alter table public.reminders enable row level security;
alter table public.documents enable row level security;
alter table public.users     enable row level security;

-- ----------------------------------------------------------------------------
-- reminders — owner-only policies.
-- ----------------------------------------------------------------------------
drop policy if exists "reminders: owner reads own"    on public.reminders;
drop policy if exists "reminders: owner inserts own"  on public.reminders;
drop policy if exists "reminders: owner updates own"  on public.reminders;
drop policy if exists "reminders: owner deletes own"  on public.reminders;

create policy "reminders: owner reads own" on public.reminders
  for select using (auth_user_id = auth.uid());
create policy "reminders: owner inserts own" on public.reminders
  for insert with check (auth_user_id = auth.uid());
create policy "reminders: owner updates own" on public.reminders
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "reminders: owner deletes own" on public.reminders
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- documents — owner-only policies (re-asserted to the canonical definition).
-- ----------------------------------------------------------------------------
drop policy if exists "documents: owner reads own"   on public.documents;
drop policy if exists "documents: owner inserts own" on public.documents;
drop policy if exists "documents: owner updates own" on public.documents;
drop policy if exists "documents: owner deletes own" on public.documents;

create policy "documents: owner reads own" on public.documents
  for select using (auth_user_id = auth.uid());
create policy "documents: owner inserts own" on public.documents
  for insert with check (auth_user_id = auth.uid());
create policy "documents: owner updates own" on public.documents
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "documents: owner deletes own" on public.documents
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- users — owner-only policies (a profile row belongs to exactly one auth user).
-- ----------------------------------------------------------------------------
drop policy if exists "users: owner reads own"   on public.users;
drop policy if exists "users: owner inserts own" on public.users;
drop policy if exists "users: owner updates own" on public.users;
drop policy if exists "users: owner deletes own" on public.users;

create policy "users: owner reads own" on public.users
  for select using (auth_user_id = auth.uid());
create policy "users: owner inserts own" on public.users
  for insert with check (auth_user_id = auth.uid());
create policy "users: owner updates own" on public.users
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "users: owner deletes own" on public.users
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- Reload the PostgREST schema cache so the new table/policies are visible to
-- the REST API immediately after a manual paste-and-run.
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';
