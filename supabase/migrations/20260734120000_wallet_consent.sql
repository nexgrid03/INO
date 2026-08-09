-- ============================================================================
-- INO - Save-consent flag on every wallet table.
-- ----------------------------------------------------------------------------
-- Before any wallet record is saved, the app now shows a consent sheet
-- explaining that the data is stored privately (RLS-scoped to the owner) and
-- only proceeds when the user agrees. `consent` records that approval on the
-- row. The app never inserts without it, so new rows always carry true; rows
-- that predate the dialog stay false - honestly.
--
-- Covers every REGISTERED wallet table (built-ins, user-created custom wallets
-- and the system share cache) and updates the table factory so wallets created
-- in the future are born with the column. `w_password_vault` already has it
-- (20260733) and is no longer in the registry.
--
-- Safe to re-run. Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Add `consent` to every wallet table the registry knows about.
-- ----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in select slug from public.wallets loop
    -- Skip a dangling registry row (missing table) rather than erroring out.
    if to_regclass('public.' || r.slug) is not null then
      execute format(
        'alter table public.%I add column if not exists consent boolean not null default false',
        r.slug);
      execute format(
        'comment on column public.%I.consent is '
        '''True when the user approved the save-consent sheet. The app refuses to save without it.''',
        r.slug);
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Teach the factory so FUTURE custom wallets get the column at creation.
--    Identical to the 20260727 version except for the added `consent` line.
-- ----------------------------------------------------------------------------
create or replace function public.ino_create_wallet_table(p_table text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  execute format($ddl$
    create table if not exists public.%1$I (
      id            uuid primary key default gen_random_uuid(),
      auth_user_id  uuid not null default auth.uid()
                    references auth.users (id) on delete cascade,
      name          text not null,
      category      text,
      record_number text,
      status        text not null default 'active',
      tags          text[] not null default '{}',
      notes         text,
      is_favorite   boolean not null default false,
      expires_at    date,
      file_path     text,
      consent       boolean not null default false,
      created_at    timestamptz not null default now(),
      updated_at    timestamptz not null default now()
    )$ddl$, p_table);

  -- A re-run against a pre-consent table must still end with the column.
  execute format(
    'alter table public.%1$I add column if not exists consent boolean not null default false',
    p_table);

  execute format(
    'create index if not exists %1$I on public.%2$I (auth_user_id, created_at desc)',
    p_table || '_owner_created_idx', p_table);
  execute format(
    'create index if not exists %1$I on public.%2$I (auth_user_id, expires_at) where expires_at is not null',
    p_table || '_owner_expiry_idx', p_table);

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

  execute format('drop trigger if exists set_updated_at on public.%1$I', p_table);
  execute format(
    'create trigger set_updated_at before update on public.%1$I
       for each row execute function public.tg_set_updated_at()',
    p_table);

  execute format(
    'grant select, insert, update, delete on public.%1$I to authenticated',
    p_table);
end;
$fn$;

commit;

-- Make the new columns visible to the REST API immediately.
notify pgrst, 'reload schema';
