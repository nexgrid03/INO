import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/shared_prefs_cache.dart';
import 'session_reset.dart';
import 'two_factor_service.dart';
import '../screens/auth/auth_flow.dart';

/// One account remembered on this device, switchable from Profile → Accounts.
class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.email,
    required this.refreshToken,
    this.name,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String? name;
  final String? photoUrl;

  /// The Supabase refresh token that can re-open this account's session.
  /// Rotates on every use - [AccountSwitcher] re-saves it after each refresh.
  final String refreshToken;

  /// What the Accounts list shows: the name when we have one, else the email.
  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : email;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'photoUrl': photoUrl,
        'refreshToken': refreshToken,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
        id: j['id']?.toString() ?? '',
        email: (j['email'] as String?) ?? '',
        name: j['name'] as String?,
        photoUrl: j['photoUrl'] as String?,
        refreshToken: (j['refreshToken'] as String?) ?? '',
      );
}

/// Multi-account support: remembers every account that signs in on this device
/// and can switch between them without a full sign-out.
///
/// **How it works.** Supabase keeps one live session at a time. This service
/// stores each account's refresh token in `shared_preferences` (the same store
/// supabase_flutter itself persists the live session in, so this adds no new
/// exposure class). Switching calls `auth.setSession(refreshToken)` - the
/// server issues a fresh session for that account and rotates the token, which
/// is immediately re-saved.
///
/// **Why switching never calls signOut.** `signOut()` revokes the session's
/// refresh token server-side, which would kill the account we intend to come
/// back to. Signing in as someone else (or `setSession` for someone else)
/// replaces the client session WITHOUT revoking the previous one - sessions
/// are independent server-side. An explicit logout from Profile is the one
/// place an account is deliberately revoked and forgotten ([forgetCurrent]).
///
/// **Isolation.** Every switch runs [SessionReset.clear] after the new session
/// is live, so the next account never sees the previous account's cached data
/// - the same hygiene the app already applies on sign-out.
class AccountSwitcher extends ChangeNotifier {
  AccountSwitcher._();
  static final AccountSwitcher instance = AccountSwitcher._();

  static const String _key = 'ino_saved_accounts';

  final List<SavedAccount> _accounts = [];
  StreamSubscription<AuthState>? _sub;

  /// Every account remembered on this device, in first-seen order.
  List<SavedAccount> get accounts => List.unmodifiable(_accounts);

  /// The signed-in user's id, or null (signed out / tests).
  String? get currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  /// Loads the saved list and starts tracking the live session so the current
  /// account's entry (and its rotating refresh token) stays fresh. Call once
  /// at startup, after `Supabase.initialize`.
  Future<void> init() async {
    await _load();
    try {
      _sub ??= Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        switch (state.event) {
          case AuthChangeEvent.initialSession:
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.tokenRefreshed:
            unawaited(saveCurrent());
          default:
            break;
        }
      });
    } catch (_) {
      // Supabase not initialised (tests) - the list still works read-only.
    }
  }

  /// Upserts the live session into the saved list. Safe to call at any time;
  /// a missing session or token is a no-op.
  Future<void> saveCurrent() async {
    Session? session;
    try {
      session = Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return;
    }
    if (session == null) return;
    final token = session.refreshToken;
    if (token == null || token.isEmpty) return;

    // SECURITY FIX: Do NOT save account until MFA challenge is completed!
    if (await TwoFactorService.instance.needsMfaChallenge()) {
      developer.log('saveCurrent: skipping account save - MFA incomplete', name: 'accounts');
      return;
    }

    final user = session.user;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final entry = SavedAccount(
      id: user.id,
      email: user.email ?? (meta['email'] as String?) ?? '',
      name: (meta['full_name'] ?? meta['name']) as String?,
      photoUrl: (meta['avatar_url'] ?? meta['picture']) as String?,
      refreshToken: token,
    );

    final i = _accounts.indexWhere((a) => a.id == entry.id);
    if (i == -1) {
      _accounts.add(entry);
    } else {
      _accounts[i] = entry;
    }
    notifyListeners();
    await _persist();
  }

  /// Forgets a saved account on this device (does not touch the server).
  Future<void> removeAccount(String id) async {
    final before = _accounts.length;
    _accounts.removeWhere((a) => a.id == id);
    if (_accounts.length == before) return;
    notifyListeners();
    await _persist();
  }

  /// Forgets the signed-in account. Wired into `AuthService.signOut`: an
  /// explicit logout means "remove this account from the device", and its
  /// refresh token is about to be revoked anyway.
  Future<void> forgetCurrent() async {
    final id = currentUserId;
    if (id == null) return;
    await removeAccount(id);
  }

  /// Switches the live session to [account]. Returns true on success.
  ///
  /// On failure (the stored refresh token was revoked or expired) the dead
  /// entry is removed so the UI can offer a fresh sign-in instead - and the
  /// current session is left untouched.
  Future<bool> switchTo(SavedAccount account) async {
    if (account.id == currentUserId) return true;

    // Keep the account we're leaving re-openable.
    await saveCurrent();

    try {
      await Supabase.instance.client.auth.setSession(account.refreshToken);
    } catch (e) {
      developer.log('switch to ${account.email} failed: $e', name: 'accounts');
      await removeAccount(account.id);
      return false;
    }

    // Same hygiene as sign-out: the next account must never see the previous
    // account's cached reminders, wallets, vault key, etc. Done AFTER the
    // session swap so a failed switch costs nothing.
    await SessionReset.instance.clear();

    // Check if the restored session requires MFA verification (AAL1 -> AAL2)
    if (await TwoFactorService.instance.needsMfaChallenge()) {
      await routeAfterAuth(
        authUserId: account.id,
        fullName: account.displayName,
        email: account.email,
      );
      return true;
    }

    // Adopt the rotated refresh token for the account we just entered.
    await saveCurrent();
    developer.log('switched to ${account.email}', name: 'accounts');
    return true;
  }

  static const _secureStorage = FlutterSecureStorage();

  Future<void> _load() async {
    try {
      _accounts.clear();
      final raw = await _secureStorage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final a = SavedAccount.fromJson(item);
            if (a.id.isNotEmpty && a.refreshToken.isNotEmpty) _accounts.add(a);
          }
        }
      } else {
        // Migration: Check legacy SharedPreferences
        try {
          final p = await SharedPrefsCache.instance.prefsAsync;
          final legacyList = p.getStringList(_key);
          if (legacyList != null && legacyList.isNotEmpty) {
            for (final item in legacyList) {
              try {
                final map = jsonDecode(item) as Map<String, dynamic>;
                var token = (map['refreshToken'] as String?) ?? '';
                token = _deobfuscateLegacyToken(token);
                final a = SavedAccount(
                  id: map['id']?.toString() ?? '',
                  email: (map['email'] as String?) ?? '',
                  name: map['name'] as String?,
                  photoUrl: map['photoUrl'] as String?,
                  refreshToken: token,
                );
                if (a.id.isNotEmpty && a.refreshToken.isNotEmpty) _accounts.add(a);
              } catch (_) {}
            }
            if (_accounts.isNotEmpty) {
              await _persist();
            }
            await p.remove(_key);
          }
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      developer.log('AccountSwitcher _load error: $e', name: 'accounts');
    }
  }

  Future<void> _persist() async {
    try {
      if (_accounts.isEmpty) {
        await _secureStorage.delete(key: _key);
      } else {
        final list = [for (final a in _accounts) a.toJson()];
        await _secureStorage.write(key: _key, value: jsonEncode(list));
      }
      // Purge legacy SharedPreferences
      try {
        final p = await SharedPrefsCache.instance.prefsAsync;
        await p.remove(_key);
      } catch (_) {}
    } catch (e) {
      developer.log('AccountSwitcher _persist error: $e', name: 'accounts');
    }
  }

  static String _deobfuscateLegacyToken(String raw) {
    if (raw.isEmpty) return '';
    try {
      final bytes = base64Decode(raw);
      const key = 0x57;
      final original = List<int>.generate(bytes.length, (i) => bytes[i] ^ key);
      final decoded = utf8.decode(original);
      if (decoded.contains('.') || decoded.length > 10) return decoded;
      return raw;
    } catch (_) {
      return raw;
    }
  }

  /// Test hook: wipe in-memory state without touching storage.
  @visibleForTesting
  void reset() {
    _accounts.clear();
    _sub?.cancel();
    _sub = null;
  }
}
