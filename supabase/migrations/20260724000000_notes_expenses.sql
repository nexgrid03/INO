-- ============================================================================
-- INO — Notes Vault + Transaction Vault persistence
-- ----------------------------------------------------------------------------
-- Moves the Notes module (previously device-local shared_preferences) and the
-- Expenses / Transaction Vault module (previously in-memory only) onto
-- Supabase, with the same owner-scoped Row Level Security model used by
-- `reminders` / `documents` (see 20260710000000_user_data_isolation.sql):
--
--   1. an `auth_user_id uuid` owner column (default auth.uid()),
--   2. Row Level Security ENABLED, and
--   3. owner-only policies: a user can only SELECT/INSERT/UPDATE/DELETE rows
--      whose auth_user_id equals their own auth.uid().
--
-- Idempotent — safe to run multiple times. Uses ONLY core Postgres.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- notes — the Notes Vault. Columns mirror the Flutter model
-- (lib/models/note_models.dart: Note.toInsert / fromRow). `content` holds what
-- the app model calls `description`.
-- ----------------------------------------------------------------------------
create table if not exists public.notes (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  title         text not null,
  content       text not null default '',
  category      text not null default 'other',
  tags          text[] not null default '{}',
  is_pinned     boolean not null default false,
  is_archived   boolean not null default false,
  is_favorite   boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.notes is
  'Per-user Notes Vault entries. Owner-scoped by auth_user_id via RLS.';

create index if not exists notes_auth_user_id_idx
  on public.notes (auth_user_id);
create index if not exists notes_owner_updated_idx
  on public.notes (auth_user_id, updated_at desc);

-- ----------------------------------------------------------------------------
-- expenses — the ITR-ready Transaction Vault. Columns mirror the Flutter model
-- (lib/models/expense_models.dart: TransactionRecord.toInsert / fromRow).
-- `title` holds what the app model calls `description`; `expense_date` is a
-- timestamptz because records keep their time of day for ordering.
-- ----------------------------------------------------------------------------
create table if not exists public.expenses (
  id              uuid primary key default gen_random_uuid(),
  auth_user_id    uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  title           text not null,
  amount          numeric(14, 2) not null check (amount >= 0),
  type            text not null default 'expense',      -- expense | income
  category        text not null default 'other',        -- TxnCategory.name
  payment_method  text,                                 -- PaymentMethod.name
  expense_date    timestamptz not null,
  reference       text,                                 -- txn id / GSTIN
  gst_amount      numeric(14, 2),
  vendor_name     text,
  notes           text,                                 -- free-text note
  receipt_path    text,                                 -- device-local path
  receipt_is_pdf  boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.expenses is
  'Per-user Transaction Vault records (expenses + income). Owner-scoped by auth_user_id via RLS.';

create index if not exists expenses_auth_user_id_idx
  on public.expenses (auth_user_id);
create index if not exists expenses_owner_date_idx
  on public.expenses (auth_user_id, expense_date desc);

-- ----------------------------------------------------------------------------
-- tax_documents — the tax-document vault attached to the Transaction Vault
-- (Form 16, 26AS, proofs, …). Files stay on-device; this persists the metadata
-- so the vault survives an app restart.
-- ----------------------------------------------------------------------------
create table if not exists public.tax_documents (
  id                    uuid primary key default gen_random_uuid(),
  auth_user_id          uuid not null default auth.uid()
                        references auth.users (id) on delete cascade,
  doc_type              text not null,                  -- TaxDocType.name
  file_name             text not null,
  file_path             text not null,                  -- device-local path
  is_pdf                boolean not null default false,
  financial_year_start  int not null,                   -- FY start year (2026 → FY 2026-27)
  added_at              timestamptz not null default now()
);

comment on table public.tax_documents is
  'Per-user tax-document vault metadata (files stay on-device). Owner-scoped by auth_user_id via RLS.';

create index if not exists tax_documents_auth_user_id_idx
  on public.tax_documents (auth_user_id);
create index if not exists tax_documents_owner_fy_idx
  on public.tax_documents (auth_user_id, financial_year_start);

-- ----------------------------------------------------------------------------
-- Enable Row Level Security. With RLS on and NO policy a table denies all
-- access — the owner-only policies below are what let authenticated users
-- reach their OWN rows.
-- ----------------------------------------------------------------------------
alter table public.notes         enable row level security;
alter table public.expenses      enable row level security;
alter table public.tax_documents enable row level security;

-- ----------------------------------------------------------------------------
-- notes — owner-only policies.
-- ----------------------------------------------------------------------------
drop policy if exists "notes: owner reads own"   on public.notes;
drop policy if exists "notes: owner inserts own" on public.notes;
drop policy if exists "notes: owner updates own" on public.notes;
drop policy if exists "notes: owner deletes own" on public.notes;

create policy "notes: owner reads own" on public.notes
  for select using (auth_user_id = auth.uid());
create policy "notes: owner inserts own" on public.notes
  for insert with check (auth_user_id = auth.uid());
create policy "notes: owner updates own" on public.notes
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "notes: owner deletes own" on public.notes
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- expenses — owner-only policies.
-- ----------------------------------------------------------------------------
drop policy if exists "expenses: owner reads own"   on public.expenses;
drop policy if exists "expenses: owner inserts own" on public.expenses;
drop policy if exists "expenses: owner updates own" on public.expenses;
drop policy if exists "expenses: owner deletes own" on public.expenses;

create policy "expenses: owner reads own" on public.expenses
  for select using (auth_user_id = auth.uid());
create policy "expenses: owner inserts own" on public.expenses
  for insert with check (auth_user_id = auth.uid());
create policy "expenses: owner updates own" on public.expenses
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "expenses: owner deletes own" on public.expenses
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- tax_documents — owner-only policies.
-- ----------------------------------------------------------------------------
drop policy if exists "tax_documents: owner reads own"   on public.tax_documents;
drop policy if exists "tax_documents: owner inserts own" on public.tax_documents;
drop policy if exists "tax_documents: owner updates own" on public.tax_documents;
drop policy if exists "tax_documents: owner deletes own" on public.tax_documents;

create policy "tax_documents: owner reads own" on public.tax_documents
  for select using (auth_user_id = auth.uid());
create policy "tax_documents: owner inserts own" on public.tax_documents
  for insert with check (auth_user_id = auth.uid());
create policy "tax_documents: owner updates own" on public.tax_documents
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy "tax_documents: owner deletes own" on public.tax_documents
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- Reload the PostgREST schema cache so the new tables/policies are visible to
-- the REST API immediately after a manual paste-and-run.
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';
