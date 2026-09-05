-- ============================================================================
-- INO Migration: 20260905010000_family_vault_owner_protection.sql
--
-- Security Hardening (H8): Protect Vault Owner from direct RLS demotion.
-- Previous policy allowed an Admin to target the Owner row in `vault_members`
-- because `USING (is_vault_admin(vault_id))` lacked `and role <> 'owner'`.
-- ============================================================================

begin;

drop policy if exists "members: admins update" on public.vault_members;

create policy "members: admins update" on public.vault_members
  for update using (public.is_vault_admin(vault_id) and role <> 'owner')
  with check (public.is_vault_admin(vault_id) and role <> 'owner');

commit;
