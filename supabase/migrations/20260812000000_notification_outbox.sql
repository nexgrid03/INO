-- ============================================================================
-- INO - Notification outbox
-- ----------------------------------------------------------------------------
-- Until now push covered exactly one thing: reminders. Everything else the app
-- knew about — a passport expiring, a card expiring, a sign-in, a vault invite
-- — was computed inside NotificationCenter and therefore only ever visible to
-- someone who already had the app open. This table is the delivery path.
--
-- WHY AN OUTBOX RATHER THAN SENDING DIRECTLY
--
-- The events come from three very different places:
--   • date-based    (document / card expiry)  — found by a daily scan,
--   • app-initiated (sign-in, password, 2FA)  — known only to the client,
--   • data-driven   (vault invite)            — a plain INSERT on a table.
--
-- Funnelling all three into one durable queue means there is exactly ONE sender
-- (`send-push`), one dedupe rule, one retry story and one place to look when a
-- notification did not arrive. Rows are written by whoever knows about the
-- event; the sender drains them.
--
-- Idempotent - safe to re-run. Core Postgres only.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The queue
-- ----------------------------------------------------------------------------
create table if not exists public.notification_outbox (
  id            uuid primary key default gen_random_uuid(),

  -- Who this is FOR. Every row fans out to that user's device_tokens.
  auth_user_id  uuid not null references auth.users (id) on delete cascade,

  -- Stable machine key, e.g. 'doc.expiry', 'security.new_signin'. The app taps
  -- route on this, so treat the values as a contract (see PushService).
  kind          text not null,

  title         text not null,
  body          text not null,

  -- Extra payload mirrored into FCM `data` (document ids, vault ids …). A
  -- `notification` payload is NOT handed to Dart when the app is backgrounded,
  -- so anything the tap handler needs must live here.
  data          jsonb not null default '{}'::jsonb,

  -- Android channel id. Must exist on the device or Android 8+ silently drops
  -- the notification — see PushService.channelId / securityChannelId.
  channel       text not null default 'ino_reminders',

  -- The device that CAUSED the event, which must not be told about it. Someone
  -- who just signed in on this phone does not need "a new sign-in happened";
  -- their other devices do. Null = send everywhere.
  exclude_token text,

  -- Natural key for "this exact notification, once". Lets the daily scan run as
  -- often as it likes without re-notifying: a second insert for
  -- 'doc:<id>:d7' is swallowed by the unique index below.
  -- Null for events that are inherently unique (a sign-in at 10:04).
  dedupe_key    text,

  created_at    timestamptz not null default now(),
  sent_at       timestamptz,
  attempts      integer not null default 0
);

comment on table public.notification_outbox is
  'Durable queue of push notifications waiting to be delivered by the send-push Edge Function. Written by triggers, by the daily expiry scan, and by the app for client-known events.';
comment on column public.notification_outbox.exclude_token is
  'FCM token of the device that caused the event; it is skipped when fanning out. Null sends to every device.';
comment on column public.notification_outbox.dedupe_key is
  'Uniqueness key so a repeated scan cannot re-notify. Null means "always distinct".';

-- Partial unique: only rows that opt into deduping are constrained, so the
-- many null-keyed event rows do not collide with each other.
create unique index if not exists notification_outbox_dedupe_idx
  on public.notification_outbox (dedupe_key)
  where dedupe_key is not null;

-- The sender's hot path: undelivered rows, oldest first.
create index if not exists notification_outbox_pending_idx
  on public.notification_outbox (created_at)
  where sent_at is null;

-- ----------------------------------------------------------------------------
-- 2. Row Level Security
-- ----------------------------------------------------------------------------
-- The app writes its OWN client-known events (sign-in, password, 2FA), so it
-- needs insert. It must never be able to write a row aimed at somebody else,
-- nor invent an arbitrary `kind` — a forged 'security.*' notification is a
-- phishing primitive, so the allowed kinds are pinned here rather than trusted
-- from the client.
--
-- The Edge Function reads and updates with the service role, which bypasses RLS
-- by design; that is how one run fans out across every user.
alter table public.notification_outbox enable row level security;

drop policy if exists "outbox: owner reads own"   on public.notification_outbox;
drop policy if exists "outbox: owner inserts own" on public.notification_outbox;

create policy "outbox: owner reads own" on public.notification_outbox
  for select using (auth_user_id = auth.uid());

create policy "outbox: owner inserts own" on public.notification_outbox
  for insert with check (
    auth_user_id = auth.uid()
    and kind in (
      'security.new_signin',
      'security.password_changed',
      'security.two_factor_changed'
    )
  );

-- ----------------------------------------------------------------------------
-- 3. enqueue_security_event() - the app's only way in
-- ----------------------------------------------------------------------------
-- A SECURITY DEFINER wrapper so the client never composes the row itself. The
-- copy is written here, server-side: a client that could choose the title could
-- make a notification say anything, and these are exactly the notifications a
-- user is most likely to trust.
create or replace function public.enqueue_security_event(
  p_kind          text,
  p_detail        text default null,
  p_exclude_token text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_title text;
  v_body  text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  case p_kind
    when 'security.new_signin' then
      v_title := 'New sign-in to your INO account';
      v_body  := coalesce(
        'Signed in on ' || nullif(trim(p_detail), ''),
        'Your account was signed in on another device.'
      ) || ' If this was not you, change your password now.';
    when 'security.password_changed' then
      v_title := 'Your password was changed';
      v_body  := 'If you did not do this, reset your password and review your trusted devices.';
    when 'security.two_factor_changed' then
      v_title := 'Two-factor authentication changed';
      v_body  := coalesce(nullif(trim(p_detail), ''), 'Your 2FA settings were updated.')
                 || ' If this was not you, secure your account now.';
    else
      raise exception 'Unknown security event kind: %', p_kind;
  end case;

  -- Only worth sending if there is a SECOND device to warn. With one device the
  -- person reading the alert is the person who just performed the action.
  if not exists (
    select 1 from public.device_tokens t
    where t.auth_user_id = v_uid
      and (p_exclude_token is null or t.token <> p_exclude_token)
  ) then
    return;
  end if;

  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, exclude_token, data)
  values
    (v_uid, p_kind, v_title, v_body, 'ino_security', p_exclude_token,
     jsonb_build_object('kind', p_kind));
end;
$$;

revoke all on function public.enqueue_security_event(text, text, text) from public;
grant execute on function public.enqueue_security_event(text, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Family vault invite - a data-driven trigger
-- ----------------------------------------------------------------------------
-- An invitation nobody sees is a dead feature, and the invitee is by definition
-- not looking at the app. Fires only when the invited email belongs to an
-- existing INO account; a brand-new user has no device to reach yet and gets
-- the invite when they sign up.
create or replace function public.tg_vault_invitation_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitee uuid;
  v_vault   text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;
  if coalesce(new.email, '') = '' then
    return new;   -- phone-only invite: no account to map to
  end if;

  select id into v_invitee
  from auth.users
  where lower(email) = lower(new.email)
  limit 1;

  if v_invitee is null or v_invitee = new.invited_by then
    return new;   -- not a user yet, or inviting themselves
  end if;

  select name into v_vault from public.family_vaults where id = new.vault_id;

  insert into public.notification_outbox
    (auth_user_id, kind, title, body, channel, dedupe_key, data)
  values (
    v_invitee,
    'vault.invite',
    'Family vault invitation',
    'You have been invited to join '
      || coalesce(nullif(trim(v_vault), ''), 'a family vault')
      || ' as ' || new.role || '.',
    'ino_reminders',
    'invite:' || new.id::text,
    jsonb_build_object('kind', 'vault.invite', 'vault_id', new.vault_id::text,
                       'invitation_id', new.id::text)
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;

  return new;
exception when others then
  -- A notification must never be able to block the invite itself.
  return new;
end;
$$;

drop trigger if exists vault_invitation_push on public.vault_invitations;
create trigger vault_invitation_push
  after insert on public.vault_invitations
  for each row execute function public.tg_vault_invitation_push();

-- ----------------------------------------------------------------------------
-- 5. Password change - covers the paths the app cannot see
-- ----------------------------------------------------------------------------
-- The app enqueues its own password change, but a reset-by-email or an admin
-- change never touches the client. This trigger catches all of them.
--
-- `auth` is owned by supabase_auth_admin. Creating a trigger there is the same
-- officially-documented pattern as the usual handle_new_user hook, but if the
-- role running this migration lacks the privilege we degrade rather than fail
-- the whole migration — the in-app path still covers the common case.
create or replace function public.tg_auth_password_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    insert into public.notification_outbox
      (auth_user_id, kind, title, body, channel, data)
    values (
      new.id,
      'security.password_changed',
      'Your password was changed',
      'If you did not do this, reset your password and review your trusted devices.',
      'ino_security',
      jsonb_build_object('kind', 'security.password_changed')
    );
  end if;
  return new;
exception when others then
  return new;   -- never block an auth write
end;
$$;

do $$
begin
  execute 'drop trigger if exists ino_auth_password_changed on auth.users';
  execute 'create trigger ino_auth_password_changed
             after update of encrypted_password on auth.users
             for each row execute function public.tg_auth_password_changed()';
exception
  when insufficient_privilege then
    raise notice 'Skipped auth.users trigger (insufficient privilege). In-app password changes are still notified.';
  when others then
    raise notice 'Skipped auth.users trigger: %', sqlerrm;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Housekeeping
-- ----------------------------------------------------------------------------
-- Delivered rows are an audit trail for a little while, then noise.
create or replace function public.purge_sent_notifications()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with gone as (
    delete from public.notification_outbox
    where sent_at is not null and sent_at < now() - interval '30 days'
    returning 1
  )
  select count(*) into v_count from gone;
  return v_count;
end;
$$;

revoke all on function public.purge_sent_notifications() from public;
grant execute on function public.purge_sent_notifications() to service_role;
