-- ============================================================================
-- INO - Password Vault end-to-end encryption: per-user key material
-- ----------------------------------------------------------------------------
-- Backs lib/services/vault_crypto.dart. The Password Vault stores ciphertext in
-- `w_password_vault.secret`, sealed with a key derived on-device from a vault
-- passphrase the user alone knows.
--
-- WHAT THIS TABLE HOLDS - and why none of it is a secret:
--   * salt       - random per-user input to PBKDF2. Public by design; its job is
--                  to make precomputed rainbow tables useless, not to be hidden.
--   * verifier   - a fixed known string sealed with the derived key. Lets the
--                  app distinguish "wrong passphrase" from "corrupt vault".
--                  Reveals nothing without the key.
--   * iterations - the PBKDF2 cost the key was CREATED with. Stored per row so
--                  the constant can be raised for new vaults without locking
--                  every existing one out.
--
-- The passphrase itself is NEVER stored, transmitted, or recoverable. Losing it
-- means losing the vault contents - that is the security property, not a bug.
-- No support process can reset it.
--
-- Idempotent - safe to run multiple times. Uses ONLY core Postgres.
-- Run with:  supabase db push   (or paste into the SQL editor).
-- ============================================================================

create table if not exists public.vault_keys (
  auth_user_id  uuid primary key
                references auth.users (id) on delete cascade,
  salt          text not null,                    -- base64, 32 random bytes
  verifier      text not null,                    -- base64(nonce|ct|mac)
  iterations    integer not null default 210000,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.vault_keys is
  'Password Vault key material. Holds only the PBKDF2 salt, a verifier and the iteration count - never the passphrase, which is unrecoverable by design.';
comment on column public.vault_keys.salt is
  'Base64 PBKDF2 salt. Public by design; prevents precomputation, not disclosure.';
comment on column public.vault_keys.verifier is
  'The constant ino.vault.v1 sealed with the derived key, so a wrong passphrase is distinguishable from a corrupt vault.';

-- One row per user: the primary key IS auth_user_id. A second row would mean a
-- second salt, and every secret sealed under the first key would be orphaned.

alter table public.vault_keys enable row level security;

drop policy if exists "vault_keys: owner reads own"   on public.vault_keys;
drop policy if exists "vault_keys: owner inserts own" on public.vault_keys;
drop policy if exists "vault_keys: owner updates own" on public.vault_keys;
drop policy if exists "vault_keys: owner deletes own" on public.vault_keys;

create policy "vault_keys: owner reads own" on public.vault_keys
  for select using (auth_user_id = auth.uid());
create policy "vault_keys: owner inserts own" on public.vault_keys
  for insert with check (auth_user_id = auth.uid());
-- Deliberately NO update policy for the salt path: rotating the passphrase has
-- to re-encrypt every secret first, so it is a client-side flow that rewrites
-- the row only after the re-encryption succeeds. Until that ships, a vault key
-- is write-once and an accidental UPDATE cannot strand the user's secrets.
create policy "vault_keys: owner deletes own" on public.vault_keys
  for delete using (auth_user_id = auth.uid());

drop trigger if exists set_updated_at on public.vault_keys;
create trigger set_updated_at before update on public.vault_keys
  for each row execute function public.tg_set_updated_at();
