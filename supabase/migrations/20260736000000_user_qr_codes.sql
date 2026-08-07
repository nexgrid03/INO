-- ============================================================================
-- INO - "My QR": the user's own payment QR, saved once and shown on Home
-- ----------------------------------------------------------------------------
-- Backs lib/repositories/qr_code_repository.dart.
--
-- ONE ROW PER USER, on purpose: the Home card is called "My QR" (singular) and
-- shows exactly one code, so `auth_user_id` IS the primary key. Replacing the
-- QR is an upsert onto the same row, which means a replace can never leave two
-- codes behind for the app to choose between.
--
-- WHY THE IMAGE LIVES IN THE TABLE, not in Storage:
--   The image stored here is not the photo the user picked - it is the QR
--   auto-cropped out of that photo, typically 10-60 KB of PNG. Keeping it in
--   the row makes the write atomic (image and decoded payload can never
--   disagree), keeps RLS as the single access rule with no second bucket policy
--   to get wrong, and makes deletion actually delete. Postgres TOASTs the
--   column, so a large-ish text value costs nothing on reads that don't select
--   it. If these ever grow past a few hundred KB, move `image_base64` to the
--   `documents` bucket and keep the metadata here.
--
-- WHAT IS AND ISN'T SENSITIVE:
--   A payment QR is meant to be shown to strangers - its payload is a request
--   to RECEIVE money, and knowing a VPA does not let anyone take funds. It is
--   still personal data, so it is owner-only under RLS like everything else.
--   Nothing here is a credential and nothing here is encrypted.
--
-- Idempotent - safe to run multiple times. Uses ONLY core Postgres.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

begin;

create table if not exists public.user_qr_codes (
  auth_user_id  uuid primary key
                references auth.users (id) on delete cascade,

  -- Optional user-facing name ("My GPay QR"). Never required.
  label         text,

  -- The auto-cropped QR as base64 PNG. This is what Home renders.
  image_base64  text not null,

  -- What the QR actually decodes to, e.g. `upi://pay?pa=…`. Null when the
  -- image was saved without a readable code (the user may still upload a photo
  -- the scanner could not decode - we keep the image rather than refuse it).
  payload       text,

  -- Parsed out of `payload` for display, so the card can show a payee without
  -- re-decoding the image on every read.
  payee_vpa     text,
  payee_name    text,

  -- Pixel size of the stored crop, so the UI can lay out before decoding.
  width         integer,
  height        integer,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- A stored QR without an image is meaningless; refuse the row outright
  -- rather than let the app render a blank card.
  constraint user_qr_codes_image_not_blank check (length(image_base64) > 0)
);

comment on table public.user_qr_codes is
  'The user''s own payment QR shown on Home ("My QR"). One row per user - replacing the QR upserts this row.';
comment on column public.user_qr_codes.image_base64 is
  'Base64 PNG of the QR auto-cropped out of the uploaded photo, not the original photo.';
comment on column public.user_qr_codes.payload is
  'Decoded QR contents (e.g. upi://pay?pa=…). Null when the image held no readable code.';
comment on column public.user_qr_codes.payee_vpa is
  'VPA parsed from payload, for display only. A VPA can receive money, never spend it.';

-- ----------------------------------------------------------------------------
-- RLS: owner-only, all four verbs. There is deliberately no anon policy - a
-- saved QR is only ever read by the person who saved it.
-- ----------------------------------------------------------------------------
alter table public.user_qr_codes enable row level security;

drop policy if exists "user_qr_codes: owner reads own"   on public.user_qr_codes;
drop policy if exists "user_qr_codes: owner inserts own" on public.user_qr_codes;
drop policy if exists "user_qr_codes: owner updates own" on public.user_qr_codes;
drop policy if exists "user_qr_codes: owner deletes own" on public.user_qr_codes;

create policy "user_qr_codes: owner reads own" on public.user_qr_codes
  for select using (auth_user_id = auth.uid());

create policy "user_qr_codes: owner inserts own" on public.user_qr_codes
  for insert with check (auth_user_id = auth.uid());

-- `using` gates which row may be updated; `with check` stops an update from
-- reassigning the row to somebody else. Both are required - `using` alone would
-- let an owner rewrite auth_user_id and hand their row to another account.
create policy "user_qr_codes: owner updates own" on public.user_qr_codes
  for update using (auth_user_id = auth.uid())
              with check (auth_user_id = auth.uid());

create policy "user_qr_codes: owner deletes own" on public.user_qr_codes
  for delete using (auth_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- updated_at maintenance. `tg_set_updated_at` already exists in this project
-- (see 20260727140000_vault_keys.sql); create it only if this migration is run
-- against a database that predates it.
-- ----------------------------------------------------------------------------
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at on public.user_qr_codes;
create trigger set_updated_at before update on public.user_qr_codes
  for each row execute function public.tg_set_updated_at();

commit;

-- Make the new table visible to the REST API immediately.
notify pgrst, 'reload schema';
