-- ============================================================================
-- INO Migration: 20260809000000_health_wallet_align.sql
-- Align public.w_health_wallet with the Health Wallet UI as it exists today.
--
-- What the Add-Document form actually writes for Health Wallet
-- (lib/screens/documents/add_document_screen.dart + lib/repositories/document_repository.dart):
--
--   name           -> "Hospital Name"          (required)
--   doctor_name    -> "Doctor Name"            (optional)
--   category       -> "Document Type"          (X-Ray | Prescription | Lab Report |
--                                               Discharge Summary | Vaccine Record | Other)
--   tags           -> "Tags"
--   expires_at     -> "Next Appointment Date"
--   notes          -> "Notes" (may hold an encoded OCR extraction envelope)
--   record_number  -> filled from OCR extraction
--   file_path      -> Storage object path for the uploaded file
--   status / is_favorite / consent / created_at / updated_at -> core plumbing
--
-- Everything else on the table is left over from an earlier schema and is not
-- read or written anywhere in the app:
--   record_type, patient_name, hospital_name, specialty, blood_group,
--   allergies, visit_date, follow_up_date, report_summary
--
-- This migration salvages whatever those columns hold, archives the rest, and
-- drops them. It is idempotent - safe to run more than once.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Guarantee the one wallet-specific column the UI does use.
-- ---------------------------------------------------------------------------
alter table public.w_health_wallet
  add column if not exists doctor_name text;

-- ---------------------------------------------------------------------------
-- 2. Archive the legacy payload before anything is dropped.
--    Nothing here is recoverable once step 4 runs, so it is kept as JSON in a
--    side table. Only rows that actually carry legacy data are copied, so on a
--    clean database this table ends up empty and you can drop it right away:
--        drop table public.w_health_wallet_legacy_fields;
-- ---------------------------------------------------------------------------
create table if not exists public.w_health_wallet_legacy_fields (
  record_id    uuid primary key references public.w_health_wallet (id) on delete cascade,
  auth_user_id uuid not null,
  fields       jsonb not null,
  archived_at  timestamptz not null default now()
);

alter table public.w_health_wallet_legacy_fields enable row level security;

drop policy if exists "w_health_wallet_legacy_fields: owner reads own"
  on public.w_health_wallet_legacy_fields;
create policy "w_health_wallet_legacy_fields: owner reads own"
  on public.w_health_wallet_legacy_fields
  for select using (auth_user_id = auth.uid());

grant select on public.w_health_wallet_legacy_fields to authenticated;

do $mig$
declare
  v_cols text[] := array[
    'record_type', 'patient_name', 'hospital_name', 'specialty',
    'blood_group', 'allergies', 'visit_date', 'follow_up_date', 'report_summary'
  ];
  v_present text[];
  v_json    text;
  v_filter  text;
begin
  -- Only consider columns that still exist, so a second run finds nothing to do.
  select array_agg(column_name::text order by column_name)
    into v_present
  from information_schema.columns
  where table_schema = 'public'
    and table_name   = 'w_health_wallet'
    and column_name  = any (v_cols);

  if v_present is null then
    raise notice 'w_health_wallet: legacy columns already removed, nothing to archive';
    return;
  end if;

  -- jsonb_build_object('record_type', record_type, ...) over the surviving columns.
  select string_agg(format('%L, %I', c, c), ', ') into v_json   from unnest(v_present) c;
  -- ... where at least one of them is non-empty.
  select string_agg(format('%I is not null', c), ' or ') into v_filter from unnest(v_present) c;

  execute format($sql$
    insert into public.w_health_wallet_legacy_fields (record_id, auth_user_id, fields)
    select id, auth_user_id, jsonb_strip_nulls(jsonb_build_object(%s))
      from public.w_health_wallet
     where (%s)
       and jsonb_strip_nulls(jsonb_build_object(%s)) <> '{}'::jsonb
    on conflict (record_id) do nothing
  $sql$, v_json, v_filter, v_json);

  raise notice 'w_health_wallet: archived legacy fields for % row(s)',
    (select count(*) from public.w_health_wallet_legacy_fields);
end
$mig$;

-- ---------------------------------------------------------------------------
-- 3. Backfill the legacy values that DO have a home in the current UI.
--    Each write is guarded so it never overwrites data the user already has.
-- ---------------------------------------------------------------------------
do $mig$
declare
  v_has boolean;
begin
  -- hospital_name -> name ("Hospital Name" is the name field now)
  select true into v_has from information_schema.columns
   where table_schema = 'public' and table_name = 'w_health_wallet'
     and column_name = 'hospital_name';
  if v_has then
    execute $sql$
      update public.w_health_wallet
         set name = btrim(hospital_name)
       where coalesce(btrim(hospital_name), '') <> ''
         and coalesce(btrim(name), '') = ''
    $sql$;
  end if;

  -- record_type -> category ("Document Type" is the category field now)
  v_has := null;
  select true into v_has from information_schema.columns
   where table_schema = 'public' and table_name = 'w_health_wallet'
     and column_name = 'record_type';
  if v_has then
    execute $sql$
      update public.w_health_wallet
         set category = btrim(record_type)
       where coalesce(btrim(record_type), '') <> ''
         and coalesce(btrim(category), '') = ''
    $sql$;
  end if;

  -- follow_up_date -> expires_at ("Next Appointment Date" is expires_at now)
  v_has := null;
  select true into v_has from information_schema.columns
   where table_schema = 'public' and table_name = 'w_health_wallet'
     and column_name = 'follow_up_date';
  if v_has then
    execute $sql$
      update public.w_health_wallet
         set expires_at = follow_up_date
       where follow_up_date is not null
         and expires_at is null
    $sql$;
  end if;

  -- report_summary -> notes, but ONLY when notes is empty. A non-empty notes
  -- column can hold the encoded OCR extraction envelope, which must not be
  -- appended to or it stops decoding.
  v_has := null;
  select true into v_has from information_schema.columns
   where table_schema = 'public' and table_name = 'w_health_wallet'
     and column_name = 'report_summary';
  if v_has then
    execute $sql$
      update public.w_health_wallet
         set notes = btrim(report_summary)
       where coalesce(btrim(report_summary), '') <> ''
         and coalesce(btrim(notes), '') = ''
    $sql$;
  end if;
end
$mig$;

-- ---------------------------------------------------------------------------
-- 4. Drop the columns the UI does not use.
-- ---------------------------------------------------------------------------
alter table public.w_health_wallet
  drop column if exists record_type,
  drop column if exists patient_name,
  drop column if exists hospital_name,
  drop column if exists specialty,
  drop column if exists blood_group,
  drop column if exists allergies,
  drop column if exists visit_date,
  drop column if exists follow_up_date,
  drop column if exists report_summary;

-- ---------------------------------------------------------------------------
-- 5. Normalise category to the six values the dropdown offers.
--    Anything else becomes 'Other' so the form can round-trip an existing row
--    without the dropdown falling back to null.
--
--    No CHECK constraint is added on purpose: DocumentRepository.move() carries
--    the source wallet's category across when a document is moved INTO the
--    Health Wallet, and that value is not from this list. A constraint would
--    make every such move fail.
-- ---------------------------------------------------------------------------
update public.w_health_wallet
   set category = 'Other'
 where coalesce(btrim(category), '') = ''
    or btrim(category) not in (
         'X-Ray', 'Prescription', 'Lab Report',
         'Discharge Summary', 'Vaccine Record', 'Other'
       );

-- ---------------------------------------------------------------------------
-- 6. Index cleanup.
--    w_health_wallet_usr_crt_idx is byte-for-byte the same index as
--    w_health_wallet_owner_created_idx - two copies of (auth_user_id,
--    created_at desc) cost double on every insert and buy nothing.
--    w_health_wallet_usr_cat_idx is unused: the app never filters by category
--    server-side, it pulls the wallet's rows and filters in Dart. Recreate with
--      create index w_health_wallet_usr_cat_idx
--        on public.w_health_wallet (auth_user_id, category);
--    if server-side category filtering is added later.
-- ---------------------------------------------------------------------------
drop index if exists public.w_health_wallet_usr_crt_idx;
drop index if exists public.w_health_wallet_usr_cat_idx;

-- The two indexes the app's read paths actually use.
create index if not exists w_health_wallet_owner_created_idx
  on public.w_health_wallet (auth_user_id, created_at desc);
create index if not exists w_health_wallet_owner_expiry_idx
  on public.w_health_wallet (auth_user_id, expires_at)
  where expires_at is not null;

-- ---------------------------------------------------------------------------
-- 7. Document the UI mapping on the table itself, so the next person reading
--    the schema does not have to guess why "name" means hospital.
-- ---------------------------------------------------------------------------
comment on table public.w_health_wallet is
  'Health Wallet - medical records, prescriptions and reports. Core columns only, plus doctor_name.';
comment on column public.w_health_wallet.name is
  'Hospital Name in the UI (required).';
comment on column public.w_health_wallet.doctor_name is
  'Doctor Name in the UI (optional).';
comment on column public.w_health_wallet.category is
  'Document Type in the UI: X-Ray | Prescription | Lab Report | Discharge Summary | Vaccine Record | Other.';
comment on column public.w_health_wallet.expires_at is
  'Next Appointment Date in the UI; also drives the auto-created reminder.';
comment on column public.w_health_wallet.record_number is
  'Populated from OCR extraction, not typed by the user.';
comment on column public.w_health_wallet.notes is
  'Free-text notes, or an encoded DocumentExtraction envelope when OCR found fields.';

-- ---------------------------------------------------------------------------
-- 8. Make PostgREST forget the dropped columns.
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;
