-- ----------------------------------------------------------------------------
-- view-once: sender-chosen ON-SCREEN duration
-- ----------------------------------------------------------------------------
-- `expiry_time` already answers "how long may this link sit unopened before it
-- lapses". This migration adds the second, orthogonal question the sender now
-- gets to answer: **once the recipient opens it, how long does the document
-- stay on screen before it is taken away.**
--
-- The two are deliberately separate. A link can be valid for 24 hours yet only
-- grant a 15-second look, and conflating them would force the sender to choose
-- between "reachable tomorrow" and "brief when opened".
--
-- Enforcement is client-side (web viewer + in-app viewer) because that is where
-- rendering happens — the server cannot un-draw pixels. The value lives here so
-- that both viewers, and any future one, read the SAME number from the same
-- place instead of each hard-coding its own.
--
-- Safe to re-run.

-- ----------------------------------------------------------------------------
-- 1. Column
-- ----------------------------------------------------------------------------
alter table public.view_once_shares
  add column if not exists view_seconds integer not null default 30;

comment on column public.view_once_shares.view_seconds is
  'How many seconds the document stays on screen after the recipient opens it. 0 = no limit. Distinct from expiry_time, which bounds the unopened link.';

-- Bound it to something sane. 0 is the explicit "no limit" escape hatch; the
-- upper bound stops a typo turning a one-time peek into a 3-hour window.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'view_once_shares_view_seconds_ck'
  ) then
    alter table public.view_once_shares
      add constraint view_once_shares_view_seconds_ck
      check (view_seconds = 0 or (view_seconds between 5 and 600));
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 2. create_view_once_share() - now takes the on-screen duration
-- ----------------------------------------------------------------------------
-- The old two-argument function MUST be dropped, not merely superseded. A
-- defaulted third parameter does not overwrite the old signature — it creates a
-- second, distinct function, and every existing two-argument call site would
-- then fail with "function ... is not unique" because Postgres cannot decide
-- between them.
--
-- Dropping it is also what preserves backward compatibility: with only the
-- three-argument version present, an older app build calling
-- `create_view_once_share(doc, ttl)` resolves cleanly to it and picks up the
-- 30-second default.
drop function if exists public.create_view_once_share(uuid, integer);

create or replace function public.create_view_once_share(
  p_document_id  uuid,
  p_ttl_seconds  integer,
  p_view_seconds integer default 30
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
  if p_view_seconds is null
     or (p_view_seconds <> 0 and (p_view_seconds < 5 or p_view_seconds > 600))
  then
    raise exception 'Invalid view duration';
  end if;

  select exists (
    select 1 from public.documents d
    where d.id = p_document_id
      and d.auth_user_id = v_uid
      and d.file_path is not null
  ) into v_ok;

  if not v_ok then
    raise exception 'Document not found';
  end if;

  insert into public.view_once_shares (document_id, owner_id, expiry_time, view_seconds)
  values (
    p_document_id,
    v_uid,
    now() + make_interval(secs => p_ttl_seconds),
    p_view_seconds
  )
  returning * into v_row;

  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. peek / claim - surface the duration to the viewer
-- ----------------------------------------------------------------------------
-- peek returns it so the GATE can tell the recipient how long they will get
-- BEFORE they burn the link ("You'll have 30 seconds"), which is the whole
-- reason the gate exists: an informed, deliberate open.
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
    'status',      'ready',
    'name',        v_doc.name,
    'type',        coalesce(v_doc.category, 'Document'),
    'expiresAt',   v_row.expiry_time,
    'viewSeconds', v_row.view_seconds
  );
end;
$$;

-- claim returns it because the countdown must be driven by the server's number,
-- not by whatever the gate happened to render a moment earlier.
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
    v_peek := public.peek_view_once_share(p_token);
    v_status := v_peek ->> 'status';
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
    'viewedAt',        v_row.viewed_at,
    'viewSeconds',     v_row.view_seconds
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Grants
-- ----------------------------------------------------------------------------
-- `create or replace` on a NEW signature creates a new function object, so the
-- original two-argument grant does not carry over. Re-apply the same policy the
-- base migration set: owners mint, only the Edge Function peeks/claims.
revoke all on function public.create_view_once_share(uuid, integer, integer) from public;
revoke all on function public.peek_view_once_share(text)                     from public;
revoke all on function public.claim_view_once_share(text, text)              from public;

grant execute on function public.create_view_once_share(uuid, integer, integer) to authenticated;
grant execute on function public.peek_view_once_share(text)        to service_role;
grant execute on function public.claim_view_once_share(text, text) to service_role;
