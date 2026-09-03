-- ============================================================================
-- INO — Family Vault: invite any INO user, join-by-name requests, co-owners
-- ----------------------------------------------------------------------------
-- What this adds (all server-authoritative, SECURITY DEFINER RPCs, audited):
--
--   1. invite_ino_user_to_vault(vault, role, query)
--        Invite by PHONE, NAME or EMAIL. The query is resolved against
--        public.users; if nobody matches the call fails with a clear
--        USER_NOT_FOUND error (errcode P0002) so the app can tell the inviter
--        to have the person install INO first. Ambiguous names fail with
--        P0003 (too_many_rows) - use phone/email instead.
--        The invitation is bound to the resolved account
--        (vault_invitations.invitee_auth_user_id), so the invitee sees it
--        regardless of email casing / phone formatting, and the push trigger
--        can reach them by phone as well as email.
--
--   2. Join requests — search_families(name) → request_to_join_family(vault)
--        A user who was not invited can look a family up by its exact name
--        and ask to join. Every owner/admin of that family is notified and
--        can approve_join_request() (with a role) or decline_join_request().
--
--   3. Co-owners — promote_vault_member_to_owner(member)
--        A vault may now have SEVERAL members with role 'owner'. Every owner
--        can invite, approve joins, add documents, rename, promote others and
--        demote non-primary owners. family_vaults.owner_auth_user_id remains
--        the PRIMARY owner: only they can delete the vault or transfer that
--        primary role, and their own owner role cannot be removed by others.
--
-- Idempotent + production-safe. Requires 20260728 … 20260812 applied.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 0. Helpers
-- ----------------------------------------------------------------------------

-- Last 10 digits of a phone number, ignoring +country, spaces and dashes, so
-- "+91 98765 43210", "9876543210" and "098765-43210" all compare equal.
create or replace function public.ino_phone_digits(p text)
  returns text language sql immutable as $$
  select right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 10);
$$;

-- Any member holding the 'owner' role (co-owners included).
create or replace function public.is_vault_owner(p_vault uuid)
  returns boolean language sql security definer stable
  set search_path = public
as $$
  select exists(
    select 1 from public.vault_members m
    where m.vault_id = p_vault
      and m.auth_user_id = auth.uid()
      and m.role = 'owner'
  );
$$;

-- The creator / primary owner (may delete + transfer).
create or replace function public.is_vault_primary_owner(p_vault uuid)
  returns boolean language sql security definer stable
  set search_path = public
as $$
  select exists(
    select 1 from public.family_vaults v
    where v.id = p_vault and v.owner_auth_user_id = auth.uid()
  );
$$;

grant execute on function public.ino_phone_digits(text) to authenticated;
grant execute on function public.is_vault_owner(uuid) to authenticated;
grant execute on function public.is_vault_primary_owner(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 1. Invitations bound to an account
-- ----------------------------------------------------------------------------
alter table public.vault_invitations
  add column if not exists invitee_auth_user_id uuid
    references auth.users (id) on delete cascade;

create index if not exists vault_invitations_invitee_idx
  on public.vault_invitations (invitee_auth_user_id)
  where invitee_auth_user_id is not null;

-- "Is this invitation addressed to the caller?" - by account first, then by
-- the profile's email / phone (older invitations, and phone-only invites).
create or replace function public.ino_invitation_is_mine(inv public.vault_invitations)
  returns boolean language sql security definer stable
  set search_path = public
as $$
  select auth.uid() is not null and (
       inv.invitee_auth_user_id = auth.uid()
    or (inv.email is not null
        and lower(inv.email) = lower(coalesce(public.ino_current_email(), '')))
    or (inv.phone is not null
        and public.ino_phone_digits(inv.phone) <> ''
        and public.ino_phone_digits(inv.phone)
            = public.ino_phone_digits(coalesce(public.ino_current_phone(), '')))
  );
$$;

drop policy if exists "invites: admins or invitee read"   on public.vault_invitations;
drop policy if exists "invites: admins or invitee update" on public.vault_invitations;

create policy "invites: admins or invitee read" on public.vault_invitations
  for select using (
    public.is_vault_admin(vault_id)
    or (status = 'pending' and public.ino_invitation_is_mine(vault_invitations))
  );
create policy "invites: admins or invitee update" on public.vault_invitations
  for update using (
    public.is_vault_admin(vault_id)
    or public.ino_invitation_is_mine(vault_invitations)
  );

-- accept / decline now use the same "is mine" rule.
create or replace function public.accept_vault_invitation(p_invitation_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  inv     public.vault_invitations%rowtype;
  v_name  text; v_email text; v_phone text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to accept an invitation' using errcode = '28000';
  end if;
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then
    raise exception 'Invitation not found' using errcode = 'P0002';
  end if;
  if inv.status <> 'pending' then
    raise exception 'This invitation is no longer pending' using errcode = '22023';
  end if;
  if inv.expires_at < now() then
    update public.vault_invitations set status = 'expired' where id = inv.id;
    raise exception 'This invitation has expired' using errcode = '22023';
  end if;
  if not public.ino_invitation_is_mine(inv) then
    raise exception 'This invitation is not addressed to you' using errcode = '42501';
  end if;

  select full_name, email, phone into v_name, v_email, v_phone
    from public.users where auth_user_id = auth.uid() limit 1;

  insert into public.vault_members
    (vault_id, auth_user_id, role, display_name, email, phone)
  values
    (inv.vault_id, auth.uid(), inv.role,
     coalesce(v_name, inv.invited_name, 'Member'), v_email, v_phone)
  on conflict (vault_id, auth_user_id) do update set role = excluded.role;

  update public.vault_invitations
     set status = 'accepted', responded_by = auth.uid(),
         responded_at = now(), accepted_at = now(),
         invitee_auth_user_id = coalesce(invitee_auth_user_id, auth.uid())
   where id = inv.id;

  perform public.ino_log_vault_event(
    inv.vault_id, 'invite_accepted', 'invitation', inv.id,
    coalesce(v_name, v_email, v_phone), jsonb_build_object('role', inv.role));
  perform public.ino_enqueue_vault_notification(
    'invitation.accepted', inv.vault_id, inv.invited_by, null, null,
    jsonb_build_object('member_name', coalesce(v_name, v_email, v_phone), 'role', inv.role));
end;
$$;

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
  if inv.id is null or inv.status <> 'pending' then
    return;
  end if;
  if not public.ino_invitation_is_mine(inv) then
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

-- ----------------------------------------------------------------------------
-- 2. invite_ino_user_to_vault — by phone, name or email; must be an INO user.
-- ----------------------------------------------------------------------------
create or replace function public.invite_ino_user_to_vault(
  p_vault uuid,
  p_role  text,
  p_query text
)
  returns public.vault_invitations
  language plpgsql security definer set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_q          text := trim(coalesce(p_query, ''));
  v_kind       text;
  v_count      int;
  v_target     public.users%rowtype;
  v_vault_name text;
  v_inviter    text;
  v_row        public.vault_invitations;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  if not public.is_vault_admin(p_vault) then
    raise exception 'Only an owner or admin can invite members' using errcode = '42501';
  end if;
  if p_role not in ('admin', 'editor', 'viewer') then
    raise exception 'Invalid role (owner cannot be invited)' using errcode = '22023';
  end if;
  if v_q = '' then
    raise exception 'Enter a phone number, name or email' using errcode = '22023';
  end if;

  -- Resolve the identifier to exactly one INO account.
  if v_q like '%@%' then
    v_kind := 'email';
    select count(*) into v_count from public.users u where lower(u.email) = lower(v_q);
    select * into v_target from public.users u where lower(u.email) = lower(v_q) limit 1;
  elsif v_q ~ '^[+()\s\d-]+$' and length(public.ino_phone_digits(v_q)) >= 8 then
    v_kind := 'phone';
    select count(*) into v_count from public.users u
     where public.ino_phone_digits(u.phone) = public.ino_phone_digits(v_q);
    select * into v_target from public.users u
     where public.ino_phone_digits(u.phone) = public.ino_phone_digits(v_q)
     order by u.created_at limit 1;
  else
    v_kind := 'name';
    select count(*) into v_count from public.users u
     where lower(trim(u.full_name)) = lower(v_q);
    if v_count = 0 then
      -- Fall back to a prefix match ("Tanvi" → "Tanvi Tiwaskar").
      select count(*) into v_count from public.users u
       where lower(trim(u.full_name)) like lower(v_q) || '%';
      select * into v_target from public.users u
       where lower(trim(u.full_name)) like lower(v_q) || '%' limit 1;
    else
      select * into v_target from public.users u
       where lower(trim(u.full_name)) = lower(v_q) limit 1;
    end if;
    if v_count > 1 then
      raise exception 'More than one INO user is named "%". Use their phone number or email instead.', v_q
        using errcode = 'P0003', hint = 'MULTIPLE_USERS';
    end if;
  end if;

  if v_count = 0 or v_target.auth_user_id is null then
    raise exception 'No INO account matches "%". Ask them to install INO and create an account first.', v_q
      using errcode = 'P0002', hint = 'USER_NOT_FOUND';
  end if;

  if v_target.auth_user_id = v_uid then
    raise exception 'You can''t invite yourself' using errcode = '22023';
  end if;
  if exists (select 1 from public.vault_members m
              where m.vault_id = p_vault and m.auth_user_id = v_target.auth_user_id) then
    raise exception 'That person is already a member of this vault' using errcode = '23505';
  end if;
  if exists (select 1 from public.vault_invitations i
              where i.vault_id = p_vault and i.status = 'pending'
                and (i.invitee_auth_user_id = v_target.auth_user_id
                  or (v_target.email is not null and lower(i.email) = lower(v_target.email))
                  or (v_target.phone is not null and i.phone = v_target.phone))) then
    raise exception 'There is already a pending invitation for that person' using errcode = '23505';
  end if;

  select name into v_vault_name from public.family_vaults where id = p_vault;
  select full_name into v_inviter from public.users where auth_user_id = v_uid;

  insert into public.vault_invitations
    (vault_id, invited_by, role, email, phone, invited_name, status,
     vault_name, invited_by_name, invitee_auth_user_id)
  values
    (p_vault, v_uid, p_role, nullif(lower(trim(v_target.email)), ''),
     nullif(trim(v_target.phone), ''), v_target.full_name, 'pending',
     coalesce(v_vault_name, 'Family Vault'), v_inviter, v_target.auth_user_id)
  returning * into v_row;

  perform public.ino_log_vault_event(
    p_vault, 'invite_sent', 'invitation', v_row.id,
    coalesce(v_target.full_name, v_target.email, v_target.phone),
    jsonb_build_object('role', p_role, 'via', v_kind));
  perform public.ino_enqueue_vault_notification(
    'invitation.created', p_vault, v_target.auth_user_id, v_target.email, v_target.phone,
    jsonb_build_object('invitation_id', v_row.id,
                       'vault_name', coalesce(v_vault_name, 'Family Vault'),
                       'role', p_role, 'invited_by_name', v_inviter));
  return v_row;
end;
$$;

revoke all on function public.invite_ino_user_to_vault(uuid, text, text) from public;
grant execute on function public.invite_ino_user_to_vault(uuid, text, text) to authenticated;

-- The push trigger: reach the invitee by account id, else by email OR phone
-- (the previous version only matched email, so phone invites never pushed).
create or replace function public.tg_vault_invitation_push()
returns trigger language plpgsql security definer set search_path = public
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
    select u.auth_user_id into v_invitee from public.users u
     where (new.email is not null and lower(u.email) = lower(new.email))
        or (new.phone is not null
            and public.ino_phone_digits(u.phone) <> ''
            and public.ino_phone_digits(u.phone) = public.ino_phone_digits(new.phone))
     limit 1;
  end if;
  if v_invitee is null or v_invitee = new.invited_by then
    return new;
  end if;

  select name into v_vault from public.family_vaults where id = new.vault_id;
  v_by := nullif(trim(coalesce(new.invited_by_name, '')), '');

  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  values (
    v_invitee,
    'vault.invite',
    'Family vault invitation',
    coalesce(v_by || ' invited you', 'You have been invited')
      || ' to join ' || coalesce(nullif(trim(v_vault), ''), 'a family vault')
      || ' as ' || new.role || '. Open INO to accept.',
    'ino_reminders',
    'invite:' || new.id::text || ':' || coalesce(new.updated_at, new.created_at)::text,
    jsonb_build_object('kind', 'vault.invite', 'vault_id', new.vault_id::text,
                       'invitation_id', new.id::text)
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;

  return new;
exception when others then
  return new;   -- a notification must never block the invite itself
end;
$$;

drop trigger if exists vault_invitation_push on public.vault_invitations;
create trigger vault_invitation_push
  after insert or update of status on public.vault_invitations
  for each row execute function public.tg_vault_invitation_push();

-- ----------------------------------------------------------------------------
-- 3. Join requests
-- ----------------------------------------------------------------------------
create table if not exists public.vault_join_requests (
  id                      uuid primary key default gen_random_uuid(),
  vault_id                uuid not null references public.family_vaults (id) on delete cascade,
  requester_auth_user_id  uuid not null references auth.users (id) on delete cascade,
  requester_name          text,
  requester_email         text,
  requester_phone         text,
  vault_name              text,
  message                 text,
  status                  text not null default 'pending'
                          check (status in ('pending', 'approved', 'declined', 'cancelled')),
  responded_by            uuid references auth.users (id) on delete set null,
  responded_at            timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.vault_join_requests is
  'A user asking to join a Family Vault they found by name. Owners/admins approve or decline via RPC.';

create unique index if not exists vault_join_requests_pending_uniq
  on public.vault_join_requests (vault_id, requester_auth_user_id)
  where status = 'pending';
create index if not exists vault_join_requests_vault_idx
  on public.vault_join_requests (vault_id, status);
create index if not exists vault_join_requests_requester_idx
  on public.vault_join_requests (requester_auth_user_id, status);

drop trigger if exists trg_touch_join_requests on public.vault_join_requests;
create trigger trg_touch_join_requests
  before update on public.vault_join_requests
  for each row execute function public.ino_touch_updated_at();

alter table public.vault_join_requests enable row level security;

drop policy if exists "join requests: requester or admins read" on public.vault_join_requests;
create policy "join requests: requester or admins read" on public.vault_join_requests
  for select using (
    requester_auth_user_id = auth.uid() or public.is_vault_admin(vault_id)
  );
-- No insert/update/delete policies: every write goes through the RPCs below.
grant select on public.vault_join_requests to authenticated;

-- search_families: exact (case-insensitive) name match. Only what a requester
-- needs to pick the right family: its name, who owns it and how big it is.
create or replace function public.search_families(p_name text)
  returns table (
    id uuid, name text, owner_name text, member_count bigint,
    already_member boolean, request_pending boolean
  )
  language sql security definer stable set search_path = public
as $$
  select v.id, v.name,
         (select m.display_name from public.vault_members m
           where m.vault_id = v.id and m.auth_user_id = v.owner_auth_user_id limit 1),
         (select count(*) from public.vault_members m where m.vault_id = v.id),
         exists (select 1 from public.vault_members m
                  where m.vault_id = v.id and m.auth_user_id = auth.uid()),
         exists (select 1 from public.vault_join_requests r
                  where r.vault_id = v.id and r.requester_auth_user_id = auth.uid()
                    and r.status = 'pending')
    from public.family_vaults v
   where auth.uid() is not null
     and length(trim(coalesce(p_name, ''))) >= 2
     and lower(trim(v.name)) = lower(trim(p_name))
   order by v.created_at
   limit 10;
$$;

create or replace function public.request_to_join_family(
  p_vault   uuid,
  p_message text default null
)
  returns public.vault_join_requests
  language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_name  text; v_email text; v_phone text; v_vault text;
  v_row   public.vault_join_requests;
  v_admin record;
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select name into v_vault from public.family_vaults where id = p_vault;
  if v_vault is null then
    raise exception 'That family no longer exists' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.vault_members m
              where m.vault_id = p_vault and m.auth_user_id = v_uid) then
    raise exception 'You are already a member of this family' using errcode = '23505';
  end if;
  if exists (select 1 from public.vault_join_requests r
              where r.vault_id = p_vault and r.requester_auth_user_id = v_uid
                and r.status = 'pending') then
    raise exception 'You already have a pending request for this family' using errcode = '23505';
  end if;

  select full_name, email, phone into v_name, v_email, v_phone
    from public.users where auth_user_id = v_uid limit 1;

  insert into public.vault_join_requests
    (vault_id, requester_auth_user_id, requester_name, requester_email,
     requester_phone, vault_name, message)
  values
    (p_vault, v_uid, coalesce(v_name, v_email, v_phone, 'An INO user'),
     v_email, v_phone, v_vault, nullif(trim(coalesce(p_message, '')), ''))
  returning * into v_row;

  perform public.ino_log_vault_event(
    p_vault, 'join_requested', 'join_request', v_row.id, v_row.requester_name, '{}'::jsonb);

  -- Tell every owner/admin of the family.
  for v_admin in
    select m.auth_user_id from public.vault_members m
     where m.vault_id = p_vault and m.role in ('owner', 'admin')
  loop
    insert into public.notification_outbox
      (auth_user_id, kind, title, body, channel, dedupe_key, data)
    values (
      v_admin.auth_user_id,
      'vault.join_request',
      'Request to join ' || v_vault,
      v_row.requester_name || ' wants to join ' || v_vault || '. Open INO to approve or decline.',
      'ino_reminders',
      'joinreq:' || v_row.id::text || ':' || v_admin.auth_user_id::text,
      jsonb_build_object('kind', 'vault.join_request', 'vault_id', p_vault::text,
                         'request_id', v_row.id::text)
    )
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end loop;
  perform public.ino_enqueue_vault_notification(
    'join.requested', p_vault, null, null, null,
    jsonb_build_object('request_id', v_row.id, 'requester', v_row.requester_name));

  return v_row;
end;
$$;

create or replace function public.approve_join_request(
  p_request uuid,
  p_role    text default 'viewer'
)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  r public.vault_join_requests%rowtype;
  v_name text; v_email text; v_phone text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into r from public.vault_join_requests where id = p_request;
  if r.id is null then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if not public.is_vault_admin(r.vault_id) then
    raise exception 'Only an owner or admin can approve join requests' using errcode = '42501';
  end if;
  if r.status <> 'pending' then
    raise exception 'This request is no longer pending' using errcode = '22023';
  end if;
  if p_role not in ('admin', 'editor', 'viewer') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;

  -- Fresh profile data, so the roster shows their current name.
  select full_name, email, phone into v_name, v_email, v_phone
    from public.users where auth_user_id = r.requester_auth_user_id limit 1;

  insert into public.vault_members
    (vault_id, auth_user_id, role, display_name, email, phone)
  values
    (r.vault_id, r.requester_auth_user_id, p_role,
     coalesce(v_name, r.requester_name, 'Member'),
     coalesce(v_email, r.requester_email), coalesce(v_phone, r.requester_phone))
  on conflict (vault_id, auth_user_id) do update set role = excluded.role;

  update public.vault_join_requests
     set status = 'approved', responded_by = auth.uid(), responded_at = now()
   where id = r.id;

  perform public.ino_log_vault_event(
    r.vault_id, 'join_approved', 'member', r.id, coalesce(v_name, r.requester_name),
    jsonb_build_object('role', p_role));

  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  values (
    r.requester_auth_user_id,
    'vault.join_approved',
    'Welcome to ' || coalesce(r.vault_name, 'the family vault'),
    'Your request to join ' || coalesce(r.vault_name, 'the family vault')
      || ' was approved. You are now ' || p_role || '.',
    'ino_reminders',
    'joinok:' || r.id::text,
    jsonb_build_object('kind', 'vault.join_approved', 'vault_id', r.vault_id::text)
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  perform public.ino_enqueue_vault_notification(
    'join.approved', r.vault_id, r.requester_auth_user_id, r.requester_email, r.requester_phone,
    jsonb_build_object('role', p_role));
end;
$$;

create or replace function public.decline_join_request(p_request uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  r public.vault_join_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into r from public.vault_join_requests where id = p_request;
  if r.id is null or r.status <> 'pending' then return; end if;
  if not public.is_vault_admin(r.vault_id) then
    raise exception 'Only an owner or admin can decline join requests' using errcode = '42501';
  end if;
  update public.vault_join_requests
     set status = 'declined', responded_by = auth.uid(), responded_at = now()
   where id = r.id;
  perform public.ino_log_vault_event(
    r.vault_id, 'join_declined', 'join_request', r.id, r.requester_name, '{}'::jsonb);
  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  values (
    r.requester_auth_user_id,
    'vault.join_declined',
    'Join request declined',
    'Your request to join ' || coalesce(r.vault_name, 'the family vault') || ' was declined.',
    'ino_reminders',
    'joinno:' || r.id::text,
    jsonb_build_object('kind', 'vault.join_declined', 'vault_id', r.vault_id::text)
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

create or replace function public.cancel_join_request(p_request uuid)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.vault_join_requests
     set status = 'cancelled', responded_by = auth.uid(), responded_at = now()
   where id = p_request
     and requester_auth_user_id = auth.uid()
     and status = 'pending';
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Co-owners
-- ----------------------------------------------------------------------------
create or replace function public.promote_vault_member_to_owner(p_member_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  m public.vault_members%rowtype;
  v_vault text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into m from public.vault_members where id = p_member_id;
  if m.id is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if not public.is_vault_owner(m.vault_id) then
    raise exception 'Only an owner can make another member an owner' using errcode = '42501';
  end if;
  if m.role = 'owner' then return; end if;

  update public.vault_members set role = 'owner' where id = m.id;
  select name into v_vault from public.family_vaults where id = m.vault_id;

  perform public.ino_log_vault_event(
    m.vault_id, 'owner_added', 'member', m.id, m.display_name,
    jsonb_build_object('from', m.role, 'to', 'owner'));
  perform public.ino_enqueue_vault_notification(
    'member.role_changed', m.vault_id, m.auth_user_id, m.email, m.phone,
    jsonb_build_object('from', m.role, 'to', 'owner'));
  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  values (
    m.auth_user_id,
    'vault.role_changed',
    'You are now an owner',
    'You were made an owner of ' || coalesce(v_vault, 'a family vault')
      || '. You can invite members and add documents.',
    'ino_reminders',
    'owner:' || m.id::text || ':' || now()::text,
    jsonb_build_object('kind', 'vault.role_changed', 'vault_id', m.vault_id::text)
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

-- set_vault_member_role: owners may now demote a NON-primary co-owner.
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
  if m.id is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if not public.is_vault_admin(m.vault_id) then
    raise exception 'Only an owner or admin can change roles' using errcode = '42501';
  end if;
  if p_role not in ('admin', 'editor', 'viewer') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  if m.role = 'owner' then
    if not public.is_vault_owner(m.vault_id) then
      raise exception 'Only an owner can change another owner''s role' using errcode = '42501';
    end if;
    if exists (select 1 from public.family_vaults v
                where v.id = m.vault_id and v.owner_auth_user_id = m.auth_user_id) then
      raise exception 'The primary owner''s role can''t be changed — transfer ownership instead'
        using errcode = '42501';
    end if;
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

-- remove_vault_member: a co-owner may be removed by an owner (or leave); the
-- PRIMARY owner still cannot be removed without a transfer.
create or replace function public.remove_vault_member(p_member_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare
  m public.vault_members%rowtype;
  v_self boolean;
  v_primary boolean;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into m from public.vault_members where id = p_member_id;
  if m.id is null then return; end if;
  v_self := (m.auth_user_id = auth.uid());
  v_primary := exists (select 1 from public.family_vaults v
                        where v.id = m.vault_id and v.owner_auth_user_id = m.auth_user_id);
  if v_primary then
    raise exception 'The primary owner can''t be removed — transfer ownership first'
      using errcode = '42501';
  end if;
  if m.role = 'owner' and not v_self and not public.is_vault_owner(m.vault_id) then
    raise exception 'Only an owner can remove another owner' using errcode = '42501';
  end if;
  if not (public.is_vault_admin(m.vault_id) or v_self) then
    raise exception 'You don''t have permission to remove this member' using errcode = '42501';
  end if;
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

-- rename: any owner. (delete + transfer stay with the primary owner.)
create or replace function public.rename_family_vault(
  p_vault uuid,
  p_name  text
)
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
  if not public.is_vault_owner(p_vault) then
    raise exception 'Only an owner can rename this vault' using errcode = '42501';
  end if;
  select name into v_old from public.family_vaults where id = p_vault;
  update public.family_vaults set name = v_name where id = p_vault
   returning * into v_row;
  -- Keep the denormalised copies in step so invitation / request cards show
  -- the current name.
  update public.vault_invitations  set vault_name = v_name where vault_id = p_vault;
  update public.vault_join_requests set vault_name = v_name where vault_id = p_vault;

  perform public.ino_log_vault_event(
    p_vault, 'vault_renamed', 'vault', p_vault, v_name,
    jsonb_build_object('from', v_old, 'to', v_name));
  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Grants + realtime
-- ----------------------------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'accept_vault_invitation(uuid)',
    'decline_vault_invitation(uuid)',
    'invite_ino_user_to_vault(uuid,text,text)',
    'search_families(text)',
    'request_to_join_family(uuid,text)',
    'approve_join_request(uuid,text)',
    'decline_join_request(uuid)',
    'cancel_join_request(uuid)',
    'promote_vault_member_to_owner(uuid)',
    'set_vault_member_role(uuid,text)',
    'remove_vault_member(uuid)',
    'rename_family_vault(uuid,text)'
  ] loop
    execute format('revoke all on function public.%s from public', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'vault_join_requests'
  ) then
    alter publication supabase_realtime add table public.vault_join_requests;
  end if;
end $$;
alter table public.vault_join_requests replica identity full;

notify pgrst, 'reload schema';

commit;

-- ============================================================================
-- VERIFICATION (read-only)
-- ----------------------------------------------------------------------------
-- 1) New RPCs present (expect 8):
--     select proname from pg_proc where pronamespace = 'public'::regnamespace
--       and proname in ('invite_ino_user_to_vault','search_families',
--         'request_to_join_family','approve_join_request','decline_join_request',
--         'cancel_join_request','promote_vault_member_to_owner','is_vault_owner')
--      order by proname;
-- 2) Column + table exist:
--     select column_name from information_schema.columns
--      where table_name = 'vault_invitations' and column_name = 'invitee_auth_user_id';
--     select count(*) from public.vault_join_requests;
-- 3) As a signed-in owner, invite by name / phone / email:
--     select * from public.invite_ino_user_to_vault('<vault id>', 'viewer', '9876543210');
--    A number nobody has → ERROR P0002 "No INO account matches …" (expected).
-- ============================================================================
