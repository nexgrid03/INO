-- ============================================================================
-- INO - Fix: vault document RPCs called the audit logger with the wrong args
-- ----------------------------------------------------------------------------
-- 20260733 called ino_log_vault_event POSITIONALLY:
--
--     perform public.ino_log_vault_event(
--       p_vault, 'document_shared', jsonb_build_object(...));
--
-- but that function's third parameter is `p_target_type text`, not the metadata
-- object. Postgres therefore looked for ino_log_vault_event(uuid, unknown,
-- jsonb), found nothing, and raised 42883 - which aborted the whole transaction
-- and made every share fail with "function does not exist" even though
-- share_document_to_vault itself was present, granted and reachable.
--
-- Both call sites now use NAMED arguments, which cannot silently bind to the
-- wrong parameter if that signature ever gains or reorders a field.
--
-- Safe to run on a database that already has 20260733: `create or replace`
-- redefines the two functions in place and touches no data.
--
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

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

grant execute on function public.share_document_to_vault(
  uuid, text, text, text, bigint, text, text, uuid, text) to authenticated;
grant execute on function public.remove_vault_document(uuid) to authenticated;

-- Replacing a function body does not change its signature, so PostgREST's cache
-- is already correct - but reloading is harmless and removes one variable if
-- this still misbehaves.
notify pgrst, 'reload schema';
