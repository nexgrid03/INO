-- ============================================================================
-- INO - View Once Document Sharing
-- ----------------------------------------------------------------------------
-- A one-time, self-destructing share: the recipient can open the document
-- EXACTLY ONCE. After that first successful open the link is permanently dead.
--
-- This is ADDITIVE. It does not touch `document_shares`, the `create_document_
-- share` RPC, or anything the existing QR/link sharing depends on. Normal
-- sharing keeps working byte-for-byte as before.
--
-- Storage is REUSED: a view-once share points at an existing `documents` row by
-- id. No file is copied, re-uploaded or duplicated.
--
-- Security model (identical in spirit to `document_shares`):
--   • The OWNER manages their own view-once links through RLS
--     (owner_id = auth.uid()), and creates them through a SECURITY DEFINER RPC
--     that verifies the document really belongs to them.
--   • ANONYMOUS recipients NEVER touch this table. The `share` Edge Function
--     runs with the service-role key and is the only caller of peek/claim/
--     resolve - so there is deliberately no anon policy here.
--   • The storage path never leaves the server: the Edge Function mints a
--     60-second signed URL server-side and streams the bytes itself.
--
-- The one-time guarantee is a SINGLE atomic UPDATE ... WHERE viewed = false,
-- so two concurrent opens can never both succeed - Postgres row locking picks
-- exactly one winner.
--
-- Run with: supabase db push  (or paste into the SQL editor). Idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- view_once_shares
-- ----------------------------------------------------------------------------
create table if not exists public.view_once_shares (
  id            uuid primary key default gen_random_uuid(),

  -- The unguessable public handle embedded in the link/QR: a random UUID with
  -- the dashes stripped (32 hex chars ≈ 122 bits of entropy). Built from
  -- gen_random_uuid() so no extension is required.
  token         text not null unique
                default replace(gen_random_uuid()::text, '-', ''),

  -- The ONE existing document this link grants a single view of. Storage is
  -- reused - nothing is duplicated.
  document_id   uuid not null,

  owner_id      uuid not null default auth.uid()
                references auth.users (id) on delete cascade,

  -- Optional expiry (always set by the RPC; a link can lapse before it is ever
  -- opened).
  expiry_time   timestamptz not null,

  -- The one-time flag. Flipped by claim_view_once_share() and never flipped
  -- back - that is the whole point.
  viewed        boolean not null default false,
  viewed_at     timestamptz,

  -- The owner can also kill a link before it is opened.
  revoked       boolean not null default false,

  -- A short-lived grant minted AT CLAIM TIME so the recipient's browser/app can
  -- actually fetch the bytes after the token itself has been burned. Without
  -- this, marking `viewed` would immediately lock the viewer out of its own
  -- document. It is single-purpose, expires in minutes, and is only ever known
  -- to the one client that performed the claim.
  access_key        text,
  access_expires_at timestamptz,

  -- Best-effort forensics: who burned the link (hashed, never a raw IP).
  viewer_ip_hash text,

  created_at    timestamptz not null default now()
);

comment on table public.view_once_shares is
  'One-time (view once) share of a single document: the first successful open burns the token permanently.';
comment on column public.view_once_shares.access_key is
  'Short-lived grant minted at claim time so the claiming client can fetch the bytes after the token is burned.';

create index if not exists view_once_shares_owner_id_idx
  on public.view_once_shares (owner_id);
create index if not exists view_once_shares_document_id_idx
  on public.view_once_shares (document_id);
-- Partial index over the links that can still be opened - the hot lookup.
create index if not exists view_once_shares_open_idx
  on public.view_once_shares (token) where viewed = false and revoked = false;

-- ----------------------------------------------------------------------------
-- Row Level Security - owner only. No anon policy, on purpose.
-- ----------------------------------------------------------------------------
alter table public.view_once_shares enable row level security;

drop policy if exists "view_once: owner reads own"   on public.view_once_shares;
drop policy if exists "view_once: owner inserts own" on public.view_once_shares;
drop policy if exists "view_once: owner updates own" on public.view_once_shares;
drop policy if exists "view_once: owner deletes own" on public.view_once_shares;

create policy "view_once: owner reads own" on public.view_once_shares
  for select using (owner_id = auth.uid());
create policy "view_once: owner inserts own" on public.view_once_shares
  for insert with check (owner_id = auth.uid());
create policy "view_once: owner updates own" on public.view_once_shares
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "view_once: owner deletes own" on public.view_once_shares
  for delete using (owner_id = auth.uid());

-- ----------------------------------------------------------------------------
-- create_view_once_share(document_id, ttl_seconds)  - called by the APP
-- ----------------------------------------------------------------------------
-- Mints a one-time link for the CURRENT user after verifying the document
-- actually belongs to them, so a client can never share an id it doesn't own.
-- The token is generated by Postgres (the column default), never by the client.
-- Returns the full new row (token, expiry_time, …).
create or replace function public.create_view_once_share(
  p_document_id uuid,
  p_ttl_seconds integer
)
returns public.view_once_shares
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ok  boolean;
  v_row public.view_once_shares;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_document_id is null then
    raise exception 'Select a document to share';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds < 60 then
    raise exception 'Invalid expiry duration';
  end if;

  select exists (
    select 1 from public.documents d
    where d.id = p_document_id
      and d.auth_user_id = v_uid
      and d.file_path is not null
  ) into v_ok;

  if not v_ok then
    raise exception 'That document is not yours to share';
  end if;

  insert into public.view_once_shares (owner_id, document_id, expiry_time)
  values (v_uid, p_document_id, now() + make_interval(secs => p_ttl_seconds))
  returning * into v_row;

  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- peek_view_once_share(token)  - called by the EDGE FUNCTION (service role)
-- ----------------------------------------------------------------------------
-- NON-CONSUMING status check. Lets the viewer render "ready to open" vs
-- "already viewed / expired" WITHOUT burning the link - so a chat app's link
-- preview crawler, a mis-tap, or a page refresh can never destroy the share.
-- Only an explicit claim burns it.
--
-- Returns: {"status":"ready","name":…,"type":…,"kind":…,"mime":…,"expiresAt":…}
--       or {"status":"viewed"|"expired"|"revoked"|"not_found", …}
create or replace function public.peek_view_once_share(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.view_once_shares;
  v_doc public.documents;
begin
  if p_token is null or length(p_token) < 8 then
    return jsonb_build_object('status', 'not_found');
  end if;

  select * into v_row from public.view_once_shares where token = p_token;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_row.revoked then
    return jsonb_build_object('status', 'revoked');
  end if;
  -- Order matters: "already viewed" is the more informative answer, and a
  -- burned link stays burned even after its expiry passes.
  if v_row.viewed then
    return jsonb_build_object('status', 'viewed', 'viewedAt', v_row.viewed_at);
  end if;
  if v_row.expiry_time <= now() then
    return jsonb_build_object('status', 'expired');
  end if;

  select * into v_doc
  from public.documents
  where id = v_row.document_id and auth_user_id = v_row.owner_id;
  if not found or v_doc.file_path is null then
    return jsonb_build_object('status', 'not_found');
  end if;

  return jsonb_build_object(
    'status',    'ready',
    'name',      v_doc.name,
    'type',      coalesce(v_doc.category, 'Document'),
    'expiresAt', v_row.expiry_time
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- claim_view_once_share(token, ip_hash)  - called by the EDGE FUNCTION
-- ----------------------------------------------------------------------------
-- THE one-time gate. A single atomic UPDATE … WHERE viewed = false flips the
-- row and mints a short-lived access key in the same statement, so concurrent
-- opens can never both win: Postgres locks the row, the loser's WHERE clause no
-- longer matches, and it gets "already viewed".
--
-- Returns: {"status":"claimed","accessKey":…,"accessExpiresAt":…,"name":…,…}
--       or {"status":"viewed"|"expired"|"revoked"|"not_found"}
create or replace function public.claim_view_once_share(
  p_token   text,
  p_ip_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    public.view_once_shares;
  v_doc    public.documents;
  v_key    text := replace(gen_random_uuid()::text, '-', '');
  v_peek   jsonb;
  v_status text;
begin
  if p_token is null or length(p_token) < 8 then
    return jsonb_build_object('status', 'not_found');
  end if;

  update public.view_once_shares s
     set viewed            = true,
         viewed_at         = now(),
         access_key        = v_key,
         access_expires_at = now() + interval '5 minutes',
         viewer_ip_hash    = coalesce(p_ip_hash, s.viewer_ip_hash)
   where s.token       = p_token
     and s.viewed      = false
     and s.revoked     = false
     and s.expiry_time > now()
  returning * into v_row;

  if not found then
    -- Not claimable. Report exactly why, without leaking anything else.
    v_peek := public.peek_view_once_share(p_token);
    v_status := v_peek ->> 'status';
    -- 'ready' here can only mean another request won the race a microsecond
    -- ago; from this caller's point of view the link is spent.
    if v_status = 'ready' then
      return jsonb_build_object('status', 'viewed');
    end if;
    return v_peek;
  end if;

  select * into v_doc
  from public.documents
  where id = v_row.document_id and auth_user_id = v_row.owner_id;
  if not found or v_doc.file_path is null then
    return jsonb_build_object('status', 'not_found');
  end if;

  return jsonb_build_object(
    'status',          'claimed',
    'accessKey',       v_key,
    'accessExpiresAt', v_row.access_expires_at,
    'name',            v_doc.name,
    'type',            coalesce(v_doc.category, 'Document'),
    'viewedAt',        v_row.viewed_at
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- resolve_view_once_file(token, access_key)  - called by the EDGE FUNCTION
-- ----------------------------------------------------------------------------
-- Exchanges the claim's short-lived access key for the storage path, so the
-- Edge Function can sign + stream the bytes. The path is returned ONLY to the
-- service role and never reaches any client.
create or replace function public.resolve_view_once_file(
  p_token      text,
  p_access_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.view_once_shares;
  v_doc public.documents;
begin
  if p_token is null or p_access_key is null or length(p_access_key) < 8 then
    return jsonb_build_object('status', 'denied');
  end if;

  select * into v_row from public.view_once_shares where token = p_token;
  if not found or v_row.revoked then
    return jsonb_build_object('status', 'denied');
  end if;
  -- Constant-shape checks: the key must match and still be inside its window.
  if v_row.access_key is null
     or v_row.access_key <> p_access_key
     or v_row.access_expires_at is null
     or v_row.access_expires_at <= now() then
    return jsonb_build_object('status', 'denied');
  end if;

  select * into v_doc
  from public.documents
  where id = v_row.document_id and auth_user_id = v_row.owner_id;
  if not found or v_doc.file_path is null then
    return jsonb_build_object('status', 'denied');
  end if;

  return jsonb_build_object(
    'status',   'ok',
    'filePath', v_doc.file_path,
    'name',     v_doc.name
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- purge_expired_view_once_shares()  - optional housekeeping (safe from cron).
-- Clears spent access keys and drops long-dead rows. Not required for
-- correctness (every path re-validates live), just keeps the table tidy.
-- ----------------------------------------------------------------------------
create or replace function public.purge_expired_view_once_shares()
returns integer
language sql
security definer
set search_path = public
as $$
  with cleared as (
    update public.view_once_shares
       set access_key = null, access_expires_at = null
     where access_key is not null and access_expires_at <= now()
    returning 1
  ),
  deleted as (
    delete from public.view_once_shares
     where (viewed and viewed_at < now() - interval '30 days')
        or (not viewed and expiry_time < now() - interval '30 days')
    returning 1
  )
  select (select count(*) from cleared)::integer
       + (select count(*) from deleted)::integer;
$$;

-- ----------------------------------------------------------------------------
-- Grants. Postgres grants EXECUTE to PUBLIC by default - revoke it, then hand
-- each function to exactly the role that may call it.
-- ----------------------------------------------------------------------------
revoke all on function public.create_view_once_share(uuid, integer)  from public;
revoke all on function public.peek_view_once_share(text)             from public;
revoke all on function public.claim_view_once_share(text, text)      from public;
revoke all on function public.resolve_view_once_file(text, text)     from public;
revoke all on function public.purge_expired_view_once_shares()       from public;

-- The app (signed-in owner) mints links.
grant execute on function public.create_view_once_share(uuid, integer) to authenticated;

-- Only the Edge Function (service role) may peek / claim / resolve. Anonymous
-- and signed-in clients cannot reach the one-time gate directly.
grant execute on function public.peek_view_once_share(text)         to service_role;
grant execute on function public.claim_view_once_share(text, text)  to service_role;
grant execute on function public.resolve_view_once_file(text, text) to service_role;
grant execute on function public.purge_expired_view_once_shares()   to service_role;

-- ----------------------------------------------------------------------------
-- Reload the PostgREST schema cache so the RPCs are callable IMMEDIATELY after
-- a manual paste-and-run (supabase db push reloads for you).
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';
