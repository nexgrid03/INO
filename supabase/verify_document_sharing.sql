-- ============================================================================
-- INO — Verify the QR Document Sharing backend is installed.
-- Paste into Supabase Dashboard → SQL Editor → Run. Every row should report OK.
-- If any report MISSING, (re)run supabase/migrations/20260704000000_document_shares.sql
-- ============================================================================

-- 1. Tables ------------------------------------------------------------------
select 'table: document_shares' as check,
       case when to_regclass('public.document_shares') is not null then 'OK' else 'MISSING' end as status
union all
select 'table: share_views',
       case when to_regclass('public.share_views') is not null then 'OK' else 'MISSING' end
union all
select 'table: share_downloads',
       case when to_regclass('public.share_downloads') is not null then 'OK' else 'MISSING' end

-- 2. The create_document_share RPC (name + exact argument types) -------------
union all
select 'rpc: create_document_share(uuid[], integer)',
       case when exists (
         select 1 from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname = 'create_document_share'
           and pg_get_function_identity_arguments(p.oid) = 'p_document_ids uuid[], p_ttl_seconds integer'
       ) then 'OK' else 'MISSING' end

-- 3. Indexes -----------------------------------------------------------------
union all
select 'index: document_shares_share_id_idx',
       case when to_regclass('public.document_shares_share_id_idx') is not null then 'OK' else 'MISSING' end
union all
select 'index: document_shares_owner_id_idx',
       case when to_regclass('public.document_shares_owner_id_idx') is not null then 'OK' else 'MISSING' end

-- 4. RLS enabled + policies present ------------------------------------------
union all
select 'rls: document_shares enabled',
       case when (select relrowsecurity from pg_class where oid = 'public.document_shares'::regclass)
            then 'OK' else 'MISSING' end
union all
select 'rls: policies on document_shares (expect >= 4)',
       case when (select count(*) from pg_policies
                  where schemaname = 'public' and tablename = 'document_shares') >= 4
            then 'OK' else 'MISSING' end
order by check;

-- 5. If the RPC exists but the app still gets PGRST202, the PostgREST schema
--    cache is stale — force a reload:
-- notify pgrst, 'reload schema';
