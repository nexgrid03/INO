-- ============================================================================
-- Family Vault document-shared notification fix:
--   1) Fire on INSERT OR UPDATE (covers new shares, re-shares / updates of
--      existing wallet records via share_vault_item / share_document_to_vault,
--      and un-hiding previously hidden items).
--   2) Use updated_at-versioned dedupe_key so re-sharing notifies members cleanly.
--   3) Enable Supabase Realtime on public.vault_documents in addition to
--      public.notification_outbox so active clients sync immediately.
-- ============================================================================

create or replace function public.tg_vault_document_shared_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vault text;
  v_by    text;
  v_doc   text;
begin
  -- Hidden items must never notify other members.
  if coalesce(new.is_hidden, false) then
    return new;
  end if;

  -- On UPDATE, skip no-op updates where neither visibility nor shared payload
  -- changed; notify whenever un-hidden OR re-shared/updated.
  if tg_op = 'UPDATE'
     and coalesce(old.is_hidden, false) = false
     and new.name is not distinct from old.name
     and new.object_path is not distinct from old.object_path
     and new.shared_data is not distinct from old.shared_data
     and new.shared_fields is not distinct from old.shared_fields
     and new.note is not distinct from old.note
     and new.updated_at is not distinct from old.updated_at then
    return new;
  end if;

  select name into v_vault from public.family_vaults where id = new.vault_id;
  v_vault := coalesce(nullif(trim(v_vault), ''), 'Family Vault');
  v_doc := coalesce(nullif(trim(new.name), ''), 'a document');

  select coalesce(
    nullif(trim(m.display_name), ''),
    nullif(trim(u.full_name), ''),
    nullif(trim(u.email), ''),
    nullif(trim(u.phone), '')
  )
  into v_by
  from auth.users au
  left join public.vault_members m
    on m.vault_id = new.vault_id and m.auth_user_id = au.id
  left join public.users u
    on u.auth_user_id = au.id
  where au.id = new.shared_by
  limit 1;

  v_by := coalesce(nullif(trim(v_by), ''), 'A family member');

  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  select
    m.auth_user_id,
    'vault.document_shared',
    'New Document in ' || v_vault,
    v_by || ' shared "' || v_doc || '" in ' || v_vault || '.',
    'ino_reminders',
    'vault_doc:' || new.id::text || ':' || coalesce(new.updated_at, new.created_at)::text || ':' || m.auth_user_id::text,
    jsonb_build_object(
      'kind', 'vault.document_shared',
      'vault_id', new.vault_id::text,
      'vault_name', v_vault,
      'vault_doc_id', new.id::text,
      'doc_name', v_doc,
      'shared_by', new.shared_by::text,
      'shared_by_name', v_by
    )
  from public.vault_members m
  where m.vault_id = new.vault_id
    and m.auth_user_id <> new.shared_by
  on conflict (dedupe_key) where dedupe_key is not null do nothing;

  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists vault_document_shared_push on public.vault_documents;
create trigger vault_document_shared_push
  after insert or update on public.vault_documents
  for each row execute function public.tg_vault_document_shared_push();

do $$
begin
  alter publication supabase_realtime add table public.notification_outbox;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.vault_documents;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;
