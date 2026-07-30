-- ============================================================================
-- INO - Family Vault: shared documents
-- ----------------------------------------------------------------------------
-- The Family Vault already had a complete membership system - vaults, roles,
-- invitations, accept/decline, removal, ownership transfer, audit log - but
-- nothing was ever shared INTO a vault. Accepting an invite made you a member
-- of an empty room. This adds the contents.
--
-- THE THREE RULES THIS FILE ENFORCES
--
--   1. Accepting an invite grants access. A member (any role) can list and
--      OPEN every document shared into that vault.
--   2. Removal revokes access immediately - view, open AND download. There is
--      no cached grant and no signed URL that outlives the membership, because
--      the storage policy re-checks vault_members on every single object read.
--   3. The role decides what you can do. viewer = read; editor = read + share
--      their own documents in and remove what they shared; admin/owner = also
--      remove anything.
--
-- WHY THE METADATA IS COPIED, NOT JOINED
--
-- A shared document's source row lives in an owner-scoped wallet table
-- (w_identity_wallet, …) whose RLS restricts it to `auth_user_id = auth.uid()`.
-- A member therefore CANNOT read it, and a foreign key to it would produce rows
-- that list but never render. So the name/category/object_path a member needs
-- are denormalized onto vault_documents - the same approach vault_members
-- already takes for display_name/email.
--
-- Idempotent - safe to run multiple times. Uses ONLY core Postgres.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. is_vault_editor() - the missing rung on the permission ladder.
--    is_vault_member() and is_vault_admin() already exist; "can contribute
--    content" sat between them with no server-side expression.
-- ----------------------------------------------------------------------------
create or replace function public.is_vault_editor(p_vault uuid)
  returns boolean language sql security definer stable
  set search_path = public
as $$
  select exists(
    select 1 from public.vault_members m
    where m.vault_id = p_vault
      and m.auth_user_id = auth.uid()
      and m.role in ('owner', 'admin', 'editor')
  );
$$;

comment on function public.is_vault_editor(uuid) is
  'True when the caller may contribute documents to the vault (editor and up).';

-- ----------------------------------------------------------------------------
-- 2. vault_documents - one row per document shared into a vault.
-- ----------------------------------------------------------------------------
create table if not exists public.vault_documents (
  id            uuid primary key default gen_random_uuid(),
  vault_id      uuid not null references public.family_vaults (id) on delete cascade,

  -- Who shared it. Kept so an editor can withdraw exactly what they contributed
  -- without being able to remove anyone else's.
  shared_by     uuid not null default auth.uid()
                references auth.users (id) on delete cascade,

  -- Where the bytes live in the `documents` storage bucket. This is the value
  -- the storage policy below matches on, so it must be the exact object name.
  object_path   text not null,

  -- Denormalized display data (see the header note on why this is copied).
  name          text not null,
  category      text,
  size_bytes    bigint,
  content_type  text,

  -- Provenance, for the owner's own bookkeeping. Deliberately NOT a foreign
  -- key: the source row is owner-scoped and unreadable to other members.
  source_table  text,
  source_id     uuid,

  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- The same file cannot be shared into the same vault twice.
  unique (vault_id, object_path)
);

comment on table public.vault_documents is
  'Documents shared into a Family Vault. Readable by every member of that vault; writable by editors and up. Removing a member revokes access instantly via the storage policy below.';
comment on column public.vault_documents.object_path is
  'Exact storage object name in the `documents` bucket. The storage RLS policy joins on this - changing the format here silently breaks member downloads.';
comment on column public.vault_documents.shared_by is
  'Who contributed the document. An editor may withdraw only their own; admins and the owner may remove any.';

create index if not exists vault_documents_vault_idx
  on public.vault_documents (vault_id, created_at desc);
-- Supports the storage policy's lookup, which runs on every object read.
create index if not exists vault_documents_object_path_idx
  on public.vault_documents (object_path);

drop trigger if exists set_updated_at on public.vault_documents;
create trigger set_updated_at before update on public.vault_documents
  for each row execute function public.ino_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 3. Row Level Security on the metadata.
-- ----------------------------------------------------------------------------
alter table public.vault_documents enable row level security;

drop policy if exists "vault docs: members read"      on public.vault_documents;
drop policy if exists "vault docs: editors insert"    on public.vault_documents;
drop policy if exists "vault docs: sharer updates"    on public.vault_documents;
drop policy if exists "vault docs: sharer or admin deletes" on public.vault_documents;

-- RULE 1: any member of the vault can see everything shared into it.
create policy "vault docs: members read" on public.vault_documents
  for select using (public.is_vault_member(vault_id));

-- RULE 3: only editors and up may contribute, and only as themselves. The
-- `shared_by = auth.uid()` check stops a member attributing a share to someone
-- else in order to make it un-removable by them.
create policy "vault docs: editors insert" on public.vault_documents
  for insert with check (
    public.is_vault_editor(vault_id) and shared_by = auth.uid()
  );

create policy "vault docs: sharer updates" on public.vault_documents
  for update using (
    shared_by = auth.uid() or public.is_vault_admin(vault_id)
  ) with check (
    shared_by = auth.uid() or public.is_vault_admin(vault_id)
  );

create policy "vault docs: sharer or admin deletes" on public.vault_documents
  for delete using (
    shared_by = auth.uid() or public.is_vault_admin(vault_id)
  );

-- ----------------------------------------------------------------------------
-- 4. Storage access - the part that actually decides "can they open it".
--
-- WITHOUT THIS, members would list documents and then get 403 on every file:
-- the bucket's own policy scopes objects to their uploader's folder
-- (`<uid>/<file>`), and a shared file still lives in the OWNER's folder.
--
-- This grants read on an object ONLY while a live membership row exists that
-- links the caller to a vault the object was shared into. That is what makes
-- removal instant and total (RULE 2): deleting the vault_members row makes this
-- EXISTS return false on the very next request, so an already-issued signed URL
-- stops resolving too. There is no grant cached anywhere to go stale.
--
-- SELECT only. A member never gains write access to another user's storage
-- folder - contributing a document shares a file the contributor already owns.
-- ----------------------------------------------------------------------------
do $$
begin
  execute 'drop policy if exists "vault members read shared objects" on storage.objects';
  execute $pol$
    create policy "vault members read shared objects" on storage.objects
      for select to authenticated
      using (
        bucket_id = 'documents'
        and exists (
          select 1
          from public.vault_documents vd
          join public.vault_members vm on vm.vault_id = vd.vault_id
          where vd.object_path = storage.objects.name
            and vm.auth_user_id = auth.uid()
        )
      )
  $pol$;
exception
  -- Managed Postgres can restrict DDL on storage.objects to the dashboard. If
  -- this fails, members will see documents but downloads will 403 - create the
  -- policy above by hand in Storage → Policies. Failing loudly in the log is
  -- better than a migration that half-applies.
  when insufficient_privilege then
    raise warning 'Could not create the storage policy automatically. Add it '
                  'manually in Storage → Policies, or member downloads will 403.';
end $$;

-- ----------------------------------------------------------------------------
-- 5. share_document_to_vault() - contribute a document.
--
-- SECURITY DEFINER so the role check is made server-side in one place, and so
-- the caller cannot fabricate a `shared_by`. Re-sharing the same file into the
-- same vault refreshes its metadata rather than erroring.
-- ----------------------------------------------------------------------------
create or replace function public.share_document_to_vault(
  p_vault        uuid,
  p_object_path  text,
  p_name         text,
  p_category     text default null,
  p_size_bytes   bigint default null,
  p_content_type text default null,
  p_source_table text default null,
  p_source_id    uuid default null,
  p_note         text default null
) returns public.vault_documents
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.vault_documents;
begin
  if not public.is_vault_editor(p_vault) then
    raise exception 'Only editors and above can share documents into this vault'
      using errcode = '42501';
  end if;
  if coalesce(p_object_path, '') = '' then
    raise exception 'A document must have a storage path' using errcode = '22023';
  end if;

  insert into public.vault_documents as vd (
    vault_id, shared_by, object_path, name, category,
    size_bytes, content_type, source_table, source_id, note
  ) values (
    p_vault, auth.uid(), p_object_path, p_name, p_category,
    p_size_bytes, p_content_type, p_source_table, p_source_id, p_note
  )
  on conflict (vault_id, object_path) do update
    set name       = excluded.name,
        category   = excluded.category,
        note       = excluded.note,
        updated_at = now()
  returning * into v_row;

  -- NAMED arguments, not positional. ino_log_vault_event's third parameter is
  -- `p_target_type text`, so passing the jsonb metadata positionally resolves
  -- to a signature that does not exist and aborts the whole share.
  perform public.ino_log_vault_event(
    p_vault        => p_vault,
    p_action       => 'document_shared',
    p_target_type  => 'document',
    p_target_id    => v_row.id,
    p_target_label => p_name,
    p_metadata     => jsonb_build_object('object_path', p_object_path)
  );

  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. remove_vault_document() - withdraw a document.
--    An editor may withdraw what they shared; admins and the owner may remove
--    anything. Enforced here AND by the delete policy above.
-- ----------------------------------------------------------------------------
create or replace function public.remove_vault_document(p_document uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_doc public.vault_documents;
begin
  select * into v_doc from public.vault_documents where id = p_document;
  if not found then
    return; -- already gone; removing twice is not an error
  end if;

  if not (v_doc.shared_by = auth.uid() or public.is_vault_admin(v_doc.vault_id)) then
    raise exception 'You can only remove documents you shared'
      using errcode = '42501';
  end if;

  delete from public.vault_documents where id = p_document;

  perform public.ino_log_vault_event(
    p_vault        => v_doc.vault_id,
    p_action       => 'document_removed',
    p_target_type  => 'document',
    p_target_id    => p_document,
    p_target_label => v_doc.name,
    p_metadata     => jsonb_build_object('object_path', v_doc.object_path)
  );
end;
$$;

grant execute on function public.is_vault_editor(uuid) to authenticated;
grant execute on function public.share_document_to_vault(
  uuid, text, text, text, bigint, text, text, uuid, text) to authenticated;
grant execute on function public.remove_vault_document(uuid) to authenticated;
