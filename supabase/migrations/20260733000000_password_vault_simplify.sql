-- ============================================================================
-- INO - Password Vault simplification: nickname + password + consent.
-- ----------------------------------------------------------------------------
-- The vault UI now stores exactly one thing per entry: a NICKNAME the user
-- invents (the app insists it must NOT be the real site or app name) and the
-- password itself, sealed on-device by VaultCrypto (AES-GCM under a
-- PBKDF2-derived key) before it is uploaded. `consent` records that the user
-- explicitly approved saving in the consent dialog.
--
-- The Password Vault also stops being a document wallet: it leaves the
-- `public.wallets` registry and therefore the `documents` union view. A
-- password row has no business appearing in a share / global-search surface.
--
-- Existing rows survive: `name` becomes `nickname` and `secret` (the sealed
-- ciphertext) becomes `password`. Their consent backfills to false - honest,
-- because those rows predate the consent dialog.
--
-- `created_at` / `updated_at` are kept: the `set_updated_at` trigger and the
-- app's ordering depend on them, and they identify nothing.
--
-- Safe to re-run. Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 0. Repair: recreate any REGISTERED wallet table that has gone missing.
--    (w_banking_wallet was dropped by hand at one point, which left a dangling
--    registry row - the view rebuild below generates SQL referencing every
--    registered slug and fails hard on a missing table.) The factory restores
--    the core columns, indexes, RLS policies, trigger and grants in one call.
-- ----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in select slug from public.wallets loop
    if to_regclass('public.' || r.slug) is null then
      perform public.ino_create_wallet_table(r.slug);
    end if;
  end loop;
end $$;

-- The Banking Wallet's own columns, exactly as 20260727 defined them - no-ops
-- when the table was never dropped.
alter table public.w_banking_wallet
  add column if not exists bank_name       text,
  add column if not exists account_holder  text,
  add column if not exists account_number  text,
  add column if not exists account_type    text,   -- savings | current | salary | nre | nro
  add column if not exists ifsc_code       text,
  add column if not exists branch_name     text,
  add column if not exists customer_id     text,
  add column if not exists upi_id          text,
  add column if not exists opened_on       date,
  add column if not exists nominee_name    text;

-- ----------------------------------------------------------------------------
-- 1. Leave the registry, then rebuild the `documents` view WITHOUT this table.
--    Must happen before the column drops: the current view still selects the
--    columns being dropped, and Postgres refuses to drop a column a view uses.
-- ----------------------------------------------------------------------------
delete from public.wallets where slug = 'w_password_vault';
select public.ino_rebuild_documents_view();

-- ----------------------------------------------------------------------------
-- 2. Rename what stays. Guarded so a re-run is a no-op instead of an error.
-- ----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public'
                and table_name   = 'w_password_vault'
                and column_name  = 'name') then
    alter table public.w_password_vault rename column name to nickname;
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'public'
                and table_name   = 'w_password_vault'
                and column_name  = 'secret') then
    alter table public.w_password_vault rename column secret to password;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 3. Drop everything the simplified vault no longer stores. The partial index
--    on `expires_at` is dropped automatically with its column.
-- ----------------------------------------------------------------------------
alter table public.w_password_vault
  drop column if exists category,
  drop column if exists record_number,
  drop column if exists status,
  drop column if exists tags,
  drop column if exists notes,
  drop column if exists is_favorite,
  drop column if exists expires_at,
  drop column if exists file_path,
  drop column if exists url,
  drop column if exists username,
  drop column if exists email,
  drop column if exists icon_key,
  drop column if exists last_rotated;

-- ----------------------------------------------------------------------------
-- 4. Consent. The app never inserts without the dialog being approved, so
--    every new row arrives as true; pre-dialog rows stay false.
-- ----------------------------------------------------------------------------
alter table public.w_password_vault
  add column if not exists consent boolean not null default false;

comment on table public.w_password_vault is
  'Password Vault - one row per saved password: a user-invented nickname plus '
  'the sealed password. No longer a document wallet; not part of the documents view.';
comment on column public.w_password_vault.nickname is
  'A decoy label the user invents. The UI tells them NOT to use the real site/app name.';
comment on column public.w_password_vault.password is
  'Client-side-encrypted (AES-GCM) password. NEVER write a plaintext credential here.';
comment on column public.w_password_vault.consent is
  'True when the user approved the save-consent dialog. The app refuses to save without it.';

commit;

-- Make the reshaped table visible to the REST API immediately.
notify pgrst, 'reload schema';
