-- ============================================================================
-- INO - Create one table per wallet.
-- Paste-ready: `documents` has already been dropped, so this script only
-- CREATES. Safe to re-run (every statement is idempotent).
--
-- Creates:
--   * public.wallets                - registry; `slug` IS the table name
--   * public.w_<wallet>             - one table per wallet, RLS + policies
--   * public.create_custom_wallet() - RPC so a new wallet gets its own table
--   * public.documents              - READ-ONLY view unioning every wallet,
--                                     so the share Edge Function keeps working
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Shared helpers
-- ----------------------------------------------------------------------------

create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

-- "My Pets 🐾" -> "w_my_pets"
create or replace function public.ino_wallet_slug(p_label text)
returns text
language sql
immutable
as $fn$
  select 'w_' || left(
           regexp_replace(
             regexp_replace(lower(trim(p_label)), '[^a-z0-9]+', '_', 'g'),
             '^_+|_+$', '', 'g'),
           40);
$fn$;

-- ----------------------------------------------------------------------------
-- 2. Wallet registry
--    Custom wallet tables are shared schema objects: two users who both create
--    a "Pets" wallet share one table, and RLS keeps their rows apart.
-- ----------------------------------------------------------------------------
create table if not exists public.wallets (
  slug         text primary key,
  label        text not null unique,
  kind         text not null default 'custom'
               check (kind in ('builtin', 'custom', 'system')),
  icon_key     text,
  color_value  bigint,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);

comment on table public.wallets is
  'Registry of every wallet that owns a table. slug = the table name in public.';

alter table public.wallets enable row level security;

drop policy if exists "wallets: authenticated reads" on public.wallets;
create policy "wallets: authenticated reads" on public.wallets
  for select to authenticated using (true);

grant select on public.wallets to authenticated;

-- ----------------------------------------------------------------------------
-- 3. The table factory
--    CORE COLUMNS (identical in every wallet table):
--      id, auth_user_id, name, category, record_number, status, tags,
--      notes, is_favorite, expires_at, file_path, created_at, updated_at
-- ----------------------------------------------------------------------------
create or replace function public.ino_create_wallet_table(p_table text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- 1) Create table skeleton if it does not exist
  execute format($ddl$
    create table if not exists public.%1$I (
      id uuid primary key default gen_random_uuid()
    )
  $ddl$, p_table);

  -- 2) Guarantee all 13 core columns exist (self-healing for pre-existing or partially created tables)
  execute format($ddl$
    alter table public.%1$I
      add column if not exists auth_user_id  uuid default auth.uid()
                                            references auth.users (id) on delete cascade,
      add column if not exists name          text,
      add column if not exists category      text,
      add column if not exists record_number text,
      add column if not exists status        text default 'active',
      add column if not exists tags          text[] default '{}',
      add column if not exists notes         text,
      add column if not exists is_favorite   boolean default false,
      add column if not exists expires_at    date,
      add column if not exists file_path     text,
      add column if not exists created_at    timestamptz default now(),
      add column if not exists updated_at    timestamptz default now();
  $ddl$, p_table);

  -- Ensure column defaults and types align cleanly
  execute format($ddl$
    alter table public.%1$I
      alter column status set default 'active',
      alter column tags set default '{}',
      alter column is_favorite set default false,
      alter column created_at set default now(),
      alter column updated_at set default now();
  $ddl$, p_table);

  -- 3) Create indexes on guaranteed core columns
  execute format(
    'create index if not exists %1$I on public.%2$I (auth_user_id, created_at desc)',
    p_table || '_owner_created_idx', p_table);
  execute format(
    'create index if not exists %1$I on public.%2$I (auth_user_id, expires_at) where expires_at is not null',
    p_table || '_owner_expiry_idx', p_table);

  -- 4) Enable RLS & recreate owner policies idempotently
  execute format('alter table public.%1$I enable row level security', p_table);

  execute format('drop policy if exists %1$I on public.%2$I', p_table || ': owner reads own',   p_table);
  execute format('drop policy if exists %1$I on public.%2$I', p_table || ': owner inserts own', p_table);
  execute format('drop policy if exists %1$I on public.%2$I', p_table || ': owner updates own', p_table);
  execute format('drop policy if exists %1$I on public.%2$I', p_table || ': owner deletes own', p_table);

  execute format(
    'create policy %1$I on public.%2$I for select using (auth_user_id = auth.uid())',
    p_table || ': owner reads own', p_table);
  execute format(
    'create policy %1$I on public.%2$I for insert with check (auth_user_id = auth.uid())',
    p_table || ': owner inserts own', p_table);
  execute format(
    'create policy %1$I on public.%2$I for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid())',
    p_table || ': owner updates own', p_table);
  execute format(
    'create policy %1$I on public.%2$I for delete using (auth_user_id = auth.uid())',
    p_table || ': owner deletes own', p_table);

  -- 5) Trigger for set_updated_at
  execute format('drop trigger if exists set_updated_at on public.%1$I', p_table);
  execute format(
    'create trigger set_updated_at before update on public.%1$I
       for each row execute function public.tg_set_updated_at()',
    p_table);

  -- 6) Permissions
  execute format(
    'grant select, insert, update, delete on public.%1$I to authenticated',
    p_table);
end;
$fn$;

create or replace function public.ino_register_wallet(
  p_label text,
  p_kind  text default 'custom',
  p_icon  text default null,
  p_color bigint default null
)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_slug text := public.ino_wallet_slug(p_label);
begin
  if v_slug is null or v_slug = 'w_' then
    raise exception 'Wallet name must contain at least one letter or digit';
  end if;

  perform public.ino_create_wallet_table(v_slug);

  insert into public.wallets (slug, label, kind, icon_key, color_value, created_by)
  values (v_slug, trim(p_label), p_kind, p_icon, p_color, auth.uid())
  on conflict (slug) do update
    set icon_key    = coalesce(excluded.icon_key,    wallets.icon_key),
        color_value = coalesce(excluded.color_value, wallets.color_value);

  return v_slug;
end;
$fn$;

-- ----------------------------------------------------------------------------
-- 4. The built-in wallets - core skeleton first, then specific columns.
-- ----------------------------------------------------------------------------

-- 4.1 Identity Wallet -- Aadhaar, PAN, passport, licence …
select public.ino_register_wallet('Identity Wallet', 'builtin', 'badge', 4291642541);
alter table public.w_identity_wallet
  add column if not exists holder_name        text,
  add column if not exists id_type            text,
  add column if not exists issuing_authority  text,
  add column if not exists place_of_issue     text,
  add column if not exists issue_date         date,
  add column if not exists date_of_birth      date,
  add column if not exists gender             text,
  add column if not exists nationality        text;
comment on table public.w_identity_wallet is
  'Identity Wallet - government identity documents. record_number holds the ID number.';

-- 4.2 Document Wallet -- the generic catch-all bucket.
select public.ino_register_wallet('Document Wallet', 'builtin', 'folder', 4282684138);
alter table public.w_document_wallet
  add column if not exists doc_type    text,
  add column if not exists issued_by   text,
  add column if not exists issue_date  date,
  add column if not exists page_count  integer;
comment on table public.w_document_wallet is
  'Document Wallet - general documents that do not belong to a specialised wallet.';

-- 4.3 Property Wallet -- mirrors lib/models/property_models.dart (Property).
select public.ino_register_wallet('Property Wallet', 'builtin', 'home', 4294210634);
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
  add column if not exists attachments          jsonb not null default '[]'::jsonb;
comment on table public.w_property_wallet is
  'Property Wallet - one row per property. status holds owned/underConstruction/rented/leased/sold; record_number holds the registration number.';

-- 4.4 Insurance Wallet
select public.ino_register_wallet('Insurance Wallet', 'builtin', 'shield', 4283149546);
alter table public.w_insurance_wallet
  add column if not exists insurer            text,
  add column if not exists policy_type        text,
  add column if not exists policy_holder      text,
  add column if not exists sum_assured        numeric(18, 2),
  add column if not exists premium_amount     numeric(14, 2),
  add column if not exists premium_frequency  text,
  add column if not exists start_date         date,
  add column if not exists renewal_date       date,
  add column if not exists nominee_name       text,
  add column if not exists agent_name         text,
  add column if not exists agent_phone        text;
comment on table public.w_insurance_wallet is
  'Insurance Wallet - policies. record_number holds the policy number, expires_at the maturity/expiry date.';

-- 4.5 Health Wallet
select public.ino_register_wallet('Health Wallet', 'builtin', 'health', 4293673545);
alter table public.w_health_wallet
  add column if not exists doctor_name      text;
-- Uses core columns only (name = Hospital Name, category = Document Type, expires_at = Next Appointment Date).
comment on table public.w_health_wallet is
  'Health Wallet - medical records, prescriptions and reports.';

-- 4.6 Investment Wallet -- mirrors lib/models/investment_models.dart.
select public.ino_register_wallet('Investment Wallet', 'builtin', 'chart', 4288453088);
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
comment on table public.w_investment_wallet is
  'Investment Wallet - one row per holding.';

-- 4.7 Banking Wallet
select public.ino_register_wallet('Banking Wallet', 'builtin', 'bank', 4283016938);
alter table public.w_banking_wallet
  add column if not exists bank_name       text,
  add column if not exists account_holder  text,
  add column if not exists account_number  text,
  add column if not exists account_type    text,
  add column if not exists ifsc_code       text,
  add column if not exists branch_name     text,
  add column if not exists customer_id     text,
  add column if not exists upi_id          text,
  add column if not exists opened_on       date,
  add column if not exists nominee_name    text;
comment on table public.w_banking_wallet is
  'Banking Wallet - accounts, passbooks and statements.';

-- 4.8 Cards Wallet -- mirrors lib/models/card_models.dart (SavedCard).
--     Only last4 is ever stored; the full PAN must never reach this table.
select public.ino_register_wallet('Cards Wallet', 'builtin', 'card', 4294341706);
alter table public.w_cards_wallet
  add column if not exists bank          text,
  add column if not exists card_kind     text not null default 'debit',
  add column if not exists network       text not null default 'other',
  add column if not exists holder_name   text,
  add column if not exists last4         text,
  add column if not exists expiry_month  smallint,
  add column if not exists expiry_year   smallint,
  add column if not exists theme_key     text not null default 'ocean';

do $$
begin
  alter table public.w_cards_wallet
    add constraint w_cards_wallet_last4_chk check (last4 is null or last4 ~ '^[0-9]{4}$');
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.w_cards_wallet
    add constraint w_cards_wallet_expiry_month_chk
    check (expiry_month is null or expiry_month between 1 and 12);
exception when duplicate_object then null;
end $$;

comment on table public.w_cards_wallet is
  'Cards Wallet - saved cards. last4 is the ONLY part of the card number stored here.';

-- 4.9 Password Vault -- mirrors lib/models/password_models.dart.
--     `secret` MUST hold a client-side-encrypted value: RLS protects it from
--     other users, not from operators, logs or a dashboard viewer.
select public.ino_register_wallet('Password Vault', 'builtin', 'lock', 4288453088);
alter table public.w_password_vault
  add column if not exists secret        text,
  add column if not exists url           text,
  add column if not exists username      text,
  add column if not exists email         text,
  add column if not exists icon_key      text,
  add column if not exists last_rotated  timestamptz;
comment on table public.w_password_vault is
  'Password Vault - credentials. `secret` must be encrypted client-side before insert; name = title, category = PasswordCategory.';
comment on column public.w_password_vault.secret is
  'Client-side-encrypted password. NEVER write a plaintext credential here.';

-- 4.10 Share cache -- hidden system wallet holding the processed (grayscale /
--      compressed) copies produced for a QR share. Was `documents.wallet =
--      '__ino_share_cache__'`. Must stay in the `documents` view: the share
--      Edge Function serves these rows by id.
select public.ino_register_wallet('__ino_share_cache__', 'system', null, null);
alter table public.w_ino_share_cache
  add column if not exists source_document_id uuid,
  add column if not exists share_id           text;
comment on table public.w_ino_share_cache is
  'System wallet - processed share copies. Pruned by DocumentRepository.pruneShareCopies; never shown in the UI.';

-- ----------------------------------------------------------------------------
-- 5. Custom wallets - "add a wallet" gets its own table too.
--
--    await Supabase.instance.client.rpc('create_custom_wallet', params: {
--      'p_name': name, 'p_icon': iconKey, 'p_color': colorValue,
--    });   // returns the slug = table name
-- ----------------------------------------------------------------------------
create or replace function public.create_custom_wallet(
  p_name  text,
  p_icon  text   default 'folder',
  p_color bigint default 4281039526
)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_slug  text;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to create a wallet';
  end if;

  -- This function creates SCHEMA OBJECTS, so the input is validated before it
  -- reaches the factory rather than relying on quoting alone.
  if p_name is null or trim(p_name) !~ '^[A-Za-z0-9][A-Za-z0-9 _''&-]{0,39}$' then
    raise exception 'Invalid wallet name: use 1-40 letters, digits, spaces, & _ - or apostrophe';
  end if;

  -- Backstop against a client loop filling the schema with tables.
  select count(*) into v_count from public.wallets where kind = 'custom';
  if v_count >= 200 then
    raise exception 'Custom wallet limit reached';
  end if;

  v_slug := public.ino_register_wallet(p_name, 'custom', p_icon, p_color);

  perform public.ino_rebuild_documents_view();
  notify pgrst, 'reload schema';
  return v_slug;
end;
$fn$;

revoke all on function public.create_custom_wallet(text, text, bigint) from public;
grant execute on function public.create_custom_wallet(text, text, bigint) to authenticated;

-- Removing a custom wallet in the app must NOT drop the table (another account
-- may share it). This deletes the caller's own rows; RLS scopes the delete.
create or replace function public.clear_custom_wallet(p_slug text)
returns integer
language plpgsql
security invoker            -- deliberately invoker: RLS must apply
set search_path = public
as $fn$
declare
  v_deleted integer;
begin
  if not exists (select 1 from public.wallets where slug = p_slug and kind = 'custom') then
    raise exception 'Not a custom wallet: %', p_slug;
  end if;
  execute format('delete from public.%1$I where auth_user_id = auth.uid()', p_slug);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$fn$;

grant execute on function public.clear_custom_wallet(text) to authenticated;

-- Admin-only: actually drop a custom wallet table (destroys EVERY user's rows
-- in it). Not granted to `authenticated` on purpose.
create or replace function public.ino_drop_wallet_table(p_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not exists (select 1 from public.wallets where slug = p_slug and kind = 'custom') then
    raise exception 'Refusing to drop % - not a registered custom wallet', p_slug;
  end if;
  execute format('drop table if exists public.%1$I', p_slug);
  delete from public.wallets where slug = p_slug;
  perform public.ino_rebuild_documents_view();
  notify pgrst, 'reload schema';
end;
$fn$;

revoke all on function public.ino_drop_wallet_table(text) from public, authenticated;

-- ----------------------------------------------------------------------------
-- 6. `public.documents` as a READ-ONLY compatibility view.
--    Keeps working: supabase/functions/share/index.ts, the ownership check in
--    create_document_share(), and any code that reads across all wallets.
--    Rebuilt automatically when a custom wallet is created or dropped.
-- ----------------------------------------------------------------------------
create or replace function public.ino_rebuild_documents_view()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_sql text;
begin
  select string_agg(
           format(
             'select id, auth_user_id, %1$L::text as wallet, name, category, '
             'record_number, status, tags, notes, is_favorite, expires_at, '
             'file_path, created_at, updated_at from public.%2$I',
             label, slug),
           E'\nunion all\n' order by slug)
    into v_sql
  from public.wallets;

  if v_sql is null then
    return;
  end if;

  execute 'drop view if exists public.documents';
  execute 'create view public.documents with (security_invoker = on) as ' || v_sql;
  execute 'grant select on public.documents to authenticated, service_role';
end;
$fn$;

select public.ino_rebuild_documents_view();

comment on view public.documents is
  'READ-ONLY union of every wallet table (core columns + wallet label). Writes must target the per-wallet table directly.';

-- ----------------------------------------------------------------------------
-- 7. Make everything visible to the REST API immediately.
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;
