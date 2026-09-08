-- ============================================================================
-- INO — Did the Family Vault sharing migration actually land?
-- ----------------------------------------------------------------------------
-- Run this AFTER pasting 20260909000000_vault_document_sharing.sql into the SQL
-- editor. Every row should say PASS. Read-only: it inspects the catalog and
-- counts rows, and changes nothing.
--
-- The one that most often fails on its own is the storage policy — managed
-- Postgres can refuse DDL on storage.objects from the SQL editor, in which case
-- the migration logs a warning and carries on. If row 5 says FAIL, edit the
-- policy "vault members read shared objects" by hand in Storage → Policies:
-- hidden documents stay downloadable until you do.
-- ============================================================================

with checks as (

  -- 1. The four columns the app writes to.
  select 1 as n, 'columns on vault_documents' as check_name,
         (select count(*) from information_schema.columns
           where table_schema = 'public' and table_name = 'vault_documents'
             and column_name in
                 ('is_hidden', 'shared_fields', 'shared_data', 'source_ref'))
           = 4 as ok,
         'is_hidden, shared_fields, shared_data, source_ref' as expected

  -- 2. The three new functions, with the argument counts the client sends.
  union all
  select 2, 'share_vault_item(12 args)',
         exists(select 1 from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'share_vault_item'
                   and p.pronargs = 12),
         'security definer, granted to authenticated'

  union all
  select 3, 'set_vault_document_visibility(2 args)',
         exists(select 1 from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public'
                   and p.proname = 'set_vault_document_visibility'
                   and p.pronargs = 2),
         'per-document switch'

  union all
  select 4, 'set_vault_wallet_visibility(3 args)',
         exists(select 1 from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public'
                   and p.proname = 'set_vault_wallet_visibility'
                   and p.pronargs = 3),
         'whole-wallet switch'

  -- 5. The storage policy actually mentions is_hidden. A policy that exists but
  --    predates this migration is the failure mode worth catching: listing hides
  --    the document while the file stays downloadable.
  union all
  select 5, 'storage policy honours is_hidden',
         exists(select 1 from pg_policies
                 where schemaname = 'storage' and tablename = 'objects'
                   and policyname = 'vault members read shared objects'
                   and coalesce(qual, '') like '%is_hidden%'),
         'create it by hand in Storage → Policies if this fails'

  -- 6. The metadata policy too.
  union all
  select 6, 'row policy honours is_hidden',
         exists(select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'vault_documents'
                   and policyname = 'vault docs: members read'
                   and coalesce(qual, '') like '%is_hidden%'),
         'hidden rows are not returned to plain members'

  -- 7. One shared copy per source record, per vault.
  union all
  select 7, 'unique (vault_id, source_ref)',
         exists(select 1 from pg_indexes
                 where schemaname = 'public'
                   and indexname = 'vault_documents_source_ref_uidx'),
         're-sharing a record updates instead of duplicating'

  -- 8. The backfill moved the old note-JSON flags onto the column. Any row
  --    still carrying {"hidden":true} in its note while is_hidden is false was
  --    missed, and would silently become visible.
  union all
  select 8, 'no note-JSON hidden flag left behind',
         not exists(
           select 1 from public.vault_documents
            where is_hidden = false
              and note is not null
              and left(btrim(note), 1) = '{'
              and note like '%"hidden":true%'),
         'backfill carried every hidden flag onto is_hidden'
)
select n as "#",
       check_name as "check",
       case when ok then 'PASS' else 'FAIL' end as result,
       expected as "what it means"
  from checks
 order by n;

-- What is actually in the vaults right now, for a sanity read.
select coalesce(source_table, '(uploaded file)') as wallet,
       count(*)                                  as documents,
       count(*) filter (where is_hidden)         as hidden,
       count(*) filter (where shared_fields <> '{}'::jsonb) as with_field_mask,
       count(*) filter (where shared_data is not null)      as with_shared_data
  from public.vault_documents
 group by 1
 order by 2 desc;
