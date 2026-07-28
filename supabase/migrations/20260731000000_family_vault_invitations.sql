-- ============================================================================
-- INO — Family Vault: invitations + member management + ownership transfer
-- ----------------------------------------------------------------------------
-- Builds the production invitation / membership workflow on the existing
-- family_vaults / vault_members / vault_invitations tables. Every mutation goes
-- through a SECURITY DEFINER RPC that enforces permissions SERVER-SIDE (never
-- trusting the client), so privilege escalation and race conditions are closed
-- at the database:
--
--   invite_to_vault           — admin/owner invites by email or phone
--   decline_vault_invitation  — invitee declines
--   cancel_vault_invitation   — admin/owner revokes a pending invite
--   resend_vault_invitation   — admin/owner re-arms a declined/expired invite
--   set_vault_member_role     — admin/owner changes a member's role (never owner)
--   remove_vault_member       — admin removes a member, or a member leaves
--   transfer_vault_ownership  — owner hands ownership to a member (atomic)
--
-- accept_vault_invitation() already exists (20260728) and is reused as-is.
--
-- Extends vault_invitations with two DENORMALIZED columns (vault_name,
-- invited_by_name) — REQUIRED because an invitee is not yet a member and so
-- cannot read family_vaults (RLS) or another user's profile to render the
-- invitation card. The invite RPC stamps them.
--
-- Hardens vault_members RLS so a direct client UPDATE/DELETE can never promote
-- to 'owner' or touch the owner row — the only path to 'owner' is the
-- transfer RPC (SECURITY DEFINER).
--
-- Idempotent + production-safe. Requires 20260728 applied first.
-- Run with:  supabase db push  (or paste into the SQL editor).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 0. Denormalized columns for the invitee's card (they can't read the vault).
-- ----------------------------------------------------------------------------
alter table public.vault_invitations
  add column if not exists vault_name      text,
  add column if not exists invited_by_name text;

-- Helpful lookups for "my pending invitations" and per-vault management.
create index if not exists vault_invitations_status_email_idx
  on public.vault_invitations (status, lower(email)) where email is not null;
create index if not exists vault_invitations_status_phone_idx
  on public.vault_invitations (status, phone) where phone is not null;

-- ----------------------------------------------------------------------------
-- 1. invite_to_vault — admin/owner only. Validates role, self-invite, existing
--    membership and duplicate pending invite, then inserts. Returns the row.
-- ----------------------------------------------------------------------------
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
    raise exception 'Only an owner or admin can invite members'
      using errcode = '42501';
  end if;
  if p_role not in ('admin', 'editor', 'viewer') then
    raise exception 'Invalid role (owner cannot be invited)' using errcode = '22023';
  end if;
  if v_email is null and v_phone is null then
    raise exception 'Provide an email or phone number' using errcode = '22023';
  end if;

  -- Not yourself.
  if (v_email is not null and v_email = lower(coalesce(public.ino_current_email(), '')))
     or (v_phone is not null and v_phone = coalesce(public.ino_current_phone(), '')) then
    raise exception 'You can''t invite yourself' using errcode = '22023';
  end if;

  -- Not an existing member (resolve the invited identity to a user, if any).
  select u.auth_user_id into v_target_uid
    from public.users u
   where (v_email is not null and lower(u.email) = v_email)
      or (v_phone is not null and u.phone = v_phone)
   limit 1;
  if v_target_uid is not null and exists (
       select 1 from public.vault_members m
        where m.vault_id = p_vault and m.auth_user_id = v_target_uid) then
    raise exception 'That person is already a member of this vault'
      using errcode = '23505';
  end if;

  -- No duplicate PENDING invite for the same target in this vault.
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
    (vault_id, invited_by, role, email, phone, status,
     vault_name, invited_by_name)
  values
    (p_vault, v_uid, p_role, v_email, v_phone, 'pending',
     coalesce(v_vault_name, 'Family Vault'), v_inviter)
  returning * into v_row;

  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. decline_vault_invitation — the invitee declines an invite addressed to
--    them (matched by email/phone).
-- ----------------------------------------------------------------------------
create or replace function public.decline_vault_invitation(p_invitation_id uuid)
  returns void
  language plpgsql security definer set search_path = public
as $$
declare
  inv public.vault_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null or inv.status <> 'pending' then
    return; -- nothing to decline (idempotent)
  end if;
  if not (
       (inv.email is not null and lower(inv.email) = lower(coalesce(public.ino_current_email(), '')))
    or (inv.phone is not null and inv.phone = coalesce(public.ino_current_phone(), ''))
  ) then
    raise exception 'This invitation is not addressed to you' using errcode = '42501';
  end if;
  update public.vault_invitations
     set status = 'declined', responded_by = auth.uid(), responded_at = now()
   where id = inv.id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. cancel_vault_invitation — admin/owner revokes a pending invite.
-- ----------------------------------------------------------------------------
create or replace function public.cancel_vault_invitation(p_invitation_id uuid)
  returns void
  language plpgsql security definer set search_path = public
as $$
declare
  inv public.vault_invitations%rowtype;
begin
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then return; end if;
  if not public.is_vault_admin(inv.vault_id) then
    raise exception 'Only an owner or admin can cancel invitations'
      using errcode = '42501';
  end if;
  update public.vault_invitations set status = 'revoked' where id = inv.id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. resend_vault_invitation — admin/owner re-arms a declined/expired/revoked
--    invite (back to pending, fresh 30-day expiry). Optionally change the role.
-- ----------------------------------------------------------------------------
create or replace function public.resend_vault_invitation(
  p_invitation_id uuid,
  p_role text default null
)
  returns public.vault_invitations
  language plpgsql security definer set search_path = public
as $$
declare
  inv public.vault_invitations%rowtype;
  v_row public.vault_invitations;
begin
  select * into inv from public.vault_invitations where id = p_invitation_id;
  if inv.id is null then
    raise exception 'Invitation not found' using errcode = 'P0002';
  end if;
  if not public.is_vault_admin(inv.vault_id) then
    raise exception 'Only an owner or admin can resend invitations'
      using errcode = '42501';
  end if;
  if p_role is not null and p_role not in ('admin', 'editor', 'viewer') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  update public.vault_invitations
     set status = 'pending',
         role = coalesce(p_role, role),
         expires_at = now() + interval '30 days',
         responded_by = null,
         responded_at = null
   where id = inv.id
   returning * into v_row;
  return v_row;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. set_vault_member_role — admin/owner changes a member's role. NEVER 'owner'
--    (ownership only moves via transfer_vault_ownership), and the owner row
--    itself can't be re-roled here.
-- ----------------------------------------------------------------------------
create or replace function public.set_vault_member_role(
  p_member_id uuid,
  p_role text
)
  returns void
  language plpgsql security definer set search_path = public
as $$
declare
  m public.vault_members%rowtype;
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
    raise exception 'The owner''s role can''t be changed here — transfer ownership instead'
      using errcode = '42501';
  end if;
  update public.vault_members set role = p_role where id = p_member_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. remove_vault_member — an admin removes a member, OR a member removes
--    themselves (leave). The owner can never be removed (must transfer first).
-- ----------------------------------------------------------------------------
create or replace function public.remove_vault_member(p_member_id uuid)
  returns void
  language plpgsql security definer set search_path = public
as $$
declare
  m public.vault_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  select * into m from public.vault_members where id = p_member_id;
  if m.id is null then return; end if;  -- already gone (idempotent)
  if m.role = 'owner' then
    raise exception 'The owner can''t be removed — transfer ownership first'
      using errcode = '42501';
  end if;
  -- Allowed if the caller is an admin of the vault, or is removing themselves.
  if not (public.is_vault_admin(m.vault_id) or m.auth_user_id = auth.uid()) then
    raise exception 'You don''t have permission to remove this member'
      using errcode = '42501';
  end if;
  delete from public.vault_members where id = p_member_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. transfer_vault_ownership — the CURRENT owner promotes a member to owner
--    and steps down to admin, atomically. Exactly one owner always exists.
-- ----------------------------------------------------------------------------
create or replace function public.transfer_vault_ownership(
  p_vault uuid,
  p_new_owner uuid
)
  returns void
  language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'You must be signed in' using errcode = '28000';
  end if;
  -- Only the current owner may transfer.
  if not exists (select 1 from public.family_vaults
                  where id = p_vault and owner_auth_user_id = v_uid) then
    raise exception 'Only the owner can transfer ownership' using errcode = '42501';
  end if;
  if p_new_owner = v_uid then
    raise exception 'You are already the owner' using errcode = '22023';
  end if;
  -- The new owner must already be a member.
  if not exists (select 1 from public.vault_members
                  where vault_id = p_vault and auth_user_id = p_new_owner) then
    raise exception 'The new owner must be a member of the vault'
      using errcode = '22023';
  end if;

  -- Step down + promote + repoint the vault's owner column (all in one txn).
  update public.vault_members set role = 'admin'
   where vault_id = p_vault and auth_user_id = v_uid;
  update public.vault_members set role = 'owner'
   where vault_id = p_vault and auth_user_id = p_new_owner;
  update public.family_vaults set owner_auth_user_id = p_new_owner, updated_at = now()
   where id = p_vault;
end;
$$;

-- ----------------------------------------------------------------------------
-- Grants — expose the RPCs to authenticated users (they self-authorize).
-- ----------------------------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'invite_to_vault(uuid,text,text,text)',
    'decline_vault_invitation(uuid)',
    'cancel_vault_invitation(uuid)',
    'resend_vault_invitation(uuid,text)',
    'set_vault_member_role(uuid,text)',
    'remove_vault_member(uuid)',
    'transfer_vault_ownership(uuid,uuid)'
  ] loop
    execute format('revoke all on function public.%s from public', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- Harden vault_members RLS: block privilege escalation + owner mutation via any
-- DIRECT client UPDATE/DELETE. The RPCs above (SECURITY DEFINER) bypass RLS and
-- remain the only way to touch the owner row / assign 'owner'.
-- ----------------------------------------------------------------------------
drop policy if exists "members: admins update" on public.vault_members;
create policy "members: admins update" on public.vault_members
  for update using (public.is_vault_admin(vault_id))
  with check (public.is_vault_admin(vault_id) and role <> 'owner');

drop policy if exists "members: admins delete" on public.vault_members;
create policy "members: admins delete" on public.vault_members
  for delete using (
    (public.is_vault_admin(vault_id) and role <> 'owner')
    or (auth_user_id = auth.uid() and role <> 'owner')
  );

notify pgrst, 'reload schema';

commit;
