-- ============================================================================
-- INO - Transaction "direction" (credited / debited)
-- ----------------------------------------------------------------------------
-- Adds a money-direction column to public.expenses so a transaction records
-- whether funds were debited (money out) or credited (money in), independent of
-- the expense/income type. Mirrors the Flutter model
-- (lib/models/expense_models.dart: TransactionDirection).
--
-- Backward compatibility: the column is nullable and existing rows are
-- backfilled from their type (income → credited, expense → debited) - the same
-- rule the app applies in TransactionRecord.effectiveDirection, so nothing
-- breaks for records saved before this migration.
--
-- Idempotent - safe to run multiple times. Run with:  supabase db push
-- (or paste into the SQL editor).
-- ============================================================================

alter table public.expenses
  add column if not exists direction text;

comment on column public.expenses.direction is
  'Money direction: ''credited'' (in) or ''debited'' (out). Null on legacy rows → derived from type.';

-- Backfill any rows that predate the column from their type.
update public.expenses
   set direction = case when type = 'income' then 'credited' else 'debited' end
 where direction is null;

-- Reload the PostgREST schema cache so the new column is visible to the REST
-- API immediately after a manual paste-and-run.
notify pgrst, 'reload schema';
