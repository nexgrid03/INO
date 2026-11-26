-- ============================================================================
-- Family Vault notifications:
--   1) Hardened invite notification (vault.invite) resolving invitees via
--      invitee_auth_user_id, public.users, or auth.users, plus inviter name.
--   2) Document shared notification (vault.document_shared) sent to every
--      member of the Family Vault EXCEPT the sharer (new.shared_by).
--   3) Realtime publication enabled on public.notification_outbox so active
--      clients receive immediate in-app banners and bell-feed updates.
-- ============================================================================

-- 1. Invite notification trigger (idempotent replacement)
create or replace function public.tg_vault_invitation_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitee uuid;
  v_vault   text;
  v_by      text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  v_invitee := new.invitee_auth_user_id;

  if v_invitee is null then
    select u.auth_user_id into v_invitee
      from public.users u
     where (new.email is not null and lower(u.email) = lower(new.email))
        or (new.phone is not null
            and public.ino_phone_digits(u.phone) <> ''
            and public.ino_phone_digits(u.phone) = public.ino_phone_digits(new.phone))
     limit 1;
  end if;

  if v_invitee is null then
    select au.id into v_invitee
      from auth.users au
     where (new.email is not null and lower(au.email) = lower(new.email))
        or (new.phone is not null
            and public.ino_phone_digits(au.phone) <> ''
            and public.ino_phone_digits(au.phone) = public.ino_phone_digits(new.phone))
     limit 1;
  end if;

  if v_invitee is null or v_invitee = new.invited_by then
    return new;
  end if;

  select name into v_vault from public.family_vaults where id = new.vault_id;
  v_vault := coalesce(nullif(trim(v_vault), ''), 'Family Vault');

  v_by := nullif(trim(coalesce(new.invited_by_name, '')), '');
  if v_by is null and new.invited_by is not null then
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
    where au.id = new.invited_by
    limit 1;
  end if;

  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  values (
    v_invitee,
    'vault.invite',
    'Family Vault Invitation',
    coalesce(v_by || ' has invited you to their family',
             'You have been invited to join a family')
      || ' (' || v_vault || '). Accept the invite to enter the family.',
    'ino_reminders',
    'invite:' || new.id::text || ':' || coalesce(new.updated_at, new.created_at)::text,
    jsonb_build_object(
      'kind', 'vault.invite',
      'vault_id', new.vault_id::text,
      'vault_name', v_vault,
      'invitation_id', new.id::text,
      'invited_by_name', coalesce(v_by, '')
    )
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;

  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists vault_invitation_push on public.vault_invitations;
create trigger vault_invitation_push
  after insert or update of status on public.vault_invitations
  for each row execute function public.tg_vault_invitation_push();

-- 2. Family document shared notification trigger
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

  -- On UPDATE, notify only when transitioning from hidden -> visible.
  if tg_op = 'UPDATE' and coalesce(old.is_hidden, false) = false then
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
    'vault_doc:' || new.id::text || ':' || m.auth_user_id::text,
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
  after insert or update of is_hidden on public.vault_documents
  for each row execute function public.tg_vault_document_shared_push();

-- 3. Ensure authenticated users can read & subscribe to their own outbox rows
grant select on public.notification_outbox to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.notification_outbox;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;
