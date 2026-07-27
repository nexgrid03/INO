# Password Vault — end-to-end encryption

Every other wallet syncs in the clear, protected by Row Level Security. RLS stops
*other users* reading your rows; it does not stop an operator. Anyone with the
`service_role` key, a database backup, or Supabase dashboard access reads those
tables plainly.

For property valuations that's an acceptable trade. For a password manager it
isn't — so `w_password_vault.secret` holds ciphertext **this server cannot
decrypt**.

```
passphrase ──PBKDF2-HMAC-SHA256(210k, per-user salt)──> 256-bit key
                                                          │
password ──────────────────AES-GCM seal───────────────────┤
                                                          ▼
                                          w_password_vault.secret (ciphertext)
```

The passphrase is never stored, never transmitted, and never leaves the device.

## Files

| File | Role |
|---|---|
| [lib/services/vault_crypto.dart](lib/services/vault_crypto.dart) | Key derivation, seal/open, unlock state |
| [lib/services/password_store.dart](lib/services/password_store.dart) | Seals on write, opens on read |
| [lib/screens/passwords/vault_passphrase_sheet.dart](lib/screens/passwords/vault_passphrase_sheet.dart) | Setup / unlock UI |
| [supabase/migrations/20260727140000_vault_keys.sql](supabase/migrations/20260727140000_vault_keys.sql) | `vault_keys`: salt, verifier, iteration count |
| [test/vault_crypto_test.dart](test/vault_crypto_test.dart) | Crypto properties |
| [test/password_vault_sync_test.dart](test/password_vault_sync_test.dart) | Fail-closed behaviour |

## What `vault_keys` stores — and why none of it is secret

| Column | Why it's safe in the clear |
|---|---|
| `salt` | Random per user. Its job is to defeat precomputed tables, not to be hidden. |
| `verifier` | The constant `ino.vault.v1` sealed with the key. Lets the app tell "wrong passphrase" from "corrupt vault". Reveals nothing without the key. |
| `iterations` | The PBKDF2 cost this key was **created** with. Stored per row so the constant can be raised for new vaults without locking existing ones out. |

## There is no recovery

This is the security property, not a gap. Nothing recoverable is stored anywhere,
so **no support process can reset a forgotten passphrase** — the credentials are
gone. The setup sheet requires an explicit acknowledgement before the first
secret is ever sealed. Don't soften that copy without replacing it with something
equally direct.

## Fail-closed

`PasswordStore.syncTable` returns **null while the vault is locked**, which
switches sync off entirely. With no key there is no way to seal a secret, and the
alternative to "cannot encrypt" must never be "upload plaintext". A locked vault
degrades to the old device-local behaviour.

`toRow` additionally throws if the vault locked mid-flight. `LocalCollectionStore`
catches it, keeps the record local, and retries later — the correct outcome.

There are tests for both. They run with the vault locked, which is the state
every test process is in.

## What is *not* encrypted

Only `secret` is. The title, username, email, url, tags and notes are metadata,
stored in the clear and protected only by RLS.

**Never move a credential into any of those columns.**

## Setup

```bash
supabase db push          # creates public.vault_keys
```

Nothing else. The key material is created per user on first vault open.

## Testing

1. Open the Password Vault → biometric prompt → passphrase setup sheet
2. Set a passphrase (≥10 chars, plus the acknowledgement)
3. Add a credential, then check the database:
   ```sql
   select name, username, secret from public.w_password_vault;
   ```
   `name` and `username` are readable. **`secret` must be base64 gibberish.**
   If you can read the password there, stop and file it as a bug.
4. Kill and reopen the app → biometric → passphrase prompt → entries decrypt
5. Enter a *wrong* passphrase → rejected, vault stays locked
6. Sign out and back in → the vault re-locks and prompts again

## Known limits

- **No passphrase rotation yet.** Changing it means re-encrypting every secret
  first; the migration deliberately omits an UPDATE policy so a partial rotation
  can't strand a vault. Write the re-encryption flow before adding one.
- **The local cache is still `shared_preferences`**, which is app-private but not
  encrypted at rest. The *server* copy is now protected; a rooted device or full
  device backup could still read the local one. Moving that to the platform
  keystore remains the next hardening step.
- **Vault unlock is per session**, tied to the app process, and clears on
  sign-out via `SessionReset`.
