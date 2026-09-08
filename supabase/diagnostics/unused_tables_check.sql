-- ============================================================================
-- Which tables in this database is nothing actually using?
--
-- READ-ONLY. Drops nothing, changes nothing. Paste into the SQL editor and run.
--
-- The repo can only show what the migrations create. This asks the live
-- database, so it also catches tables added by hand in the dashboard and
-- forgotten - which is where dead tables usually come from.
--
-- Read the output with the row counts next to it: a table flagged UNUSED with
-- 0 rows is safe to drop; one flagged UNUSED with rows in it is holding data
-- nothing reads, which is worth understanding before you drop anything.
-- ============================================================================

with known as (
  -- Every table the app, the SQL functions or the edge functions actually read
  -- or write. Derived by tracing usage through lib/, supabase/functions/ and
  -- the migration function bodies.
  select unnest(array[
    -- core
    'users', 'documents', 'wallets', 'reminders', 'notes', 'expenses',
    'tax_documents', 'user_qr_codes', 'user_consents', 'user_sessions',
    'offline_documents', 'device_tokens',
    -- sharing
    'document_shares', 'share_views', 'share_downloads', 'share_rate_limits',
    'view_once_shares',
    -- family vaults
    'family_vaults', 'vault_members', 'vault_documents', 'vault_invitations',
    'vault_join_requests', 'vault_audit_log', 'vault_invite_audit_logs',
    'vault_notification_events', 'vault_keys',
    -- notifications
    'notification_outbox', 'push_log'
  ]) as t
),
live as (
  select
    c.relname::text                                as table_name,
    c.reltuples::bigint                            as approx_rows,
    pg_size_pretty(pg_total_relation_size(c.oid))  as total_size,
    coalesce(s.seq_scan, 0) + coalesce(s.idx_scan, 0) as reads,
    coalesce(s.n_tup_ins, 0) + coalesce(s.n_tup_upd, 0)
      + coalesce(s.n_tup_del, 0)                   as writes
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_stat_user_tables s on s.relid = c.oid
  where n.nspname = 'public'
    and c.relkind = 'r'
)
select
  l.table_name,
  case
    when l.table_name like 'w\_%' then 'wallet table (dynamic - keep)'
    when k.t is not null          then 'USED'
    else                               'UNUSED - nothing in the codebase touches it'
  end                          as verdict,
  l.approx_rows,
  l.total_size,
  l.reads                      as index_and_seq_scans,
  l.writes                     as rows_written_ever
from live l
left join known k on k.t = l.table_name
order by
  case when k.t is null and l.table_name not like 'w\_%' then 0 else 1 end,
  l.approx_rows desc,
  l.table_name;

-- ============================================================================
-- Known dead weight, from tracing the repo. Verify with the query above -
-- specifically that approx_rows is 0 - before dropping ANY of these.
--
--   vault_items   } the first-generation password vault, from
--   vault_meta    } supabase/vault_schema.sql. Superseded by w_password_vault,
--                   which is what the app writes to now. Nothing reads these
--                   two any more except the delete-account cascade.
--
--   w_health_wallet_legacy_fields
--                 - a staging table from 20260809000000_health_wallet_align.
--                   That migration says so itself: "on a clean database this
--                   table ends up empty and you can drop it right away".
--
--   documents_backup_20260727
--                 - only ever appears as a commented-out suggestion in
--                   20260727000000_per_wallet_tables.sql. It exists only if
--                   someone ran that line by hand.
--
-- To drop them, once you have confirmed each is empty:
--
--   drop table if exists public.vault_items;
--   drop table if exists public.vault_meta;
--   drop table if exists public.w_health_wallet_legacy_fields;
--   drop table if exists public.documents_backup_20260727;
--
-- Note that dropping vault_items / vault_meta will make the two defensive
-- `to_regclass('public.vault_items') IS NOT NULL` guards in the delete-account
-- RPC skip them, which is exactly what those guards are for. Nothing breaks.
-- ============================================================================
