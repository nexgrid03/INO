import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';

/// Guards the one behaviour the Password Vault cannot get wrong: a credential
/// must never leave the device unencrypted.
///
/// `w_password_vault.secret` carries this instruction in the schema itself -
/// *"Client-side-encrypted password. NEVER write a plaintext credential here."*
/// The mechanism that enforces it is [PasswordStore.syncTable] returning null
/// while the vault is locked, which switches sync off entirely rather than
/// falling back to an unsealed upload.
///
/// These tests run with the vault LOCKED, which is the state a test process is
/// always in (no Supabase session, so no key can be derived). That is exactly
/// the state the fail-closed path exists for.
void main() {
  test('a locked vault reports no sync table, so nothing can be uploaded', () {
    expect(VaultCrypto.instance.isUnlocked, isFalse);

    // Null here is what makes LocalCollectionStore skip the network entirely.
    // If this ever returns a table name while locked, toRow would be called
    // without a key and the store would try to upload a credential it cannot
    // seal.
    expect(PasswordStore.instance.syncTable, isNull);
  });

  test('sealing a secret while locked refuses rather than returning plaintext',
      () async {
    // The critical negative: encrypt() must return null, NOT the input. A
    // pass-through here would put every user's password in Postgres in clear.
    final sealed = await VaultCrypto.instance.encrypt('hunter2');
    expect(sealed, isNull);
  });

  test('toRow throws while locked instead of writing an unsealed secret',
      () async {
    // LocalCollectionStore catches this, keeps the record local, and retries on
    // the next sync - the correct outcome. Writing `secret: null` or the
    // plaintext would not be.
    expect(
      () => PasswordStore.instance.toRow(_entry()),
      throwsA(isA<StateError>()),
    );
  });

  test('decrypting while locked yields null, never the ciphertext', () async {
    final opened = await VaultCrypto.instance.decrypt('not-a-real-sealed-value');
    expect(opened, isNull);
  });

  test('lock() is idempotent and safe to call when already locked', () {
    VaultCrypto.instance.lock();
    VaultCrypto.instance.lock();
    expect(VaultCrypto.instance.isUnlocked, isFalse);
  });
}

/// A minimal entry. Only `password` matters here - these tests never get far
/// enough to map the other fields.
PasswordEntry _entry() => PasswordEntry(
      id: 'pw_local_1',
      nickname: 'blue parrot',
      password: 'hunter2',
      consent: true,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
