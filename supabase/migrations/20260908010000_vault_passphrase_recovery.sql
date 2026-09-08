-- ============================================================================
-- INO - Password Vault Passphrase Recovery & Envelope Key Architecture
-- ----------------------------------------------------------------------------
-- Extends public.vault_keys to store wrapped master keys and recovery envelopes
-- so users who verify their identity via Email / Phone OTP can reset their
-- passphrase and preserve 100% of their encrypted data without loss.
-- ============================================================================

alter table public.vault_keys
  add column if not exists wrapped_master_key text,
  add column if not exists recovery_envelope text;

comment on column public.vault_keys.wrapped_master_key is
  'Vault Master Key (VMK) wrapped with the user passphrase-derived key.';
comment on column public.vault_keys.recovery_envelope is
  'Vault Master Key (VMK) wrapped with user-verified account recovery key for OTP resets.';

-- Allow owners to update their own key row upon passphrase reset / rotation
drop policy if exists vault_keys: owner updates own on public.vault_keys;
create policy vault_keys: owner updates own on public.vault_keys
  for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
