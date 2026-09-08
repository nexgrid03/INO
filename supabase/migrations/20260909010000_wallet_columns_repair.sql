-- ============================================================================
-- INO — Wallet schema repair: make every column the app writes actually exist
-- ----------------------------------------------------------------------------
-- THE SYMPTOM
--
-- You add a property in the app, it appears in the Property Wallet, and
-- `public.w_property_wallet` is EMPTY.
--
-- THE CAUSE
--
-- A property row needs columns from THREE separate migrations:
--   20260727000000  the base + property columns
--   20260734120000  consent
--   20260908120000  reminder_date
--
-- PostgREST rejects the whole insert if ANY column in the payload is missing
-- from the table ("PGRST204: Could not find the 'reminder_date' column of
-- 'w_property_wallet' in the schema cache"). The app then kept the record
-- locally and — until now — swallowed the error, so the wallet looked healthy
-- and the table stayed empty. The app no longer hides that, but it is still
-- only a safety net: the fix is the columns.
--
-- WHAT THIS FILE DOES
--
-- Adds every column the Dart stores actually send, for every synced wallet
-- table, in ONE file. Nothing is dropped, no data is touched, and re-running is
-- a no-op — `add column if not exists` all the way down. Run it even if you
-- believe the earlier migrations are applied; it costs nothing and it is the
-- fastest way to rule the schema out.
--
-- The column lists below mirror `toRow()` in:
--   lib/services/property_store.dart, investment_store.dart, card_store.dart
-- Keep them in step: a field added to toRow() with no column here is exactly
-- the bug this file exists to fix.
--
-- Run with:  supabase db push   (or paste the whole file into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. The tables must exist at all. `ino_register_wallet` creates the table and
--    the 13 core columns (name, category, record_number, status, tags, notes,
--    is_favorite, expires_at, file_path, created_at, updated_at, auth_user_id)
--    and is idempotent, so this is safe on a database that already has them.
-- ----------------------------------------------------------------------------
do $$
begin
  perform public.ino_register_wallet('Property Wallet',   'builtin', 'home',  4294210634);
  perform public.ino_register_wallet('Investment Wallet', 'builtin', 'chart', 4288453088);
  perform public.ino_register_wallet('Cards Wallet',      'builtin', 'card',  4294341706);
exception
  when undefined_function then
    raise exception
      'ino_register_wallet() is missing — apply 20260727000000_per_wallet_tables.sql first, then re-run this file.';
end $$;

-- ----------------------------------------------------------------------------
-- 1. `consent` — every wallet table, from 20260734120000.
--    The app sends it on EVERY row (the save-consent sheet gates the save), so
--    a table without it rejects every single insert.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'w_identity_wallet', 'w_document_wallet', 'w_property_wallet',
    'w_insurance_wallet', 'w_health_wallet', 'w_investment_wallet',
    'w_banking_wallet', 'w_cards_wallet', 'w_password_vault'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'alter table public.%I add column if not exists consent boolean not null default false', t);
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Property Wallet — mirrors PropertyStore.toRow().
--    `reminder_date` is the one that most often bites: it shipped on its own,
--    two migrations after the rest.
-- ----------------------------------------------------------------------------
alter table public.w_property_wallet
  add column if not exists property_type        text not null default 'other',
  add column if not exists image_path           text,
  add column if not exists purchase_date        date,
  add column if not exists purchase_price       numeric(18, 2),
  add column if not exists current_value        numeric(18, 2),
  add column if not exists area                 numeric(14, 4),
  add column if not exists area_unit            text default 'squareFeet',
  add column if not exists country              text,
  add column if not exists state                text,
  add column if not exists city                 text,
  add column if not exists address              text,
  add column if not exists pin_code             text,
  add column if not exists maps_url             text,
  add column if not exists owner_name           text,
  add column if not exists co_owners            jsonb not null default '[]'::jsonb,
  add column if not exists ownership_percent    numeric(5, 2),
  add column if not exists registration_date    date,
  add column if not exists will_details         text,
  add column if not exists nominee_name         text,
  add column if not exists nominee_relationship text,
  add column if not exists legal_heirs          text[] not null default '{}',
  add column if not exists tax_id               text,
  add column if not exists encumbrance          text,
  add column if not exists has_loan             boolean not null default false,
  add column if not exists loan_provider        text,
  add column if not exists outstanding_loan     numeric(18, 2),
  add column if not exists emi                  numeric(14, 2),
  add column if not exists annual_tax           numeric(14, 2),
  add column if not exists maintenance_charges  numeric(14, 2),
  add column if not exists rental_income        numeric(14, 2),
  add column if not exists other_expenses       numeric(14, 2),
  add column if not exists reminder_note        text,
  add column if not exists reminder_date        timestamptz,
  add column if not exists attachments          jsonb not null default '[]'::jsonb;

comment on column public.w_property_wallet.reminder_date is
  'Optional scheduled reminder timestamp for this property (tax due, lease renewal, EMI).';
comment on column public.w_property_wallet.image_path is
  'Storage object path (<uid>/<ts>.<ext>) in the `documents` bucket, NOT a device path. The app uploads the photo before saving the row.';
comment on column public.w_property_wallet.attachments is
  'Array of {id, kind, name, path, …}. `path` is a storage object path, uploaded before the row is written.';

-- ----------------------------------------------------------------------------
-- 3. Investment Wallet — mirrors InvestmentStore.toRow().
-- ----------------------------------------------------------------------------
alter table public.w_investment_wallet
  add column if not exists investment_type  text not null default 'other',
  add column if not exists institution      text,
  add column if not exists account_number   text,
  add column if not exists units            numeric(20, 6),
  add column if not exists purchase_price   numeric(18, 4),
  add column if not exists invested_amount  numeric(18, 2),
  add column if not exists current_value    numeric(18, 2),
  add column if not exists purchase_date    date,
  add column if not exists maturity_date    date,
  add column if not exists nominee          text,
  add column if not exists attachments      jsonb not null default '[]'::jsonb;

-- ----------------------------------------------------------------------------
-- 4. Cards Wallet — mirrors CardStore.toRow().
--    last4 stays the only part of a card number this table may ever hold.
-- ----------------------------------------------------------------------------
alter table public.w_cards_wallet
  add column if not exists bank          text,
  add column if not exists card_kind     text not null default 'debit',
  add column if not exists network       text not null default 'other',
  add column if not exists holder_name   text,
  add column if not exists last4         text,
  add column if not exists expiry_month  smallint,
  add column if not exists expiry_year   smallint,
  add column if not exists theme_key     text not null default 'ocean';

-- ----------------------------------------------------------------------------
-- 5. Report what is still missing, by name.
--
-- A NOTICE per gap rather than an exception: the point is to tell you which
-- column to chase, not to abort a repair that fixed the other forty.
-- ----------------------------------------------------------------------------
do $$
declare
  spec record;
  missing text[];
begin
  for spec in
    select * from (values
      ('w_property_wallet', array[
        'auth_user_id','name','property_type','status','record_number','notes',
        'is_favorite','consent','created_at','updated_at','image_path',
        'purchase_date','purchase_price','current_value','area','area_unit',
        'country','state','city','address','pin_code','maps_url','owner_name',
        'co_owners','ownership_percent','registration_date','will_details',
        'nominee_name','nominee_relationship','legal_heirs','tax_id',
        'encumbrance','has_loan','loan_provider','outstanding_loan','emi',
        'annual_tax','maintenance_charges','rental_income','other_expenses',
        'reminder_note','reminder_date','attachments']),
      ('w_investment_wallet', array[
        'auth_user_id','name','investment_type','notes','is_favorite','consent',
        'created_at','updated_at','institution','account_number','units',
        'purchase_price','invested_amount','current_value','purchase_date',
        'maturity_date','nominee','attachments']),
      ('w_cards_wallet', array[
        'auth_user_id','name','bank','card_kind','network','holder_name',
        'last4','expiry_month','expiry_year','theme_key','notes','is_favorite',
        'consent','created_at','updated_at'])
    ) as t(tbl, cols)
  loop
    select array_agg(c) into missing
      from unnest(spec.cols) as c
     where not exists (
       select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = spec.tbl
          and column_name = c);

    if missing is null then
      raise notice '% — OK, every column the app writes is present.', spec.tbl;
    else
      raise notice '% — STILL MISSING: %', spec.tbl, array_to_string(missing, ', ');
    end if;
  end loop;
end $$;

-- PostgREST caches the column list. Without this reload it keeps rejecting
-- inserts for columns that now exist — which looks exactly like the bug you
-- just fixed.
notify pgrst, 'reload schema';
