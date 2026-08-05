import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'core/responsive/responsive.dart';
import 'l10n/app_localizations.dart';
import 'screens/lock/app_lock.dart';
import 'screens/share/shared_documents_screen.dart';
import 'screens/share/view_once_viewer_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/account_switcher.dart';
import 'services/app_settings.dart';
import 'services/auto_backup_coordinator.dart';
import 'services/biometric_service.dart';
import 'services/card_store.dart';
import 'services/category_store.dart';
import 'services/deep_link_service.dart';
import 'services/investment_store.dart';
import 'services/notification_center.dart';
import 'services/document_protection_store.dart';
import 'services/password_store.dart';
import 'services/property_store.dart';
import 'services/push_service.dart';
import 'services/trusted_device_service.dart';
import 'services/vault_guard.dart';
import 'services/voice_manager.dart';
import 'services/wallet_store.dart';
import 'theme/app_theme.dart';
import 'theme/ino_scroll_behavior.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_style.dart';

Future<void> main() async {
  // Flutter needs this before any async work runs before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Create the Supabase client once, at startup. After this, the rest of the
  // app reaches Supabase via `Supabase.instance.client` (see AuthService).
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // Multi-account registry: remembers every account that signs in on this
  // device (Profile → Accounts) and keeps the live one's entry fresh.
  await AccountSwitcher.instance.init();

  // Hydrate persisted preferences before the first frame so the UI (theme, lock
  // screen, settings toggles) renders in its saved state with no flash.
  await ThemeController.load();
  await BiometricService.instance.loadLockState();
  await AppSettings.instance.load();

  // Biometric security services: the per-document protection flags and the
  // session guard that gates protected documents / sensitive actions.
  await DocumentProtectionStore.instance.load();
  VaultGuard.instance.init();

  // Custom document categories (name / icon / colour), so they're available to
  // pickers and filters on first paint.
  await CategoryStore.instance.load();

  // Wallets the user created themselves, so the hub grid and every wallet
  // picker list them on first paint.
  await CustomWalletStore.instance.load();

  // The four data wallets' device-local records, so the hub shows real counts
  // ("3 properties") on the very first frame instead of zeros that then jump.
  await Future.wait([
    PropertyStore.instance.ensureLoaded(),
    InvestmentStore.instance.ensureLoaded(),
    CardStore.instance.ensureLoaded(),
    PasswordStore.instance.ensureLoaded(),
  ]);

  // Record this device in the local trusted-devices registry (non-blocking).
  unawaited(TrustedDeviceService.instance.registerCurrent());

  // Auto-backup: when enabled, back up shortly after documents change.
  AutoBackupCoordinator.instance.start();

  // Warm the notification feed so the bell badge is accurate on first paint.
  unawaited(NotificationCenter.instance.load());

  // Reminder push notifications (FCM). Deliberately NOT awaited: it makes
  // network calls (Firebase handshake, token fetch, token upsert) that must
  // never sit between the user and the first frame. A tap that cold-launched
  // the app is still routed correctly - PushService waits for the navigator to
  // attach before navigating.
  unawaited(PushService.instance.init(InoApp.navigatorKey));

  // Warm the centralized voice manager so the native TextToSpeech service is
  // already bound (and past its cold-start races) before the voice greeting
  // fires - part of the duplicate-speech fix (see services/voice_manager.dart).
  VoiceManager.instance.warmUp();

  // Capture a share deep link the app may have been cold-launched from, BEFORE
  // the first frame - so the app root can show the shared documents directly
  // (see [InoApp._home]) instead of the splash flow overwriting it.
  await DeepLinkService.instance.captureInitialLink();

  runApp(const InoApp());
}

class InoApp extends StatefulWidget {
  const InoApp({super.key});

  /// App-root navigator, so post-auth navigation can run even if the screen
  /// that started sign-in was disposed (e.g. Android Credential Manager
  /// recreating the Activity while the Google picker was open). Without this,
  /// navigation was tied to the login widget's `context`/`mounted` and was
  /// silently dropped - the "nothing happens after picking an account" bug.
  /// Also used by [DeepLinkService] to present the shared-documents viewer.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// App-root messenger, so error snackbars still show when the originating
  /// screen is no longer mounted (auth never fails silently).
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  State<InoApp> createState() => _InoAppState();
}

class _InoAppState extends State<InoApp> {
  /// When the app was cold-launched from a share link, show the viewer directly
  /// as the root (resolved once, before the first frame in `main()`).
  final String? _initialShareId = DeepLinkService.instance.initialShareId;

  /// Same idea for a cold start from a **view-once** link. It routes to the
  /// gated one-time viewer, which warns before spending the single view.
  final String? _initialViewOnceToken =
      DeepLinkService.instance.initialViewOnceToken;

  @override
  void initState() {
    super.initState();
    // Warm links (background → foreground / already running) are pushed onto
    // the live navigator once it's attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.startListening(InoApp.navigatorKey);
    });
  }

  @override
  void dispose() {
    DeepLinkService.instance.dispose();
    // Release the native text-to-speech engine with the app root.
    VoiceManager.instance.dispose();
    super.dispose();
  }

  /// The root screen: the one-time viewer for a view-once cold start, the
  /// shared-documents viewer for a regular share link, otherwise the normal
  /// splash flow.
  Widget get _home {
    if (_initialViewOnceToken != null) {
      return ViewOnceViewerScreen(token: _initialViewOnceToken);
    }
    if (_initialShareId != null) {
      return SharedDocumentsScreen(token: _initialShareId);
    }
    return const SplashScreen();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        // The visual style (classic / bold / soft) rebuilds the app the same
        // way the light/dark mode does - picked in Profile → App theme.
        return ValueListenableBuilder<ThemeStyle>(
          valueListenable: ThemeController.style,
          builder: (context, style, _) {
            // The language notifier is persisted (AppSettings) and drives the
            // app locale, so selecting a language rebuilds every Localizations
            // dependant instantly - no restart required.
            return ValueListenableBuilder<String>(
              valueListenable: AppSettings.instance.language,
              builder: (context, langCode, _) {
                return MaterialApp(
                  title: 'INO',
                  debugShowCheckedModeBanner: false,
                  navigatorKey: InoApp.navigatorKey,
                  scaffoldMessengerKey: InoApp.messengerKey,
                  theme: AppTheme.lightFor(style),
                  darkTheme: AppTheme.darkFor(style),
                  themeMode: mode,
                  // Launcher / Aqua: no M3 stretch overscroll (it scales the
                  // page and makes text look like it shrinks while scrolling).
                  scrollBehavior: InoStyle.usesDivineGlassStyle(style)
                      ? const InoNoStretchScrollBehavior()
                      : const MaterialScrollBehavior(),
                  locale: _localeForCode(langCode),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  // Wrap every route in the biometric app-lock gate (inert
                  // unless enabled) and the InoStyleScope, so every route -
                  // dialogs and sheets included - sees the active style.
                  builder: (context, child) => InoResponsiveInit(
                    child: InoStyleScope(
                      style: style,
                      child: AppLock(child: child ?? const SizedBox.shrink()),
                    ),
                  ),
                  home: _home,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Maps a persisted language code (`en` / `hi` / `te` / `ta`) to its [Locale],
/// defaulting to English for anything unknown.
Locale _localeForCode(String code) {
  switch (code) {
    case 'hi':
      return const Locale('hi');
    case 'te':
      return const Locale('te');
    case 'ta':
      return const Locale('ta');
    default:
      return const Locale('en');
  }
}
