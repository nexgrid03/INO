-- ============================================================================
-- INO — Family Vault: COMPLETE, idempotent backend (single migration).
-- Tables + columns + indexes + helpers + triggers + all RPCs + grants + RLS +
-- audit log + notification outbox + realtime. Safe to run multiple times.
-- Run with:  supabase db push   — or paste into the Supabase SQL editor.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. TABLES
-- ----------------------------------------------------------------------------
create table if not exists public.family_vaults (
  id                  uuid primary key default gen_random_uuid(),
  owner_auth_user_id  uuid not null default auth.uid()
                      references auth.users (id) on delete cascade,
  name                text not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists public.vault_members (
  id            uuid primary key default gen_random_uuid(),
  vault_id      uuid not null references public.family_vaults (id) on delete cascade,
  auth_user_id  uuid not null references auth.users (id) on delete cascade,
  role          text not null default 'viewer'
                check (role in ('owner','admin','editor','viewer')),
  display_name  text,
  email         text,
  phone         text,
  created_at    timestamptz not null default now(),
  unique (vault_id, auth_user_id)
);

create table if not exists public.vault_invitations (
  id            uuid primary key default gen_random_uuid(),
  vault_id      uuid not null references public.family_vaults (id) on delete cascade,
  invited_by    uuid not null default auth.uid()
                references auth.users (id) on delete set null,
  role          text not null default 'viewer'
                check (role in ('admin','editor','viewer')),
  email         text,
  phone         text,
  invited_name  text,
  status        text not null default 'pending'
                check (status in ('pending','accepted','declined','revoked','expired')),
  responded_by  uuid references auth.users (id) on delete set null,
  responded_at  timestamptz,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '30 days'),
  constraint vault_invitations_target_chk
    check (coalesce(email,'') <> '' or coalesce(phone,'') <> '')
);

create table if not exists public.vault_audit_log (
  id                  uuid primary key default gen_random_uuid(),
  vault_id            uuid not null references public.family_vaults (id) on delete cascade,
  actor_auth_user_id  uuid references auth.users (id) on delete set null,
  actor_name          text,
  action              text not null,
  target_type         text,
  target_id           uuid,
  target_label        text,
  metadata            jsonb not null default '{}'::jsonb,
  ip_address          inet,
  user_agent          text,
  created_at          timestamptz not null default now()
);

create table if not exists public.vault_notification_events (
  id                      uuid primary key default gen_random_uuid(),
  event_type              text not null,
  vault_id                uuid references public.family_vaults (id) on delete cascade,
  actor_auth_user_id      uuid references auth.users (id) on delete set null,
  recipient_auth_user_id  uuid references auth.users (id) on delete set null,
  recipient_email         text,
  recipient_phone         text,
  channels                text[] not null default array['push','email','sms']::text[],
  payload                 jsonb not null default '{}'::jsonb,
  status                  text not null default 'pending'
                          check (status in ('pending','processing','sent','failed','skipped')),
  attempts                int not null default 0,
  last_error              text,
  created_at              timestamptz not null default now(),
  processed_at            timestamptz
);

-- Idempotent columns for pre-existing installs.
alter table public.family_vaults
  add column if not exists updated_at timestamptz not null default now();

alter table public.vault_members
  add column if not exists display_name text,
  add column if not exists email        text,
  add column if not exists phone        text;

alter table public.vault_invitations
  add column if not exists invited_name    text,
  add column if not exists responded_by    uuid,
  add column if not exists responded_at    timestamptz,
  add column if not exists vault_name      text,
  add column if not exists invited_by_name text,
  add column if not exists updated_at      timestamptz not null default now(),
  add column if not exists accepted_at     timestamptz;

-- ----------------------------------------------------------------------------
-- 2. INDEXES
-- ----------------------------------------------------------------------------
create index if not exists family_vaults_owner_idx
  on public.family_vaults (owner_auth_user_id);
create index if not exists vault_members_vault_idx
  on public.vault_members (vault_id);
create index if not exists vault_members_user_idx
  on public.vault_members (auth_user_id);
create index if not exists vault_members_role_idx
  on public.vault_members (vault_id, role);
create index if not exists vault_invitations_vault_idx
  on public.vault_invitations (vault_id);
create index if not exists vault_invitations_email_idx
  on public.vault_invitations (lower(email)) where email is not null;
create index if not exists vault_invitations_phone_idx
  on public.vault_invitations (phone) where phone is not null;
create index if not exists vault_invitations_status_idx
  on public.vault_invitations (status);
create index if not exists vault_invitations_status_email_idx
  on public.vault_invitations (status, lower(email)) where email is not null;
create index if not exists vault_invitations_status_phone_idx
  on public.vault_invitations (status, phone) where phone is not null;
create index if not exists vault_audit_vault_time_idx
  on public.vault_audit_log (vault_id, created_at desc);
create index if not exists vault_audit_actor_idx
  on public.vault_audit_log (actor_auth_user_id);
create index if not exists vault_notif_pending_idx
  on public.vault_notification_events (created_at) where status = 'pending';
create index if not exists vault_notif_recipient_idx
  on public.vault_notification_events (recipient_auth_user_id);

-- ----------------------------------------------------------------------------
-- 3. HELPER FUNCTIONS (SECURITY DEFINER — bypass RLS to avoid policy recursion
--    and to read the owner-scoped users table for identity matching).
-- ----------------------------------------------------------------------------
create or replace function public.is_vault_member(p_vault uuid)
  returns boolean language sql security definer stable set search_path = public
as $$
  select exists(
    select 1 from public.vault_members m
    where m.vault_id = p_vault and m.auth_user_id = auth.uid()
  );
$$;

create or replace function public.is_vault_admin(p_vault uuid)
  returns boolean language sql security definer stable set search_path = public
as $$
  select exists(
    select 1 from public.vault_members m
    where m.vault_id = p_vault and m.auth_user_id = auth.uid()
      and m.role in ('owner','admin')
  );
$$;

create or replace function public.ino_current_email()
  returns text language sql security definer stable set search_path = public
as $$
  select email from public.users where auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.ino_current_phone()
  returns text language sql security definer stable set search_path = public
as $$
  select phone from public.users where auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.ino_current_name()
  returns text language sql security definer stable set search_path = public
as $$
  select full_name from public.users where auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.ino_touch_updated_at()
  returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.ino_log_vault_event(
  p_vault        uuid,
  p_action       text,
  p_target_type  text default null,
  p_target_id    uuid default null,
  p_target_label text default null,
  p_metadata     jsonb default '{}'::jsonb
)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  insert into public.vault_audit_log
    (vault_id, actor_auth_user_id, actor_name, action,
     target_type, target_id, target_label, metadata)
  values
    (p_vault, auth.uid(), public.ino_current_name(), p_action,
     p_target_type, p_target_id, p_target_label, coalesce(p_metadata, '{}'::jsonb));
end;
$$;

create or replace function public.ino_enqueue_vault_notification(
  p_event_type      text,
  p_vault           uuid,
  p_recipient_uid   uuid default null,
  p_recipient_email text default null,
  p_recipient_phone text default null,
  p_payload         jsonb default '{}'::jsonb
)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  insert into public.vault_notification_events
    (event_type, vault_id, actor_auth_user_id,
     recipient_auth_user_id, recipient_email, recipient_phone, payload)
  values
    (p_event_type, p_vault, auth.uid(),
     p_recipient_uid, nullif(lower(trim(p_recipient_email)), ''),
     nullif(trim(p_recipient_phone), ''), coalesce(p_payload, '{}'::jsonb));
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. TRIGGER FUNCTIONS + TRIGGERS
-- ----------------------------------------------------------------------------
create or replace function public.add_owner_membership()
  returns trigger language plpgsql security definer set search_path = public
as $$
declare
  v_name text; v_email text; v_phone text;
begin
  select full_name, email, phone into v_name, v_email, v_phone
    from public.users where auth_user_id = new.owner_auth_user_id limit 1;

  insert into public.vault_members
    (vault_id, auth_user_id, role, display_name, email, phone)
  values
    (new.id, new.owner_auth_user_id, 'owner',
     coalesce(v_name, 'Owner'), v_email, v_phone)
  on conflict (vault_id, auth_user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_add_owner_membership on public.family_vaults;
create trigger trg_add_owner_membership
  after insert on public.family_vaults
  for each row execute function public.add_owner_membership();

drop trigger if exists trg_touch_invitations on public.vault_invitations;
create trigger trg_touch_invitations
  before update on public.vault_invitations
  for each row execute function public.ino_touch_updated_at();

drop trigger if exists trg_touch_vaults on public.family_vaults;
create trigger trg_touch_vaults
  before update on public.family_vaults
  for each row execute function public.ino_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 5. RPCs (all SECURITY DEFINER, self-authorizing, audited + notify-enqueued).
-- ----------------------------------------------------------------------------

-- 5a. create_family_vault — owner stamped from server auth.uid().
create or replace function public.create_family_vault(p_name text)
  returns public.family_vaults
  language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := nullif(trim(p_name), '');
  v_row  public.family_vaults;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  if v_name is null then
    raise exception 'A vault name is required' using errcode = '22023';
  end if;
  insert into public.family_vaults (owner_auth_user_id, name)
  values (v_uid, v_name)
  returning * into v_row;
  return v_row;
end;
$$;

-- 5b. invite_to_vault — admin/owner invites by email/phone with a role.
create or replace function public.invite_to_vault(
  p_vault uuid,
  p_role  text,
  p_email text default null,
  p_phone text default null
)
  returns public.vault_invitations
  language plpgsql security definer set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_email      text := nullif(lower(trim(p_email)), '');
  v_phone      text := nullif(trim(p_phone), '');
  v_vault_name text;
  v_inviter    text;
  v_target_uid uuid;
  v_row        public.vault_invitations;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  if not public.is_vault_admin(p_vault) then
    raise exception 'Only an owner or admin can invite members' using errcode = '42501';
  end if;
  if p_role not in ('admin','editor','viewer') then
    raise exception 'Invalid role (owner cannot be invited)' using errcode = '22023';
  end if;
  if v_email is null and v_phone is null then
    raise exception 'Provide an email or phone number' using errcode = '22023';
  end if;

  if (v_email is not null and v_email = lower(coalesce(public.ino_current_email(), '')))
     or (v_phone is not null and v_phone = coalesce(public.ino_current_phone(), '')) then
    raise exception 'You can''t invite yourself' using errcode = '22023';
  end if;

  select u.auth_user_id into v_target_uid
    from public.users u
   where (v_email is not null and lower(u.email) = v_email)
      or (v_phone is not null and u.phone = v_phone)
   limit 1;
  if v_target_uid is not null and exists (
       select 1 from public.vault_members m
        where m.vault_id = p_vault and m.auth_user_id = v_target_uid) then
    raise exception 'That person is already a member of this vault' using errcode = '23505';
  end if;

  if exists (
       select 1 from public.vault_invitations i
        where i.vault_id = p_vault and i.status = 'pending'
          and ((v_email is not null and lower(i.email) = v_email)
            or (v_phone is not null and i.phone = v_phone))) then
    raise exception 'There is already a pending invitation for that contact'
      using errcode = '23505';
  end if;

  select name into v_vault_name from public.family_vaults where id = p_vault;
  select full_name into v_inviter from public.users where auth_user_id = v_uid;

  insert into public.vault_invitations
    (vault_id, invited_by, role, email, phone, status, vault_name, invited_by_name)
  values
    (p_vault, v_uid, p_role, v_email, v_phone, 'pending',
     coalesce(v_vault_name, 'Family Vault'), v_inviter)
  returning * into v_row;

  perform public.ino_log_vault_event(
    p_vault, 'invite_sent', 'invitation', v_row.id, coalesce(v_email, v_phone),
    jsonb_build_object('role', p_role, 'email', v_email, 'phone', v_phone));
  perform public.ino_enqueue_vault_notification(
    'invitation.created', p_vault, v_target_uid, v_email, v_phone,
    jsonb_build_object('invitation_id', v_row.id,
                       'vault_name', coalesce(v_vault_name, 'Family Vault'),
                       'role', p_role, 'invited_by_name', v_inviter));
  return v_row;
end;
$$;

-- 5c. accept_vault_invitation — invitee joins the vault.
create or replace function public.accept_vault_invitation(p_invitation_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  inv    public.vault_invitations%rowtype;
  v_name text; v_email text; v_phone text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to accept an invitation';
  end if;
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then raise exception 'Invitation not found'; end if;
  if inv.status <> 'pending' then raise exception 'This invitation is no longer pending'; end if;
  if inv.expires_at < now() then
    update public.vault_invitations set status = 'expired' where id = inv.id;
    raise exception 'This invitation has expired';
  end if;

  select full_name, email, phone into v_name, v_email, v_phone
    from public.users where auth_user_id = auth.uid() limit 1;

  if not (
       (inv.email is not null and lower(inv.email) = lower(coalesce(v_email, '')))
    or (inv.phone is not null and inv.phone = coalesce(v_phone, ''))
  ) then
    raise exception 'This invitation is not addressed to you';
  end if;

  insert into public.vault_members
    (vault_id, auth_user_id, role, display_name, email, phone)
  values
    (inv.vault_id, auth.uid(), inv.role,
     coalesce(v_name, inv.invited_name, 'Member'), v_email, v_phone)
  on conflict (vault_id, auth_user_id) do update set role = excluded.role;

  update public.vault_invitations
     set status = 'accepted', responded_by = auth.uid(),
         responded_at = now(), accepted_at = now()
   where id = inv.id;

  perform public.ino_log_vault_event(
    inv.vault_id, 'invite_accepted', 'invitation', inv.id,
    coalesce(v_name, v_email, v_phone), jsonb_build_object('role', inv.role));
  perform public.ino_enqueue_vault_notification(
    'invitation.accepted', inv.vault_id, inv.invited_by, null, null,
    jsonb_build_object('member_name', coalesce(v_name, v_email, v_phone), 'role', inv.role));
end;
$$;

-- 5d. decline_vault_invitation — invitee declines.
create or replace function public.decline_vault_invitation(p_invitation_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  inv public.vault_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null or inv.status <> 'pending' then return; end if;
  if not (
       (inv.email is not null and lower(inv.email) = lower(coalesce(public.ino_current_email(), '')))
    or (inv.phone is not null and inv.phone = coalesce(public.ino_current_phone(), ''))
  ) then
    raise exception 'This invitation is not addressed to you' using errcode = '42501';
  end if;
  update public.vault_invitations
     set status = 'declined', responded_by = auth.uid(), responded_at = now()
   where id = inv.id;

  perform public.ino_log_vault_event(
    inv.vault_id, 'invite_declined', 'invitation', inv.id,
    coalesce(inv.email, inv.phone), jsonb_build_object('role', inv.role));
  perform public.ino_enqueue_vault_notification(
    'invitation.declined', inv.vault_id, inv.invited_by, null, null,
    jsonb_build_object('target', coalesce(inv.email, inv.phone)));
end;
$$;

-- 5e. cancel_vault_invitation — admin/owner revokes a pending invite.
create or replace function public.cancel_vault_invitation(p_invitation_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  inv public.vault_invitations%rowtype;
begin
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then return; end if;
  if not public.is_vault_admin(inv.vault_id) then
    raise exception 'Only an owner or admin can cancel invitations' using errcode = '42501';
  end if;
  update public.vault_invitations set status = 'revoked' where id = inv.id;

  perform public.ino_log_vault_event(
    inv.vault_id, 'invite_cancelled', 'invitation', inv.id,
    coalesce(inv.email, inv.phone), jsonb_build_object('role', inv.role));
end;
$$;

-- 5f. resend_vault_invitation — admin/owner re-arms a non-pending invite.
create or replace function public.resend_vault_invitation(
  p_invitation_id uuid,
  p_role text default null
)
  returns public.vault_invitations
  language plpgsql security definer set search_path = public
as $$
declare
  inv          public.vault_invitations%rowtype;
  v_row        public.vault_invitations;
  v_target_uid uuid;
begin
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then raise exception 'Invitation not found' using errcode = 'P0002'; end if;
  if not public.is_vault_admin(inv.vault_id) then
    raise exception 'Only an owner or admin can resend invitations' using errcode = '42501';
  end if;
  if p_role is not null and p_role not in ('admin','editor','viewer') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  update public.vault_invitations
     set status = 'pending',
         role = coalesce(p_role, role),
         expires_at = now() + interval '30 days',
         responded_by = null, responded_at = null, accepted_at = null
   where id = inv.id
   returning * into v_row;

  select u.auth_user_id into v_target_uid from public.users u
   where (v_row.email is not null and lower(u.email) = lower(v_row.email))
      or (v_row.phone is not null and u.phone = v_row.phone)
   limit 1;

  perform public.ino_log_vault_event(
    v_row.vault_id, 'invite_resent', 'invitation', v_row.id,
    coalesce(v_row.email, v_row.phone), jsonb_build_object('role', v_row.role));
  perform public.ino_enqueue_vault_notification(
    'invitation.created', v_row.vault_id, v_target_uid, v_row.email, v_row.phone,
    jsonb_build_object('invitation_id', v_row.id, 'vault_name', v_row.vault_name,
                       'role', v_row.role, 'resent', true));
  return v_row;
end;
$$;

-- 5g. set_vault_member_role — admin/owner changes a role (never 'owner').
create or replace function public.set_vault_member_role(
  p_member_id uuid,
  p_role text
)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  m public.vault_members%rowtype;
  v_old text;
begin
  select * into m from public.vault_members where id = p_member_id;
  if m.id is null then raise exception 'Member not found' using errcode = 'P0002'; end if;
  if not public.is_vault_admin(m.vault_id) then
    raise exception 'Only an owner or admin can change roles' using errcode = '42501';
  end if;
  if p_role not in ('admin','editor','viewer') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  if m.role = 'owner' then
    raise exception 'The owner''s role can''t be changed here — transfer ownership instead'
      using errcode = '42501';
  end if;
  v_old := m.role;
  update public.vault_members set role = p_role where id = p_member_id;

  perform public.ino_log_vault_event(
    m.vault_id, 'role_changed', 'member', m.id, m.display_name,
    jsonb_build_object('from', v_old, 'to', p_role));
  perform public.ino_enqueue_vault_notification(
    'member.role_changed', m.vault_id, m.auth_user_id, m.email, m.phone,
    jsonb_build_object('from', v_old, 'to', p_role));
end;
$$;

-- 5h. remove_vault_member — admin removes a member, or a member leaves.
create or replace function public.remove_vault_member(p_member_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  m public.vault_members%rowtype;
  v_self boolean;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into m from public.vault_members where id = p_member_id;
  if m.id is null then return; end if;
  if m.role = 'owner' then
    raise exception 'The owner can''t be removed — transfer ownership first' using errcode = '42501';
  end if;
  if not (public.is_vault_admin(m.vault_id) or m.auth_user_id = auth.uid()) then
    raise exception 'You don''t have permission to remove this member' using errcode = '42501';
  end if;
  v_self := (m.auth_user_id = auth.uid());
  delete from public.vault_members where id = p_member_id;

  perform public.ino_log_vault_event(
    m.vault_id, case when v_self then 'member_left' else 'member_removed' end,
    'member', m.id, m.display_name, jsonb_build_object('role', m.role));
  if not v_self then
    perform public.ino_enqueue_vault_notification(
      'member.removed', m.vault_id, m.auth_user_id, m.email, m.phone,
      jsonb_build_object('member_name', m.display_name));
  end if;
end;
$$;

-- 5i. transfer_vault_ownership — atomic; exactly one owner always exists.
create or replace function public.transfer_vault_ownership(
  p_vault uuid,
  p_new_owner uuid
)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  m public.vault_members%rowtype;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  if not exists (select 1 from public.family_vaults
                  where id = p_vault and owner_auth_user_id = v_uid) then
    raise exception 'Only the owner can transfer ownership' using errcode = '42501';
  end if;
  if p_new_owner = v_uid then
    raise exception 'You are already the owner' using errcode = '22023';
  end if;
  select * into m from public.vault_members
   where vault_id = p_vault and auth_user_id = p_new_owner;
  if m.id is null then
    raise exception 'The new owner must be a member of the vault' using errcode = '22023';
  end if;

  update public.vault_members set role = 'admin'
   where vault_id = p_vault and auth_user_id = v_uid;
  update public.vault_members set role = 'owner'
   where vault_id = p_vault and auth_user_id = p_new_owner;
  update public.family_vaults set owner_auth_user_id = p_new_owner where id = p_vault;

  perform public.ino_log_vault_event(
    p_vault, 'ownership_transferred', 'member', m.id, m.display_name,
    jsonb_build_object('new_owner', p_new_owner, 'previous_owner', v_uid));
  perform public.ino_enqueue_vault_notification(
    'ownership.transferred', p_vault, p_new_owner, m.email, m.phone,
    jsonb_build_object('member_name', m.display_name));
end;
$$;

-- 5j. rename_family_vault — owner only, audited.
create or replace function public.rename_family_vault(p_vault uuid, p_name text)
  returns public.family_vaults
  language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := nullif(trim(p_name), '');
  v_old  text;
  v_row  public.family_vaults;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  if v_name is null then
    raise exception 'A vault name is required' using errcode = '22023';
  end if;
  select name into v_old from public.family_vaults
   where id = p_vault and owner_auth_user_id = v_uid;
  if v_old is null then
    raise exception 'Only the owner can rename this vault' using errcode = '42501';
  end if;
  update public.family_vaults set name = v_name where id = p_vault returning * into v_row;

  perform public.ino_log_vault_event(
    p_vault, 'vault_renamed', 'vault', p_vault, v_name,
    jsonb_build_object('from', v_old, 'to', v_name));
  return v_row;
end;
$$;

-- 5k. delete_family_vault — owner only.
create or replace function public.delete_family_vault(p_vault uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  if not exists (select 1 from public.family_vaults
                  where id = p_vault and owner_auth_user_id = v_uid) then
    raise exception 'Only the owner can delete this vault' using errcode = '42501';
  end if;
  delete from public.family_vaults where id = p_vault;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. GRANTS on RPCs (they self-authorize inside).
-- ----------------------------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'create_family_vault(text)',
    'invite_to_vault(uuid,text,text,text)',
    'accept_vault_invitation(uuid)',
    'decline_vault_invitation(uuid)',
    'cancel_vault_invitation(uuid)',
    'resend_vault_invitation(uuid,text)',
    'set_vault_member_role(uuid,text)',
    'remove_vault_member(uuid)',
    'transfer_vault_ownership(uuid,uuid)',
    'rename_family_vault(uuid,text)',
    'delete_family_vault(uuid)',
    'accept_vault_invitation(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

revoke all on function public.ino_log_vault_event(uuid,text,text,uuid,text,jsonb) from public;
revoke all on function public.ino_enqueue_vault_notification(text,uuid,uuid,text,text,jsonb) from public;

-- ----------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.family_vaults            enable row level security;
alter table public.vault_members            enable row level security;
alter table public.vault_invitations        enable row level security;
alter table public.vault_audit_log          enable row level security;
alter table public.vault_notification_events enable row level security;

-- family_vaults
drop policy if exists "vaults: members read"  on public.family_vaults;
drop policy if exists "vaults: owner inserts"  on public.family_vaults;
drop policy if exists "vaults: owner updates"  on public.family_vaults;
drop policy if exists "vaults: owner deletes"  on public.family_vaults;
create policy "vaults: members read" on public.family_vaults
  for select using (owner_auth_user_id = auth.uid() or public.is_vault_member(id));
create policy "vaults: owner inserts" on public.family_vaults
  for insert with check (owner_auth_user_id = auth.uid());
create policy "vaults: owner updates" on public.family_vaults
  for update using (owner_auth_user_id = auth.uid())
  with check (owner_auth_user_id = auth.uid());
create policy "vaults: owner deletes" on public.family_vaults
  for delete using (owner_auth_user_id = auth.uid());

-- vault_members
drop policy if exists "members: members read"  on public.vault_members;
drop policy if exists "members: admins insert" on public.vault_members;
drop policy if exists "members: admins update" on public.vault_members;
drop policy if exists "members: admins delete" on public.vault_members;
create policy "members: members read" on public.vault_members
  for select using (public.is_vault_member(vault_id));
create policy "members: admins insert" on public.vault_members
  for insert with check (public.is_vault_admin(vault_id));
create policy "members: admins update" on public.vault_members
  for update using (public.is_vault_admin(vault_id))
  with check (public.is_vault_admin(vault_id) and role <> 'owner');
create policy "members: admins delete" on public.vault_members
  for delete using (
    (public.is_vault_admin(vault_id) and role <> 'owner')
    or (auth_user_id = auth.uid() and role <> 'owner')
  );

-- vault_invitations
drop policy if exists "invites: admins or invitee read"   on public.vault_invitations;
drop policy if exists "invites: admins insert"            on public.vault_invitations;
drop policy if exists "invites: admins or invitee update" on public.vault_invitations;
drop policy if exists "invites: admins delete"            on public.vault_invitations;
create policy "invites: admins or invitee read" on public.vault_invitations
  for select using (
    public.is_vault_admin(vault_id)
    or (status = 'pending' and (
         (email is not null and lower(email) = lower(coalesce(public.ino_current_email(), '')))
      or (phone is not null and phone = coalesce(public.ino_current_phone(), ''))
    ))
  );
create policy "invites: admins insert" on public.vault_invitations
  for insert with check (
    public.is_vault_admin(vault_id) and role in ('admin','editor','viewer')
  );
create policy "invites: admins or invitee update" on public.vault_invitations
  for update using (
    public.is_vault_admin(vault_id)
    or (email is not null and lower(email) = lower(coalesce(public.ino_current_email(), '')))
    or (phone is not null and phone = coalesce(public.ino_current_phone(), ''))
  );
create policy "invites: admins delete" on public.vault_invitations
  for delete using (public.is_vault_admin(vault_id));

-- vault_audit_log — admins/owner read; no client writes.
drop policy if exists "audit: admins read" on public.vault_audit_log;
create policy "audit: admins read" on public.vault_audit_log
  for select using (public.is_vault_admin(vault_id));

-- vault_notification_events — no client access (service role / SECURITY DEFINER only).

-- ----------------------------------------------------------------------------
-- 8. TABLE GRANTS (RLS still applies).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete
  on public.family_vaults, public.vault_members, public.vault_invitations
  to authenticated;
grant select on public.vault_audit_log to authenticated;

-- ----------------------------------------------------------------------------
-- 9. REALTIME
-- ----------------------------------------------------------------------------
do $$
declare tbl text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach tbl in array array['family_vaults','vault_members','vault_invitations'] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = tbl
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tbl);
    end if;
  end loop;
end $$;

alter table public.vault_members     replica identity full;
alter table public.vault_invitations replica identity full;
alter table public.family_vaults     replica identity full;

notify pgrst, 'reload schema';

commit;

-- ============================================================================
-- VERIFICATION (read-only) — run these AFTER the migration commits.
-- ============================================================================
-- A) All 8 required RPCs exist (expect exactly 8 rows):
select proname
from pg_proc
where proname in (
  'invite_to_vault','accept_vault_invitation','decline_vault_invitation',
  'cancel_vault_invitation','resend_vault_invitation','transfer_vault_ownership',
  'set_vault_member_role','remove_vault_member'
)
order by proname;

-- B) All 5 tables exist (expect 5 rows):
select table_name from information_schema.tables
 where table_schema = 'public'
   and table_name in ('family_vaults','vault_members','vault_invitations',
                      'vault_audit_log','vault_notification_events')
 order by table_name;

-- C) EXECUTE granted to authenticated on every RPC (expect 8 rows, all 'true'):
select p.proname, has_function_privilege('authenticated', p.oid, 'execute') as can_exec
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in (
    'invite_to_vault','accept_vault_invitation','decline_vault_invitation',
    'cancel_vault_invitation','resend_vault_invitation','transfer_vault_ownership',
    'set_vault_member_role','remove_vault_member')
order by p.proname;
