-- ============================================================================
-- INO — Family Vault: real field-level sharing + server-enforced visibility
-- ----------------------------------------------------------------------------
-- WHAT WAS WRONG
--
-- 1. "Hidden from members" was a LIE. The flag lived inside `vault_documents.note`
--    as JSON (`{"hidden": true}`) and the only thing acting on it was a Dart
--    `.where()` in vault_detail_screen. RLS still returned the row and the
--    storage policy still granted the object, so any member could read a hidden
--    document straight off the API. A visibility switch that the server does
--    not enforce is decoration.
--
-- 2. Field-level disclosure had nowhere to live. When you share a property you
--    should be able to send the deed but withhold the price; the chosen mask and
--    the redacted values were being stuffed into the same `note` text column,
--    which meant no index, no constraint, and no way for the server to know what
--    it was serving.
--
-- 3. Re-sharing the same wallet record created a DUPLICATE row every time. The
--    only unique key was `(vault_id, object_path)`, and a structured record with
--    no file gets a freshly-timestamped JSON object path on each share.
--
-- WHAT THIS FILE ADDS
--
--   * vault_documents.is_hidden      — a real boolean the RLS policies read.
--   * vault_documents.shared_fields  — the disclosure mask {field: bool}.
--   * vault_documents.shared_data    — the values that survived that mask.
--   * vault_documents.source_ref     — the wallet record's own id (text, so a
--     device-local `prop_17…` id works as well as a uuid), unique per vault, so
--     re-sharing a record UPDATES its row instead of piling up copies.
--   * share_vault_item()             — the share RPC that understands all four.
--   * set_vault_document_visibility() / set_vault_wallet_visibility() — the
--     per-document and whole-wallet switches.
--
-- The old share_document_to_vault() / remove_vault_document() are left exactly
-- as they are. The app calls the new RPCs and falls back to the old ones, so an
-- app build newer than the database keeps working (without field masks) instead
-- of erroring — which is also what makes this file safe to apply at any time.
--
-- Idempotent. Core Postgres only.
-- Run with:  supabase db push   (or paste the whole file into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The new columns.
-- ----------------------------------------------------------------------------
alter table public.vault_documents
  add column if not exists is_hidden     boolean not null default false,
  add column if not exists shared_fields jsonb   not null default '{}'::jsonb,
  add column if not exists shared_data   jsonb,
  add column if not exists source_ref    text;

comment on column public.vault_documents.is_hidden is
  'Master switch. While true, only the contributor and vault admins/owners can see the row OR open its file — enforced by the RLS policies below, not by the client.';
comment on column public.vault_documents.shared_fields is
  'Disclosure mask, {"price": false, "address": true, …}. Which fields of the source wallet record the contributor agreed to expose.';
comment on column public.vault_documents.shared_data is
  'The field values that survived shared_fields. Denormalized for the same reason the name/category are: the source row is owner-scoped and unreadable to co-members.';
comment on column public.vault_documents.source_ref is
  'The source wallet record''s own id as TEXT — uuid for synced records, prop_17…/inv_17… for ones still device-local. Unique per vault so re-sharing updates in place.';

-- ----------------------------------------------------------------------------
-- 2. Carry the old note-JSON flags onto the real columns.
--    Rows shared before this migration kept {"hidden":true,...,"fields":{...}}
--    inside `note`; without this backfill they would all silently become
--    visible the moment the policies below start reading is_hidden.
-- ----------------------------------------------------------------------------
--    Done row-by-row inside an exception handler rather than as one UPDATE
--    with `note::jsonb`: a hand-typed note that merely LOOKS like JSON
--    ("{see the attached deed}") makes that cast raise, and one bad note would
--    abort the entire migration. Per-row, a bad note is simply skipped.
do $$
declare
  r    record;
  j    jsonb;
  hid  boolean;
begin
  for r in
    select id, note, source_id, source_ref
      from public.vault_documents
     where note is not null and btrim(note) <> ''
  loop
    begin
      j := r.note::jsonb;
    exception when others then
      j := null;
    end;

    if j is null or jsonb_typeof(j) <> 'object' then
      -- Not a config blob, just a human note. Still worth filling provenance.
      if r.source_ref is null and r.source_id is not null then
        update public.vault_documents
           set source_ref = r.source_id::text where id = r.id;
      end if;
      continue;
    end if;

    begin
      hid := coalesce(
               (j ->> 'hidden')::boolean,
               (j ->> 'is_hidden')::boolean,
               not coalesce((j ->> 'active')::boolean, true),
               false);
    exception when others then
      hid := false;
    end;

    update public.vault_documents
       set is_hidden     = hid,
           shared_fields = case
                             when jsonb_typeof(j -> 'fields') = 'object'
                               then j -> 'fields'
                             else '{}'::jsonb
                           end,
           source_ref    = coalesce(r.source_ref,
                                    j ->> 'source_id',
                                    r.source_id::text)
     where id = r.id;
  end loop;
end $$;

-- Rows that never carried a note still want their provenance filled in.
update public.vault_documents
   set source_ref = source_id::text
 where source_ref is null and source_id is not null;

-- Duplicates already exist: before this migration, re-sharing a property added
-- a whole new row every time. Keep the newest of each group and drop the
-- provenance from the older ones, so the unique index below can be created at
-- all. Their rows survive — they just stop being treated as "the same record",
-- which is the honest outcome: the family really was sent several copies.
update public.vault_documents vd
   set source_ref = null
  from (
    select id,
           row_number() over (
             partition by vault_id, source_ref
             order by created_at desc, id desc) as rn
      from public.vault_documents
     where source_ref is not null
  ) ranked
 where ranked.id = vd.id and ranked.rn > 1;

-- One shared copy of a given wallet record per vault. Partial, so the many rows
-- with no provenance at all (plain uploads) are unaffected.
create unique index if not exists vault_documents_source_ref_uidx
  on public.vault_documents (vault_id, source_ref)
  where source_ref is not null;

-- The visibility policies filter on this pair on every read.
create index if not exists vault_documents_visible_idx
  on public.vault_documents (vault_id, is_hidden, created_at desc);

-- ----------------------------------------------------------------------------
-- 3. RLS — make the switch mean something.
--
-- A hidden document is invisible to plain members and editors. Its contributor
-- keeps seeing it (they have to, to switch it back on) and so do admins/owners
-- (they have to, to moderate what the family is sharing).
-- ----------------------------------------------------------------------------
drop policy if exists "vault docs: members read" on public.vault_documents;
create policy "vault docs: members read" on public.vault_documents
  for select using (
    public.is_vault_member(vault_id)
    and (
      not is_hidden
      or shared_by = auth.uid()
      or public.is_vault_admin(vault_id)
    )
  );

-- ----------------------------------------------------------------------------
-- 4. The same rule on the bytes.
--
-- Skipping this would leave the whole feature cosmetic: a member who had once
-- listed the document keeps its object_path, and the 20260733 storage policy
-- grants any object that appears in vault_documents for a vault they belong to
-- — hidden or not. The visibility test has to be repeated here, on the read
-- that actually serves the file.
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
            and (
              not vd.is_hidden
              or vd.shared_by = auth.uid()
              or vm.role in ('owner', 'admin')
            )
        )
      )
  $pol$;
exception
  when insufficient_privilege then
    raise warning 'Could not update the storage policy automatically. Edit '
                  '"vault members read shared objects" by hand in '
                  'Storage → Policies, or hidden documents stay downloadable.';
end $$;

-- ----------------------------------------------------------------------------
-- 5. share_vault_item() — share a document or a wallet record, with a mask.
--
-- SECURITY DEFINER so the editor check happens server-side in one place and the
-- caller cannot fabricate `shared_by`.
--
-- Upsert order matters: match on (vault_id, source_ref) FIRST, because the same
-- wallet record re-shared with a different mask produces a DIFFERENT object_path
-- (the redacted snapshot is a freshly written JSON file). Matching on the path
-- first would insert a second row for the same property.
-- ----------------------------------------------------------------------------
create or replace function public.share_vault_item(
  p_vault         uuid,
  p_object_path   text,
  p_name          text,
  p_category      text    default null,
  p_size_bytes    bigint  default null,
  p_content_type  text    default null,
  p_source_table  text    default null,
  p_source_ref    text    default null,
  p_shared_fields jsonb   default '{}'::jsonb,
  p_shared_data   jsonb   default null,
  p_note          text    default null,
  p_is_hidden     boolean default false
) returns public.vault_documents
language plpgsql security definer set search_path = public
as $$
declare
  v_row       public.vault_documents;
  v_existing  uuid;
  v_source_id uuid;
  v_ref       text := nullif(btrim(coalesce(p_source_ref, '')), '');
begin
  if not public.is_vault_editor(p_vault) then
    raise exception 'Only editors and above can share documents into this vault'
      using errcode = '42501';
  end if;
  if coalesce(p_object_path, '') = '' then
    raise exception 'A document must have a storage path' using errcode = '22023';
  end if;

  -- source_id stays a uuid column; a device-local id like prop_1757… is kept in
  -- source_ref only. Casting it would raise 22P02 and sink the share.
  begin
    v_source_id := v_ref::uuid;
  exception when others then
    v_source_id := null;
  end;

  if v_ref is not null then
    select id into v_existing
      from public.vault_documents
     where vault_id = p_vault and source_ref = v_ref;
  end if;

  if v_existing is null then
    select id into v_existing
      from public.vault_documents
     where vault_id = p_vault and object_path = p_object_path;
  end if;

  if v_existing is not null then
    -- Re-sharing updates in place, so the update path has to carry the same
    -- ownership rule the delete path does. Without this, any editor could
    -- re-share against another member's row and silently rewrite its name,
    -- its disclosure mask and the file it points at — the row would still be
    -- attributed to the original contributor. Admins may moderate; editors
    -- may only revise what they themselves contributed.
    if not exists (
      select 1 from public.vault_documents
       where id = v_existing
         and (shared_by = auth.uid() or public.is_vault_admin(p_vault))
    ) then
      raise exception 'Someone else already shared that into this vault'
        using errcode = '42501';
    end if;

    update public.vault_documents
       set object_path   = p_object_path,
           name          = p_name,
           category      = p_category,
           size_bytes    = coalesce(p_size_bytes, size_bytes),
           content_type  = coalesce(p_content_type, content_type),
           source_table  = coalesce(p_source_table, source_table),
           source_id     = coalesce(v_source_id, source_id),
           source_ref    = coalesce(v_ref, source_ref),
           shared_fields = coalesce(p_shared_fields, '{}'::jsonb),
           shared_data   = p_shared_data,
           note          = p_note,
           is_hidden     = p_is_hidden,
           updated_at    = now()
     where id = v_existing
    returning * into v_row;
  else
    insert into public.vault_documents (
      vault_id, shared_by, object_path, name, category,
      size_bytes, content_type, source_table, source_id, source_ref,
      shared_fields, shared_data, note, is_hidden
    ) values (
      p_vault, auth.uid(), p_object_path, p_name, p_category,
      p_size_bytes, p_content_type, p_source_table, v_source_id, v_ref,
      coalesce(p_shared_fields, '{}'::jsonb), p_shared_data, p_note, p_is_hidden
    )
    returning * into v_row;
  end if;

  -- NAMED arguments — ino_log_vault_event's third parameter is p_target_type,
  -- so passing the jsonb positionally resolves to no signature at all and
  -- aborts the share (the exact bug 20260734 was written to fix).
  perform public.ino_log_vault_event(
    p_vault        => p_vault,
    p_action       => 'document_shared',
    p_target_type  => 'document',
    p_target_id    => v_row.id,
    p_target_label => p_name,
    p_metadata     => jsonb_build_object(
                        'object_path', p_object_path,
                        'wallet',      p_source_table,
                        'fields',      coalesce(p_shared_fields, '{}'::jsonb))
  );

  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. set_vault_document_visibility() — the per-document switch.
--    The contributor controls their own contributions; admins/owners control
--    anything in their vault. Same rule as removal.
-- ----------------------------------------------------------------------------
create or replace function public.set_vault_document_visibility(
  p_document uuid,
  p_visible  boolean
) returns public.vault_documents
language plpgsql security definer set search_path = public
as $$
declare
  v_doc public.vault_documents;
begin
  select * into v_doc from public.vault_documents where id = p_document;
  if not found then
    raise exception 'That document is no longer in this vault'
      using errcode = 'P0002';
  end if;

  if not (v_doc.shared_by = auth.uid() or public.is_vault_admin(v_doc.vault_id)) then
    raise exception 'You can only change documents you shared'
      using errcode = '42501';
  end if;

  update public.vault_documents
     set is_hidden = not coalesce(p_visible, true),
         updated_at = now()
   where id = p_document
  returning * into v_doc;

  perform public.ino_log_vault_event(
    p_vault        => v_doc.vault_id,
    p_action       => case when v_doc.is_hidden
                        then 'document_hidden' else 'document_shown' end,
    p_target_type  => 'document',
    p_target_id    => v_doc.id,
    p_target_label => v_doc.name,
    p_metadata     => jsonb_build_object('hidden', v_doc.is_hidden)
  );

  return v_doc;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. set_vault_wallet_visibility() — the switch at the top of a wallet.
--
-- Flips every document the caller may control in one wallet group at once, and
-- returns how many rows actually changed so the app can report it honestly
-- rather than claiming success for documents it was not allowed to touch.
--
-- p_source_table null  → every wallet in the vault.
-- The caller's reach is the same as everywhere else: their own contributions,
-- or everything if they are an admin/owner.
-- ----------------------------------------------------------------------------
create or replace function public.set_vault_wallet_visibility(
  p_vault        uuid,
  p_source_table text,
  p_visible      boolean
) returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_hidden  boolean := not coalesce(p_visible, true);
  v_admin   boolean := public.is_vault_admin(p_vault);
  v_changed integer;
begin
  if not public.is_vault_member(p_vault) then
    raise exception 'You are not a member of this vault' using errcode = '42501';
  end if;

  with touched as (
    update public.vault_documents
       set is_hidden = v_hidden, updated_at = now()
     where vault_id = p_vault
       and is_hidden is distinct from v_hidden
       and (v_admin or shared_by = auth.uid())
       and (
         p_source_table is null
         -- Wallet names travel denormalized and inconsistently cased
         -- ("Property Wallet" / "property_wallet"), so compare them the way the
         -- app groups them: lower-cased with the spaces and underscores gone.
         or lower(replace(replace(coalesce(source_table, ''), ' ', ''), '_', ''))
            = lower(replace(replace(p_source_table, ' ', ''), '_', ''))
       )
    returning 1
  )
  select count(*) into v_changed from touched;

  if v_changed > 0 then
    perform public.ino_log_vault_event(
      p_vault        => p_vault,
      p_action       => case when v_hidden
                          then 'wallet_hidden' else 'wallet_shown' end,
      p_target_type  => 'wallet',
      p_target_label => coalesce(p_source_table, 'All wallets'),
      p_metadata     => jsonb_build_object('hidden', v_hidden, 'count', v_changed)
    );
  end if;

  return v_changed;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. Grants.
-- ----------------------------------------------------------------------------
grant execute on function public.share_vault_item(
  uuid, text, text, text, bigint, text, text, text, jsonb, jsonb, text, boolean)
  to authenticated;
grant execute on function public.set_vault_document_visibility(uuid, boolean)
  to authenticated;
grant execute on function public.set_vault_wallet_visibility(uuid, text, boolean)
  to authenticated;

-- PostgREST caches the function list; a new function is invisible until it
-- reloads. Applying this through the SQL editor makes that step easy to miss.
notify pgrst, 'reload schema';
