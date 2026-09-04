import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../repositories/document_repository.dart';
import 'auth_service.dart';
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
    if (client == null || client.auth.currentUser?.id == null) {
      throw const AuthException('You must be signed in to delete your account.');
    }
    final userId = client.auth.currentUser!.id;
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
      if (paths.isNotEmpty) {
        await repo.removeObjects(paths);
      }
    } catch (e) {
      developer.log('deleteAccount: client storage pre-cleanup note: $e', name: 'account');
    }

    // 2. Execute server-side delete_account RPC. Throws on failure (do NOT swallow!).
    await client.rpc('delete_account');
    developer.log('deleteAccount: delete_account RPC executed successfully', name: 'account');

    // 3. Clear local session & in-memory caches strictly AFTER RPC succeeds
    await SessionReset.instance.clear();
    await AuthService.instance.signOut();
    developer.log('deleteAccount: account deleted & signed out', name: 'account');
  }
}
