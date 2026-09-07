import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../repositories/document_repository.dart';
import 'auth_service.dart';
import 'password_store.dart';
import 'session_reset.dart';

/// A coarse password-strength score for the Change Password meter.
enum PasswordStrength { weak, fair, good, strong }

extension PasswordStrengthX on PasswordStrength {
  String get labelKey => switch (this) {
        PasswordStrength.weak => 'strengthWeak',
        PasswordStrength.fair => 'strengthFair',
        PasswordStrength.good => 'strengthGood',
        PasswordStrength.strong => 'strengthStrong',
      };

  String label(AppLocalizations l10n) => l10n.t(labelKey);

  double get fraction => switch (this) {
        PasswordStrength.weak => 0.25,
        PasswordStrength.fair => 0.5,
        PasswordStrength.good => 0.75,
        PasswordStrength.strong => 1.0,
      };
}

/// Sensitive account operations: verifying the current password, changing it,
/// and permanently deleting the account (data + files).
///
/// All auth work goes through the Supabase client so it's genuinely backed by
/// the authentication backend - no local-only stubs.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Scores a candidate password: length + character-class variety.
  static PasswordStrength scorePassword(String password) {
    if (password.length < 6) return PasswordStrength.weak;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    if (score >= 5) return PasswordStrength.strong;
    if (score >= 3) return PasswordStrength.good;
    if (score >= 1) return PasswordStrength.fair;
    return PasswordStrength.weak;
  }

  /// Re-authenticates by re-signing-in with the current password. Throws
  /// [AuthException] if the password is wrong - used to gate sensitive actions
  /// (change password, delete account).
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException('You must be signed in to perform this action.');
    }
    developer.log('reauthenticate: verifying current password', name: 'account');
    await client.auth.signInWithPassword(email: email, password: password);
  }

  /// Verifies the current password, then updates it in Supabase Auth.
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException('You must be signed in to perform this action.');
    }
    await reauthenticate(email: email, password: currentPassword);
    developer.log('changePassword: updating credential', name: 'account');
    await client.auth.updateUser(UserAttributes(password: newPassword));
    developer.log('changePassword: success', name: 'account');
  }

  /// Permanently deletes the user's account (server-side data, storage objects,
  /// and auth user row) and clears local session state.
  ///
  /// MUST NOT swallow errors. If the server-side RPC `delete_account` fails, an
  /// exception is thrown, aborting local cleanup and sign-out so the user is not
  /// misled into thinking their account was deleted when it was not.
  Future<void> deleteAccount() async {
    final client = _client;
    final currentUser = client?.auth.currentUser;
    final currentSession = client?.auth.currentSession;

    debugPrint('═══════════════════════════════════════════════════════════════');
    debugPrint('[AccountService] DELETE ACCOUNT PROCESS STARTED');
    debugPrint('[AccountService] Auth user ID: ${currentUser?.id}');
    debugPrint('[AccountService] Auth email: ${currentUser?.email}');
    debugPrint('[AccountService] Session valid: ${currentSession != null && !currentSession.isExpired}');
    debugPrint('[AccountService] Access token present: ${currentSession?.accessToken.isNotEmpty == true}');
    debugPrint('═══════════════════════════════════════════════════════════════');

    if (client == null || currentUser?.id == null) {
      debugPrint('[AccountService] ABORT: User is not authenticated.');
      throw const AuthException('You must be signed in to delete your account.');
    }
    final userId = currentUser!.id;
    developer.log('deleteAccount: starting deletion for $userId', name: 'account');

    // 1. Client-side storage cleanup prior to RPC (best-effort)
    try {
      final repo = DocumentRepository.instance;
      final files = await repo.listUserObjects();
      final backups = await repo.listUserObjects(subFolder: 'backups');
      final paths = <String>[
        for (final f in files) '$userId/${f.name}',
        for (final b in backups) '$userId/backups/${b.name}',
      ];
      debugPrint('[AccountService] Pre-cleanup found ${paths.length} storage objects.');
      if (paths.isNotEmpty) {
        await repo.removeObjects(paths);
        debugPrint('[AccountService] Storage objects removed successfully.');
      }
    } catch (e, st) {
      debugPrint('[AccountService] Storage pre-cleanup warning: $e');
      developer.log('deleteAccount: client storage pre-cleanup note: $e', name: 'account', error: e, stackTrace: st);
    }

    // 2. Execute server-side delete_account RPC. Throws on failure (do NOT swallow!).
    const rpcName = 'delete_account';
    debugPrint('[AccountService] Calling RPC: $rpcName | Target UID: $userId');
    try {
      await client.rpc(rpcName);
      debugPrint('[AccountService] RPC $rpcName EXECUTED SUCCESSFULLY!');
      developer.log('deleteAccount: delete_account RPC executed successfully', name: 'account');
    } on PostgrestException catch (e, st) {
      debugPrint('[AccountService] POSTGREST ERROR on $rpcName:');
      debugPrint('  • Code: ${e.code}');
      debugPrint('  • Message: ${e.message}');
      debugPrint('  • Details: ${e.details}');
      debugPrint('  • Hint: ${e.hint}');
      debugPrint('  • StackTrace:\n$st');
      developer.log('deleteAccount RPC failed: ${e.message} (${e.code})', name: 'account', error: e, stackTrace: st);
      rethrow;
    } catch (e, st) {
      debugPrint('[AccountService] UNEXPECTED ERROR on $rpcName: $e');
      debugPrint('  • StackTrace:\n$st');
      developer.log('deleteAccount RPC failed: $e', name: 'account', error: e, stackTrace: st);
      rethrow;
    }

    // 3. Clear local session & in-memory caches strictly AFTER RPC succeeds
    await PasswordStore.instance.purgeSecureStorageForUser(userId);
    await SessionReset.instance.clear();
    await AuthService.instance.signOut();
    debugPrint('[AccountService] Local caches purged and user signed out.');
    developer.log('deleteAccount: account deleted & signed out', name: 'account');
  }
}
