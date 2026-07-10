-- ============================================================================
-- INO — Secure Document Sharing via QR Code
-- ----------------------------------------------------------------------------
-- Adds the `document_shares` table (one row per generated QR share) plus the
-- `share_views` / `share_downloads` analytics tables, tight RLS, indexes, and
-- two SECURITY DEFINER helper functions.
--
-- Compatibility: uses ONLY core Postgres functions (gen_random_uuid,
-- make_interval) so it applies to a fresh Supabase project with no extensions
-- to enable. (gen_random_uuid() is built into PostgreSQL 13+; Supabase is PG15.)
--
-- Security model:
--   • The OWNER manages their own shares through RLS (owner_id = auth.uid()).
--   • ANONYMOUS recipients NEVER touch these tables directly. The public share
--     viewer is a Supabase Edge Function that runs with the service-role key
--     (bypassing RLS) and only ever exposes the documents named in a share,
--     and only while it is active + unexpired. So there is deliberately NO
--     anon SELECT policy here — that is the point.
--
-- Run with: supabase db push   (or paste into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- document_shares
-- ----------------------------------------------------------------------------
create table if not exists public.document_shares (
  id            uuid primary key default gen_random_uuid(),
  -- Unguessable public token embedded in the QR/URL, e.g.
  -- share_9f83a1c4e07b1d2f3a. Derived from a random UUID (72 bits of entropy)
  -- so it needs no pgcrypto/gen_random_bytes.
  share_id      text not null unique
                default ('share_' ||
                         substr(replace(gen_random_uuid()::text, '-', ''), 1, 18)),
  owner_id      uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  -- The exact set of documents this share grants access to — nothing else.
  document_ids  uuid[] not null,
  status        text not null default 'active'
                check (status in ('active', 'expired', 'revoked')),
  -- Lightweight analytics counters (detailed rows live in the tables below).
  views_count      integer not null default 0,
  downloads_count  integer not null default 0,
  last_accessed_at timestamptz,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null
);

comment on table public.document_shares is
  'One QR/link share granting read-only access to a fixed set of documents until expiry or revocation.';

create index if not exists document_shares_share_id_idx
  on public.document_shares (share_id);
create index if not exists document_shares_owner_id_idx
  on public.document_shares (owner_id);

-- ----------------------------------------------------------------------------
-- Analytics: one row per view / download event.
-- ----------------------------------------------------------------------------
create table if not exists public.share_views (
  id         uuid primary key default gen_random_uuid(),
  share_id   text not null
             references public.document_shares (share_id) on delete cascade,
  viewed_at  timestamptz not null default now(),
  ip_hash    text
);
create index if not exists share_views_share_id_idx
  on public.share_views (share_id);

create table if not exists public.share_downloads (
  id            uuid primary key default gen_random_uuid(),
  share_id      text not null
                references public.document_shares (share_id) on delete cascade,
  document_id   uuid not null,
  downloaded_at timestamptz not null default now(),
  ip_hash       text
);
create index if not exists share_downloads_share_id_idx
  on public.share_downloads (share_id);

-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
alter table public.document_shares enable row level security;
alter table public.share_views     enable row level security;
alter table public.share_downloads enable row level security;

-- Owner-only management of their own shares.
drop policy if exists "shares: owner reads own"   on public.document_shares;
drop policy if exists "shares: owner inserts own" on public.document_shares;
drop policy if exists "shares: owner updates own" on public.document_shares;
drop policy if exists "shares: owner deletes own" on public.document_shares;

create policy "shares: owner reads own" on public.document_shares
  for select using (owner_id = auth.uid());
create policy "shares: owner inserts own" on public.document_shares
  for insert with check (owner_id = auth.uid());
create policy "shares: owner updates own" on public.document_shares
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "shares: owner deletes own" on public.document_shares
  for delete using (owner_id = auth.uid());

-- Owner-only read of their shares' analytics. (Writes happen service-side.)
drop policy if exists "views: owner reads own"     on public.share_views;
drop policy if exists "downloads: owner reads own" on public.share_downloads;

create policy "views: owner reads own" on public.share_views
  for select using (
    exists (
      select 1 from public.document_shares s
      where s.share_id = share_views.share_id and s.owner_id = auth.uid()
    )
  );
create policy "downloads: owner reads own" on public.share_downloads
  for select using (
    exists (
      select 1 from public.document_shares s
      where s.share_id = share_downloads.share_id and s.owner_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- create_document_share(document_ids, ttl_seconds)
-- ----------------------------------------------------------------------------
-- Creates a share for the CURRENT user after verifying every requested
-- document actually belongs to them — so a client can never share a document
-- id it doesn't own. Returns the full new row (share_id, expires_at, …).
create or replace function public.create_document_share(
  p_document_ids uuid[],
  p_ttl_seconds  integer
)
returns public.document_shares
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_owned integer;
  v_row   public.document_shares;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_document_ids is null or array_length(p_document_ids, 1) is null then
    raise exception 'Select at least one document to share';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds < 60 then
    raise exception 'Invalid expiry duration';
  end if;

  -- Every requested document must belong to the caller.
  select count(*) into v_owned
  from public.documents d
  where d.id = any (p_document_ids)
    and d.auth_user_id = v_uid;

  if v_owned <> array_length(p_document_ids, 1) then
    raise exception 'One or more documents are not yours to share';
  end if;

  insert into public.document_shares (owner_id, document_ids, expires_at)
  values (v_uid, p_document_ids, now() + make_interval(secs => p_ttl_seconds))
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_document_share(uuid[], integer) to authenticated;

-- ----------------------------------------------------------------------------
-- expire_due_shares()  — optional housekeeping (safe to call from a cron job).
-- Flips any active-but-past-expiry rows to 'expired'. Not required for
-- correctness (the Edge Function checks expiry live) but keeps status honest.
-- ----------------------------------------------------------------------------
create or replace function public.expire_due_shares()
returns integer
language sql
security definer
set search_path = public
as $$
  with updated as (
    update public.document_shares
    set status = 'expired'
    where status = 'active' and expires_at < now()
    returning 1
  )
  select count(*)::integer from updated;
$$;

-- ----------------------------------------------------------------------------
-- Reload the PostgREST schema cache so the RPC is callable IMMEDIATELY after
-- applying this file in the SQL editor. Without this, a freshly-created
-- function can return PGRST202 "Could not find the function … in the schema
-- cache" until PostgREST next reloads. `supabase db push` reloads for you, but
-- this makes a manual paste-and-run work straight away too.
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';
