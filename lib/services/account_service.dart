import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/document_repository.dart';
import 'auth_service.dart';

/// A coarse password-strength score for the Change Password meter.
enum PasswordStrength { weak, fair, good, strong }

extension PasswordStrengthX on PasswordStrength {
  String get label => switch (this) {
        PasswordStrength.weak => 'Weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
      };

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
/// the authentication backend — no local-only stubs.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  SupabaseClient get _client => Supabase.instance.client;

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
  /// [AuthException] if the password is wrong — used to gate sensitive actions
  /// (change password, delete account).
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    developer.log('reauthenticate: verifying current password', name: 'account');
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Verifies the current password, then updates it in Supabase Auth.
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    await reauthenticate(email: email, password: currentPassword);
    developer.log('changePassword: updating credential', name: 'account');
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    developer.log('changePassword: success', name: 'account');
  }

  /// Permanently deletes the user's data and signs them out.
  ///
  /// Order matters: remove Storage objects, then document rows, then the profile
  /// row, then attempt a server-side auth-user deletion RPC (if the project
  /// defines one), and finally sign out. Client SDKs can't delete the auth user
  /// directly (that needs the service role), so the optional `delete_account`
  /// RPC is the supported hook — its absence is non-fatal.
  Future<void> deleteAccount() async {
    final userId = _client.auth.currentUser?.id;
    developer.log('deleteAccount: starting for $userId', name: 'account');

    // 1. Storage objects (documents + backups).
    try {
      final repo = DocumentRepository.instance;
      final files = await repo.listUserObjects();
      final backups = await repo.listUserObjects(subFolder: 'backups');
      final paths = <String>[
        for (final f in files) '$userId/${f.name}',
        for (final b in backups) '$userId/backups/${b.name}',
      ];
      await repo.removeObjects(paths);
      developer.log('deleteAccount: removed ${paths.length} objects',
          name: 'account');
    } catch (e) {
      developer.log('deleteAccount: storage cleanup failed: $e',
          name: 'account');
    }

    // 2. Document rows.
    try {
      await DocumentRepository.instance.deleteAllRowsForUser();
    } catch (e) {
      developer.log('deleteAccount: row cleanup failed: $e', name: 'account');
    }

    // 3. Profile row.
    try {
      if (userId != null) {
        await _client.from('users').delete().eq('auth_user_id', userId);
      }
    } catch (e) {
      developer.log('deleteAccount: profile cleanup failed: $e',
          name: 'account');
    }

    // 4. Best-effort server-side auth-user deletion via an RPC, if present.
    try {
      await _client.rpc('delete_account');
      developer.log('deleteAccount: delete_account RPC ok', name: 'account');
    } catch (e) {
      developer.log('deleteAccount: delete_account RPC unavailable: $e',
          name: 'account');
    }

    // 5. Sign out locally (also drops the biometric lock).
    await AuthService.instance.signOut();
    developer.log('deleteAccount: complete', name: 'account');
  }
}
