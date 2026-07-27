-- ============================================================================
-- INO — Family Vault (complete backend)
-- ----------------------------------------------------------------------------
-- A Family Vault is a shared space owned by one user, with members who each
-- hold a role, and invitations for people who aren't members yet.
--
-- This ONE migration creates the entire Family Vault backend:
--   1.  family_vaults        — the vault, owned by its creator
--   2.  vault_members        — membership + role (owner/admin/editor/viewer)
--   3.  vault_invitations    — invite support (pending-invite-on-signup model)
--   4-7 roles + RLS          — role CHECKs + owner-only / member / admin policies
--   8.  invite support       — table, RLS, create + accept/decline logic
--   9.  auto owner trigger   — creator is added as 'owner' automatically
--   10. indexes              — on every foreign key / lookup column
--   11. helper functions     — SECURITY DEFINER membership + identity helpers
--
-- DESIGN NOTES
--  • Encryption model = at-rest + RLS (files stay in Storage; access gated by
--    membership). No client-side E2E.
--  • Member display name/email/phone are DENORMALIZED onto vault_members because
--    public.users is owner-only under RLS — co-members can't read each other's
--    profile rows, so a members list needs the info on the membership row.
--  • RLS recursion: a "you can read a vault_members row if you're a member of
--    that vault" policy would query vault_members from within a vault_members
--    policy → infinite recursion. The SECURITY DEFINER helpers
--    is_vault_member / is_vault_admin bypass RLS when evaluating membership, so
--    the policies never recurse.
--  • Invites to non-users: an invitation is keyed by email/phone. When that
--    person signs up (or is already a user), RLS lets them SEE invitations that
--    match their profile, and accept_vault_invitation() adds them as a member.
--
-- Idempotent + production-safe: every object uses create-if-not-exists /
-- create-or-replace / drop-if-exists, wrapped in a single transaction so a
-- failure rolls the whole thing back. Safe to run and re-run.
--
-- Run with:  supabase db push   — or paste this whole file into the SQL editor.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. family_vaults
-- ----------------------------------------------------------------------------
create table if not exists public.family_vaults (
  id                  uuid primary key default gen_random_uuid(),
  owner_auth_user_id  uuid not null default auth.uid()
                      references auth.users (id) on delete cascade,
  name                text not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.family_vaults is
  'A shared Family Vault, owned by its creator. Members live in vault_members.';

-- ----------------------------------------------------------------------------
-- 2. vault_members  (roles: owner / admin / editor / viewer)
-- ----------------------------------------------------------------------------
create table if not exists public.vault_members (
  id            uuid primary key default gen_random_uuid(),
  vault_id      uuid not null references public.family_vaults (id) on delete cascade,
  auth_user_id  uuid not null references auth.users (id) on delete cascade,
  role          text not null default 'viewer'
                check (role in ('owner', 'admin', 'editor', 'viewer')),
  display_name  text,
  email         text,
  phone         text,
  created_at    timestamptz not null default now(),
  unique (vault_id, auth_user_id)
);

comment on table public.vault_members is
  'Membership + role per Family Vault. Roles: owner (full control), admin '
  '(manage members + docs), editor (add/edit docs), viewer (read only). '
  'Display info is denormalized so co-members render without reading users.';

-- ----------------------------------------------------------------------------
-- 3. vault_invitations  (invite support)
--    An invite targets an email and/or phone with a role to grant. It stays
--    'pending' until the invitee accepts (they may not be a user yet).
-- ----------------------------------------------------------------------------
create table if not exists public.vault_invitations (
  id            uuid primary key default gen_random_uuid(),
  vault_id      uuid not null references public.family_vaults (id) on delete cascade,
  invited_by    uuid not null default auth.uid()
                references auth.users (id) on delete set null,
  role          text not null default 'viewer'
                check (role in ('admin', 'editor', 'viewer')),  -- never invite as owner
  email         text,
  phone         text,
  invited_name  text,
  status        text not null default 'pending'
                check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired')),
  responded_by  uuid references auth.users (id) on delete set null,
  responded_at  timestamptz,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '30 days'),
  -- Must target at least one identifier.
  constraint vault_invitations_target_chk
    check (coalesce(email, '') <> '' or coalesce(phone, '') <> '')
);

comment on table public.vault_invitations is
  'Pending invitations into a Family Vault, keyed by email/phone. The invitee '
  'accepts via accept_vault_invitation() once they are a signed-in user.';

-- ----------------------------------------------------------------------------
-- 10. Indexes (foreign keys + lookup columns)
-- ----------------------------------------------------------------------------
create index if not exists family_vaults_owner_idx
  on public.family_vaults (owner_auth_user_id);
create index if not exists vault_members_vault_idx
  on public.vault_members (vault_id);
create index if not exists vault_members_user_idx
  on public.vault_members (auth_user_id);
create index if not exists vault_invitations_vault_idx
  on public.vault_invitations (vault_id);
create index if not exists vault_invitations_email_idx
  on public.vault_invitations (lower(email)) where email is not null;
create index if not exists vault_invitations_phone_idx
  on public.vault_invitations (phone) where phone is not null;
create index if not exists vault_invitations_status_idx
  on public.vault_invitations (status);

-- ----------------------------------------------------------------------------
-- 11. Helper functions (SECURITY DEFINER — bypass RLS to avoid recursion and
--     to read the owner-scoped users table for identity matching).
-- ----------------------------------------------------------------------------
create or replace function public.is_vault_member(p_vault uuid)
  returns boolean language sql security definer stable
  set search_path = public
as $$
  select exists(
    select 1 from public.vault_members m
    where m.vault_id = p_vault and m.auth_user_id = auth.uid()
  );
$$;

create or replace function public.is_vault_admin(p_vault uuid)
  returns boolean language sql security definer stable
  set search_path = public
as $$
  select exists(
    select 1 from public.vault_members m
    where m.vault_id = p_vault
      and m.auth_user_id = auth.uid()
      and m.role in ('owner', 'admin')
  );
$$;

-- The signed-in user's own email / phone (from their profile), used to match
-- invitations addressed to them without exposing other users' rows.
create or replace function public.ino_current_email()
  returns text language sql security definer stable
  set search_path = public
as $$
  select email from public.users where auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.ino_current_phone()
  returns text language sql security definer stable
  set search_path = public
as $$
  select phone from public.users where auth_user_id = auth.uid() limit 1;
$$;

-- ----------------------------------------------------------------------------
-- 9. Auto owner-membership trigger — creator becomes the 'owner' member.
-- ----------------------------------------------------------------------------
create or replace function public.add_owner_membership()
  returns trigger language plpgsql security definer
  set search_path = public
as $$
declare
  v_name text; v_email text; v_phone text;
begin
  select full_name, email, phone
    into v_name, v_email, v_phone
    from public.users
    where auth_user_id = new.owner_auth_user_id
    limit 1;

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

-- ----------------------------------------------------------------------------
-- 8. Invite acceptance logic (SECURITY DEFINER: the invitee is not yet an
--    admin, so they can't INSERT into vault_members under RLS — this function
--    verifies the invite is addressed to them, then adds the membership).
-- ----------------------------------------------------------------------------
create or replace function public.accept_vault_invitation(p_invitation_id uuid)
  returns void language plpgsql security definer
  set search_path = public
as $$
declare
  inv     public.vault_invitations%rowtype;
  v_name  text; v_email text; v_phone text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to accept an invitation';
  end if;

  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then
    raise exception 'Invitation not found';
  end if;
  if inv.status <> 'pending' then
    raise exception 'This invitation is no longer pending';
  end if;
  if inv.expires_at < now() then
    update public.vault_invitations set status = 'expired' where id = inv.id;
    raise exception 'This invitation has expired';
  end if;

  select full_name, email, phone into v_name, v_email, v_phone
    from public.users where auth_user_id = auth.uid() limit 1;

  -- The invite must be addressed to THIS user (by email or phone).
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
     set status = 'accepted', responded_by = auth.uid(), responded_at = now()
   where id = inv.id;
end;
$$;

revoke all on function public.accept_vault_invitation(uuid) from public;
grant execute on function public.accept_vault_invitation(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4-7. Row Level Security + policies
-- ----------------------------------------------------------------------------
alter table public.family_vaults     enable row level security;
alter table public.vault_members     enable row level security;
alter table public.vault_invitations enable row level security;

-- family_vaults — a member can read; only the owner writes.
drop policy if exists "vaults: members read"  on public.family_vaults;
drop policy if exists "vaults: owner inserts"  on public.family_vaults;
drop policy if exists "vaults: owner updates"  on public.family_vaults;
drop policy if exists "vaults: owner deletes"  on public.family_vaults;

-- The owner clause is REQUIRED for create(): insert().select() does an
-- INSERT … RETURNING, and the SELECT policy is applied to the RETURNING row
-- BEFORE the AFTER-INSERT owner-membership trigger runs — so membership isn't
-- established yet. The owner clause is self-satisfied by the inserted row, so
-- the row is returned. Members (incl. the owner post-trigger) read via the
-- membership clause.
create policy "vaults: members read" on public.family_vaults
  for select using (
    owner_auth_user_id = auth.uid()
    or public.is_vault_member(id)
  );
create policy "vaults: owner inserts" on public.family_vaults
  for insert with check (owner_auth_user_id = auth.uid());
create policy "vaults: owner updates" on public.family_vaults
  for update using (owner_auth_user_id = auth.uid())
  with check (owner_auth_user_id = auth.uid());
create policy "vaults: owner deletes" on public.family_vaults
  for delete using (owner_auth_user_id = auth.uid());

-- vault_members — members read the roster; admins/owner manage it; a member may
-- remove THEMSELVES (leave) except the owner. The owner row is created by the
-- SECURITY DEFINER trigger, which bypasses these policies.
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
  with check (public.is_vault_admin(vault_id));
create policy "members: admins delete" on public.vault_members
  for delete using (
    public.is_vault_admin(vault_id)
    or (auth_user_id = auth.uid() and role <> 'owner')
  );

-- vault_invitations — admins/owner manage a vault's invites; the invitee can
-- see a pending invite addressed to them and decline it (accept goes through
-- accept_vault_invitation()).
drop policy if exists "invites: admins or invitee read" on public.vault_invitations;
drop policy if exists "invites: admins insert"          on public.vault_invitations;
drop policy if exists "invites: admins or invitee update" on public.vault_invitations;
drop policy if exists "invites: admins delete"          on public.vault_invitations;

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
    public.is_vault_admin(vault_id) and role in ('admin', 'editor', 'viewer')
  );
create policy "invites: admins or invitee update" on public.vault_invitations
  for update using (
    public.is_vault_admin(vault_id)
    or (email is not null and lower(email) = lower(coalesce(public.ino_current_email(), '')))
    or (phone is not null and phone = coalesce(public.ino_current_phone(), ''))
  );
create policy "invites: admins delete" on public.vault_invitations
  for delete using (public.is_vault_admin(vault_id));

-- ----------------------------------------------------------------------------
-- Grants (RLS still applies; these let authenticated reach the tables at all).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete
  on public.family_vaults, public.vault_members, public.vault_invitations
  to authenticated;

-- ----------------------------------------------------------------------------
-- Make everything visible to the REST API immediately.
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;

-- ============================================================================
-- VERIFICATION QUERIES (run after the migration; all read-only)
-- ============================================================================
-- 1) The three tables now exist (expect 3 rows):
--     select table_name from information_schema.tables
--      where table_schema = 'public'
--        and table_name in ('family_vaults','vault_members','vault_invitations')
--      order by table_name;
--
-- 2) RLS is enabled on all three (rls_enabled must be true):
--     select relname, relrowsecurity as rls_enabled
--       from pg_class
--      where relnamespace = 'public'::regnamespace
--        and relname in ('family_vaults','vault_members','vault_invitations');
--
-- 3) Policies exist (expect 4 + 4 + 4 = 12):
--     select tablename, count(*) as policies
--       from pg_policies
--      where schemaname = 'public'
--        and tablename in ('family_vaults','vault_members','vault_invitations')
--      group by tablename order by tablename;
--
-- 4) Helper functions + trigger fn + accept RPC exist (expect 6):
--     select proname from pg_proc
--      where pronamespace = 'public'::regnamespace
--        and proname in ('is_vault_member','is_vault_admin','ino_current_email',
--                        'ino_current_phone','add_owner_membership',
--                        'accept_vault_invitation')
--      order by proname;
--
-- 5) Owner-membership trigger is attached:
--     select tgname from pg_trigger where tgrelid = 'public.family_vaults'::regclass
--       and not tgisinternal;   -- expect trg_add_owner_membership
--
-- 6) Indexes exist (expect the 7 created above):
--     select indexname from pg_indexes where schemaname = 'public'
--       and tablename in ('family_vaults','vault_members','vault_invitations')
--      order by indexname;
--
-- 7) End-to-end smoke test (run as a signed-in user in the app's context, or via
--    a session with a valid auth.uid()):
--     insert into public.family_vaults (name) values ('Test Vault') returning id;
--     -- the trigger should have added you as owner:
--     select role from public.vault_members
--      where vault_id = '<id from above>' and auth_user_id = auth.uid();  -- 'owner'
-- ============================================================================
