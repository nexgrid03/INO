import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../core/storage/shared_prefs_cache.dart';

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
  static const _kCurrency = 'pref_currency';
  static const _kLastBackup = 'pref_last_backup_at';
  static const _kWelcomeSound = 'pref_welcome_sound_enabled';
  static const _kTourSeen = 'pref_feature_tour_seen';
  static const _kOnboardingSeen = 'pref_onboarding_seen';
  static const _kPaymentAppConsent = 'pref_payment_app_consent';
  static const _kQuickMenu = 'pref_quick_menu';

  /// Push / reminder notifications. Default on.
  final ValueNotifier<bool> notifications = ValueNotifier<bool>(true);

  /// The spoken welcome greeting on app open. Default OFF (muted): the app
  /// stays silent unless the user asks for the greeting from
  /// Settings › Preferences › "Startup greeting", which is the only surface
  /// that writes this. The single source of truth read by
  /// [VoiceGreetingService] BEFORE any audio work happens.
  final ValueNotifier<bool> welcomeSound = ValueNotifier<bool>(false);

  /// Automatically back new documents up to the cloud after upload. Default off.
  final ValueNotifier<bool> autoBackup = ValueNotifier<bool>(false);

  /// Cached "2FA is enabled" flag. The source of truth is Supabase MFA
  /// (see [TwoFactorService]); this just lets the Profile row render instantly.
  final ValueNotifier<bool> twoFactor = ValueNotifier<bool>(false);

  /// Preferred language code: `en` / `hi` / `te`.
  final ValueNotifier<String> language = ValueNotifier<String>('en');

  /// Preferred currency (ISO 4217 code) for the Property & Finance tools.
  /// Device preference like [language] - it survives sign-out.
  final ValueNotifier<String> currency = ValueNotifier<String>('INR');

  /// When the last successful cloud backup completed, or null if never.
  final ValueNotifier<DateTime?> lastBackupAt = ValueNotifier<DateTime?>(null);

  /// Whether the one-time first-run feature tour (nav bar + voice assistant
  /// coach marks) has already been shown on this device. Device-scoped like
  /// [welcomeSound] - it survives sign-out.
  final ValueNotifier<bool> tourSeen = ValueNotifier<bool>(false);

  /// Whether the splash→onboarding carousel has been completed on this device.
  /// After this is true, cold starts skip onboarding and go Splash → auth/shell.
  final ValueNotifier<bool> onboardingSeen = ValueNotifier<bool>(false);

  /// Whether the user has agreed to let INO hand a scanned payment QR off to
  /// an installed payment app (Google Pay, PhonePe, Paytm, …).
  ///
  /// Asked once, then remembered — leaving a payment app is a real trust
  /// boundary (INO passes the payee VPA out to another app and the payment
  /// itself happens there, outside INO), so it deserves an explicit yes rather
  /// than happening silently on first tap. Revocable from Profile → Privacy.
  final ValueNotifier<bool> paymentAppConsent = ValueNotifier<bool>(false);

  /// The user's picked quick-menu features (action ids, in their chosen order,
  /// max 5) for the bottom nav's "+" button. Device preference. The ids map to
  /// `QuickAction.name`s; unknown ids are ignored at read time so an old
  /// preference can never break the menu.
  final ValueNotifier<List<String>> quickMenu = ValueNotifier<List<String>>(
    const ['expenses', 'scan', 'notes'],
  );

  /// Reads every persisted preference into memory. Call once at startup.
  Future<void> load() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      notifications.value = p.getBool(_kNotifications) ?? true;
      welcomeSound.value = p.getBool(_kWelcomeSound) ?? false;
      autoBackup.value = p.getBool(_kAutoBackup) ?? false;
      twoFactor.value = p.getBool(_kTwoFactor) ?? false;
      language.value = p.getString(_kLanguage) ?? 'en';
      currency.value = p.getString(_kCurrency) ?? 'INR';
      tourSeen.value = p.getBool(_kTourSeen) ?? false;
      onboardingSeen.value = p.getBool(_kOnboardingSeen) ?? false;
      paymentAppConsent.value = p.getBool(_kPaymentAppConsent) ?? false;
      final menu = p.getStringList(_kQuickMenu);
      if (menu != null && menu.isNotEmpty) {
        quickMenu.value = List.unmodifiable(menu.take(5));
      }
      final ts = p.getInt(_kLastBackup);
      lastBackupAt.value = ts == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ts);
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

  Future<void> setWelcomeSound(bool value) =>
      _setBool(_kWelcomeSound, welcomeSound, value);

  Future<void> setTourSeen(bool value) => _setBool(_kTourSeen, tourSeen, value);

  Future<void> setOnboardingSeen(bool value) =>
      _setBool(_kOnboardingSeen, onboardingSeen, value);

  Future<void> setPaymentAppConsent(bool value) =>
      _setBool(_kPaymentAppConsent, paymentAppConsent, value);

  Future<void> setAutoBackup(bool value) =>
      _setBool(_kAutoBackup, autoBackup, value);

  Future<void> setTwoFactor(bool value) =>
      _setBool(_kTwoFactor, twoFactor, value);

  Future<void> setLanguage(String code) async {
    language.value = code;
    developer.log('language → $code', name: 'settings');
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setString(_kLanguage, code);
    } catch (e) {
      developer.log('setLanguage failed: $e', name: 'settings');
    }
  }

  Future<void> setQuickMenu(List<String> ids) async {
    final capped = List<String>.unmodifiable(ids.take(5));
    quickMenu.value = capped;
    developer.log('quickMenu → $capped', name: 'settings');
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setStringList(_kQuickMenu, capped);
    } catch (e) {
      developer.log('setQuickMenu failed: $e', name: 'settings');
    }
  }

  Future<void> setCurrency(String code) async {
    currency.value = code;
    developer.log('currency → $code', name: 'settings');
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setString(_kCurrency, code);
    } catch (e) {
      developer.log('setCurrency failed: $e', name: 'settings');
    }
  }

  Future<void> markBackedUpNow() async {
    final now = DateTime.now();
    lastBackupAt.value = now;
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setInt(_kLastBackup, now.millisecondsSinceEpoch);
    } catch (e) {
      developer.log('markBackedUpNow failed: $e', name: 'settings');
    }
  }

  Future<void> _setBool(
    String key,
    ValueNotifier<bool> notifier,
    bool value,
  ) async {
    notifier.value = value;
    developer.log('$key → $value', name: 'settings');
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setBool(key, value);
    } catch (e) {
      developer.log('persist $key failed: $e', name: 'settings');
    }
  }

  /// Resets the ACCOUNT-scoped preferences to their defaults on sign-out so the
  /// next user doesn't inherit this account's notification / auto-backup / 2FA
  /// state or last-backup time. [language] and [welcomeSound] are DEVICE
  /// preferences and are deliberately kept (muting the greeting should stick
  /// across sign-ins on this phone). Called from [SessionReset].
  Future<void> resetAccountScoped() async {
    notifications.value = true;
    autoBackup.value = false;
    twoFactor.value = false;
    lastBackupAt.value = null;
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.remove(_kNotifications);
      await p.remove(_kAutoBackup);
      await p.remove(_kTwoFactor);
      await p.remove(_kLastBackup);
    } catch (e) {
      developer.log('resetAccountScoped failed: $e', name: 'settings');
    }
  }
}
