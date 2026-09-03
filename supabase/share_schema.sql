-- ===========================================================================
-- INO Document Sharing (QR) — Supabase schema
-- Run once in the Supabase dashboard SQL editor.
--
-- Files are uploaded to a Storage bucket named `shares` under an unguessable
-- token path; this table records the bundle. The receiving device resolves a
-- scanned token via the SECURITY DEFINER function below, so a share opens even
-- across accounts — but only with the exact token, and only until it expires.
-- ===========================================================================

create table if not exists public.document_shares (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid        not null references auth.users (id) on delete cascade,
  token      text        not null unique,
  title      text        not null default 'Shared documents',
  files      jsonb       not null default '[]'::jsonb,  -- [{name,path,size,mime}]
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists document_shares_token_idx
  on public.document_shares (token);

alter table public.document_shares enable row level security;

-- Owners manage their own shares.
drop policy if exists document_shares_owner on public.document_shares;
create policy document_shares_owner on public.document_shares
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Token lookup for the receiving device. SECURITY DEFINER intentionally
-- bypasses RLS, but only ever returns a single non-expired row for an exact
-- token match — never a listing.
create or replace function public.get_document_share(p_token text)
returns setof public.document_shares
language sql
security definer
set search_path = public
as $$
  select *
  from public.document_shares
  where token = p_token
    and (expires_at is null or expires_at > now());
$$;

grant execute on function public.get_document_share(text) to anon, authenticated;

-- --- Storage bucket --------------------------------------------------------
-- 1) Create a bucket named `shares` in Storage and mark it PUBLIC (so a scanned
--    token path can be downloaded). Security comes from the unguessable token.
-- 2) Allow signed-in users to upload into it:
drop policy if exists "shares upload" on storage.objects;
create policy "shares upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'shares');
