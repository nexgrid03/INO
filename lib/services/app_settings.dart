import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide, locally-persisted user preferences (the ones that don't warrant a
/// backend column): push notifications, auto-backup, 2FA cache flag, language
/// and the last cloud-backup timestamp.
///
/// Each preference is a [ValueNotifier] so any surface can react instantly, and
/// every setter writes through to `shared_preferences` so the choice survives a
/// restart. Mirrors the pattern in [BiometricService]: in-memory notifiers with
/// safe defaults, hydrated once at startup via [load]. Reading a notifier never
/// touches disk, so widgets can build (and tests can run) before [load] runs.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kNotifications = 'pref_notifications_enabled';
  static const _kAutoBackup = 'pref_auto_backup_enabled';
  static const _kTwoFactor = 'pref_two_factor_enabled';
  static const _kLanguage = 'pref_language';
  static const _kLastBackup = 'pref_last_backup_at';

  /// Push / reminder notifications. Default on.
  final ValueNotifier<bool> notifications = ValueNotifier<bool>(true);

  /// Automatically back new documents up to the cloud after upload. Default off.
  final ValueNotifier<bool> autoBackup = ValueNotifier<bool>(false);

  /// Cached "2FA is enabled" flag. The source of truth is Supabase MFA
  /// (see [TwoFactorService]); this just lets the Profile row render instantly.
  final ValueNotifier<bool> twoFactor = ValueNotifier<bool>(false);

  /// Preferred language code: `en` / `hi` / `ta`.
  final ValueNotifier<String> language = ValueNotifier<String>('en');

  /// When the last successful cloud backup completed, or null if never.
  final ValueNotifier<DateTime?> lastBackupAt = ValueNotifier<DateTime?>(null);

  /// Reads every persisted preference into memory. Call once at startup.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      notifications.value = p.getBool(_kNotifications) ?? true;
      autoBackup.value = p.getBool(_kAutoBackup) ?? false;
      twoFactor.value = p.getBool(_kTwoFactor) ?? false;
      language.value = p.getString(_kLanguage) ?? 'en';
      final ts = p.getInt(_kLastBackup);
      lastBackupAt.value =
          ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
      developer.log(
        'loaded: notifications=${notifications.value} '
        'autoBackup=${autoBackup.value} twoFactor=${twoFactor.value} '
        'language=${language.value}',
        name: 'settings',
      );
    } catch (e) {
      developer.log('load failed: $e', name: 'settings');
    }
  }

  Future<void> setNotifications(bool value) =>
      _setBool(_kNotifications, notifications, value);

  Future<void> setAutoBackup(bool value) =>
      _setBool(_kAutoBackup, autoBackup, value);

  Future<void> setTwoFactor(bool value) =>
      _setBool(_kTwoFactor, twoFactor, value);

  Future<void> setLanguage(String code) async {
    language.value = code;
    developer.log('language → $code', name: 'settings');
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLanguage, code);
    } catch (e) {
      developer.log('setLanguage failed: $e', name: 'settings');
    }
  }

  Future<void> markBackedUpNow() async {
    final now = DateTime.now();
    lastBackupAt.value = now;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kLastBackup, now.millisecondsSinceEpoch);
    } catch (e) {
      developer.log('markBackedUpNow failed: $e', name: 'settings');
    }
  }

  Future<void> _setBool(
      String key, ValueNotifier<bool> notifier, bool value) async {
    notifier.value = value;
    developer.log('$key → $value', name: 'settings');
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (e) {
      developer.log('persist $key failed: $e', name: 'settings');
    }
  }

  /// Resets the ACCOUNT-scoped preferences to their defaults on sign-out so the
  /// next user doesn't inherit this account's notification / auto-backup / 2FA
  /// state or last-backup time. [language] is a DEVICE preference and is
  /// deliberately kept. Called from [SessionReset].
  Future<void> resetAccountScoped() async {
    notifications.value = true;
    autoBackup.value = false;
    twoFactor.value = false;
    lastBackupAt.value = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kNotifications);
      await p.remove(_kAutoBackup);
      await p.remove(_kTwoFactor);
      await p.remove(_kLastBackup);
    } catch (e) {
      developer.log('resetAccountScoped failed: $e', name: 'settings');
    }
  }
}
