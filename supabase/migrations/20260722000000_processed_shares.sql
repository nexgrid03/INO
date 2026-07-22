-- Advanced Document Sharing: processed-copy shares.
--
-- Lets a share serve PROCESSED COPIES (colour-converted / watermarked /
-- redacted) that the app uploads to Storage, instead of the original documents.
-- This is additive and leaves the existing `create_document_share` RPC (which
-- serves originals) untouched.
--
-- Deploy: `supabase db push` (or run in the SQL editor), THEN apply the Edge
-- Function patch in supabase/README_processed_shares.md and redeploy the
-- `share` function. Both are required for processed-copy QR links to work.

create extension if not exists pgcrypto;

-- New columns on the existing shares table. All nullable / defaulted so existing
-- rows and the original-file flow are unaffected.
alter table public.document_shares
  add column if not exists processed_paths text[],
  add column if not exists processed_names text[],
  add column if not exists processed_mimes text[],
  add column if not exists view_only boolean not null default false,
  add column if not exists password_hash text;

-- Register a share over already-uploaded processed copies. The app uploads each
-- copy to `<uid>/shares/<stamp>/<i>.<ext>` in the `documents` bucket first (RLS
-- confines writes to the caller's own folder), then calls this to mint the row.
create or replace function public.create_processed_share(
  p_paths        text[],
  p_names        text[],
  p_mimes        text[],
  p_ttl_seconds  integer,
  p_view_only    boolean default false,
  p_password     text default null
)
returns public.document_shares
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.document_shares;
begin
  if v_uid is null then
    raise exception 'You must be signed in to share documents.';
  end if;
  if p_paths is null or array_length(p_paths, 1) is null then
    raise exception 'No files to share.';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds <= 0 then
    raise exception 'Invalid expiry duration.';
  end if;
  -- Defense-in-depth: every processed path must live under the caller's folder.
  if exists (
    select 1 from unnest(p_paths) as pth
    where pth not like v_uid::text || '/%'
  ) then
    raise exception 'Processed files must be under your own folder.';
  end if;

  insert into public.document_shares (
    owner_id, document_ids,
    processed_paths, processed_names, processed_mimes,
    view_only, password_hash, status, expires_at
  )
  values (
    v_uid, '{}',
    p_paths, p_names, p_mimes,
    coalesce(p_view_only, false),
    case
      when p_password is null or length(p_password) = 0 then null
      else encode(digest(p_password, 'sha256'), 'hex')
    end,
    'active',
    now() + make_interval(secs => p_ttl_seconds)
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_processed_share(
  text[], text[], text[], integer, boolean, text
) to authenticated;
