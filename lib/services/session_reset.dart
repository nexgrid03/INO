import 'dart:developer' as developer;

import '../data/reminder_store.dart';
import '../repositories/document_repository.dart';
import '../repositories/qr_code_repository.dart';
import '../repositories/user_repository.dart';
import 'app_preload.dart';
import 'app_settings.dart';
import 'card_store.dart';
import 'category_store.dart';
import 'document_protection_store.dart';
import 'expense_store.dart';
import 'family_vault_store.dart';
import 'global_search_service.dart';
import 'investment_store.dart';
import 'net_worth_service.dart';
import 'notes_store.dart';
import 'notification_center.dart';
import 'document_file_service.dart';
import 'offline_document_store.dart';
import 'password_store.dart';
import 'property_store.dart';
import 'secure_clipboard.dart';
import 'vault_crypto.dart';
import 'voice_greeting_service.dart';
import 'wallet_store.dart';

/// Clears every piece of **user-scoped in-memory / local state** so that when
/// one account signs out and another signs in on the same device, the new
/// account never sees the previous account's data.
///
/// This is the client-side half of data isolation. The server-side half is Row
/// Level Security (see `supabase/migrations/20260710000000_user_data_isolation.sql`):
/// RLS scopes what the database returns; [SessionReset] scopes what the app has
/// already cached in process-wide singletons and `shared_preferences`.
///
/// Why this is required: the app holds several `static final … instance`
/// singletons ([ReminderStore], [NotificationCenter], [CategoryStore],
/// [DocumentProtectionStore], …). The Dart process does NOT restart on sign-out,
/// so those singletons - and their `_loaded` guards - survive an account switch.
/// Without this reset, `ReminderStore.ensureLoaded()` would no-op for the second
/// user and hand them the first user's reminders.
///
/// Call [clear] on every sign-out (wired into `AuthService.signOut`) and account
/// deletion. It is best-effort and never throws: one store failing to clear must
/// not block sign-out.
class SessionReset {
  SessionReset._();
  static final SessionReset instance = SessionReset._();

  /// Wipes all user-scoped caches. Safe to call multiple times.
  Future<void> clear() async {
    developer.log('clearing user-scoped state', name: 'session');

    // In-memory reminders (+ `_loaded` guard) - the reported leak vector.
    await _guard('reminders', () async => ReminderStore.instance.clear());

    // Derived notifications + persisted read/dismissed ids (global keys).
    await _guard('notifications', () => NotificationCenter.instance.clear());

    // User-created custom document categories (persisted global key).
    await _guard('categories', () => CategoryStore.instance.clear());

    // User-created wallets (persisted global key) - same reasoning as
    // categories: the next account must start from just the eight built-ins.
    await _guard('wallets', () => CustomWalletStore.instance.clear());

    // The four data wallets' device-local records (properties, investments,
    // saved cards, vault credentials). These are user-created content under
    // per-account keys and MUST NOT survive into the next account's session.
    await _guard('properties', () => PropertyStore.instance.clear());
    await _guard('investments', () => InvestmentStore.instance.clear());
    await _guard('cards', () => CardStore.instance.clear());
    await _guard('passwords', () => PasswordStore.instance.clear());

    // Per-document biometric-protection flags (persisted global key).
    await _guard('protection', () => DocumentProtectionStore.instance.clear());

    // Drop the Password Vault's derived key. Without this the next account to
    // sign in on this device would inherit an unlocked vault and the previous
    // user's key still in memory - and PasswordStore would happily seal the new
    // user's credentials with it.
    await _guard('vaultKey', () async => VaultCrypto.instance.lock());

    // Clear system clipboard to prevent leak to next user.
    await _guard('clipboard', () async => SecureClipboard.instance.clearImmediately());

    // In-memory document cache + persisted recent-search history.
    await _guard('search', () => GlobalSearchService.instance.clear());

    // Transaction Vault cache (rows live in Supabase, RLS-scoped; the next
    // account's ensureLoaded() re-hydrates its OWN records).
    await _guard('expenses', () async => ExpenseStore.instance.clear());

    // Notes Vault cache - same: drop in-memory state + re-arm the loader; the
    // next account's ensureLoaded() fetches its own RLS-scoped rows.
    await _guard('notes', () async => NotesStore.instance.clear());

    // Family Vault cache - drop in-memory vaults + re-arm the loader so the
    // next account loads its OWN RLS-scoped memberships.
    await _guard('familyVaults',
        () async => FamilyVaultStore.instance.clear());

    // "My QR" memo. The row itself is RLS-scoped, but the cache is a plain
    // in-memory field: without this the next account to sign in on this device
    // would see the previous user's payment QR on Home until a refetch.
    await _guard('myQr', () async => QrCodeRepository.instance.invalidate());

    // Re-arm the spoken welcome so the next sign-in is greeted at the start of
    // ITS session - still exactly once per session.
    await _guard('greeting',
        () async => VoiceGreetingService.instance.resetForNextSession());

    // Account-scoped preferences (2FA flag, last-backup, toggles). Language is a
    // device preference and is intentionally preserved.
    await _guard('settings', () => AppSettings.instance.resetAccountScoped());

    // Clear DocumentRepository & UserRepository memory and disk caches so Account B
    // never inherits Account A's cached documents or profile snapshot.
    await _guard('documentRepository', () async => DocumentRepository.instance.clearDiskCache());
    await _guard('userRepository', () async => UserRepository.instance.clearDiskCache());

    // Unload in-memory offline documents and purge decrypted plaintext temp files on sign-out,
    // while preserving encrypted on-disk storage for offline access.
    await _guard('offlineDocsMemory', () async => OfflineDocumentStore.instance.clearMemory());
    await _guard('offlineDecryptedFiles', () async => OfflineDocumentStore.instance.clearDecryptedFiles());
    await _guard('documentFiles', () async => DocumentFileService.instance.clearCache());

    // Net-worth history + its once-per-session hydration guard. The holdings
    // behind it were just cleared, so the cached chart is the previous user's.
    await _guard('netWorth', () async => NetWorthService.instance.reset());

    // The splash warm-up's cached read models (documents, the wallet hub) and
    // its "already ran" guard. Without this the next account would either be
    // handed the previous user's snapshot, or get no warm-up at all because
    // AppPreload still believed it had done its job.
    await _guard('preload', () async => AppPreload.instance.reset());

    // Nudge document listeners (storage meter, wallet counts) to re-fetch - the
    // next fetch is RLS-scoped to whoever signs in next.
    DocumentRepository.revision.value++;
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      developer.log('reset "$label" failed: $e', name: 'session');
    }
  }
}
