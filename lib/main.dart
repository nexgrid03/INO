import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'core/net/net_guard.dart';
import 'core/responsive/responsive.dart';
import 'core/storage/shared_prefs_cache.dart';
import 'l10n/app_localizations.dart';
import 'screens/lock/app_lock.dart';
import 'screens/share/shared_documents_screen.dart';
import 'screens/share/view_once_viewer_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/account_switcher.dart';
import 'services/app_settings.dart';
import 'services/auto_backup_coordinator.dart';
import 'services/biometric_service.dart';
import 'services/category_store.dart';
import 'services/deep_link_service.dart';
import 'services/notification_center.dart';
import 'services/document_protection_store.dart';
import 'services/push_service.dart';
import 'services/trusted_device_service.dart';
import 'services/vault_guard.dart';
import 'services/voice_manager.dart';
import 'services/wallet_store.dart';
import 'theme/app_theme.dart';
import 'theme/ino_scroll_behavior.dart';
import 'theme/theme_controller.dart';
import 'widgets/common/liquid_glass.dart';
import 'theme/theme_style.dart';
import 'widgets/shell/ino_bottom_nav.dart';
import 'widgets/dashboard/expandable_fab.dart';

Future<void> main() async {
  // Flutter needs this before any async work runs before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize shared preferences cache early so all subsequent stores use it
  await SharedPrefsCache.init();

  // Create the Supabase client once, at startup. After this, the rest of the
  // app reaches Supabase via `Supabase.instance.client` (see AuthService).
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    httpClient: TimeoutHttpClient(http.Client()),
  );

  // Parallelize independent startup initializations to reduce cold start time
  await Future.wait([
    AccountSwitcher.instance.init(),
    ThemeController.load(),
    BiometricService.instance.loadLockState(),
    AppSettings.instance.load(),
    DeepLinkService.instance.captureInitialLink(),
  ]);

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

class _InoAppState extends State<InoApp> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    // Warm links (background → foreground / already running) are pushed onto
    // the live navigator once it's attached, and non-critical services are deferred post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.startListening(InoApp.navigatorKey);
      _initDeferredServices();
    });
  }

  @override
  Future<bool> didPopRoute() async {
    debugPrint('[GLOBAL SYSTEM BACK OBSERVER] System back event received. isBottomNavOpen: ${InoBottomNav.isMenuOpen}, isExpandableFabOpen: ${ExpandableFab.isMenuOpen}');

    if (InoBottomNav.isMenuOpen) {
      debugPrint('[GLOBAL SYSTEM BACK OBSERVER] Intercepted back -> Closing InoBottomNav FAB menu. PREVENTING ALL NAVIGATION!');
      InoBottomNav.closeActiveMenu();
      return true; // Handled -> Cancels route pop and tab change entirely!
    }

    if (ExpandableFab.isMenuOpen) {
      debugPrint('[GLOBAL SYSTEM BACK OBSERVER] Intercepted back -> Closing ExpandableFab. PREVENTING ALL NAVIGATION!');
      ExpandableFab.closeActiveMenu();
      return true; // Handled -> Cancels route pop and tab change entirely!
    }

    return false; // Not handled -> Normal navigation proceeds.
  }

  void _initDeferredServices() {
    unawaited(DocumentProtectionStore.instance.load());
    VaultGuard.instance.init();
    unawaited(CategoryStore.instance.load());
    unawaited(CustomWalletStore.instance.load());
    TrustedDeviceService.instance.init();
    AutoBackupCoordinator.instance.start();
    unawaited(NotificationCenter.instance.load());
    unawaited(PushService.instance.init(InoApp.navigatorKey));
    VoiceManager.instance.warmUp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                // Mirror the active language to the static accessor so code
                // without a BuildContext (services, the push sender) can
                // translate in the language the user is actually seeing.
                AppLocalizations.activeLanguageCode = langCode;
                return MaterialApp(
                  title: 'INO',
                  debugShowCheckedModeBanner: false,
                  navigatorKey: InoApp.navigatorKey,
                  scaffoldMessengerKey: InoApp.messengerKey,
                  theme: AppTheme.lightFor(style),
                  darkTheme: AppTheme.darkFor(style),
                  themeMode: mode,
                  // ONE scroll feel for the entire app - iOS-style spring
                  // physics on every platform, no M3 stretch overscroll (it
                  // scales the page and makes text look like it shrinks while
                  // scrolling). Screens inherit this; none should pass
                  // `physics:` of their own. See [InoScrollBehavior].
                  scrollBehavior: const InoScrollBehavior(),
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
                      child: GlassScrollListener(
                        child: AppLock(child: child ?? const SizedBox.shrink()),
                      ),
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

/// Maps a persisted language code (`en` / `hi` / `te`) to its [Locale],
/// defaulting to English for anything unknown.
Locale _localeForCode(String code) {
  switch (code) {
    case 'hi':
      return const Locale('hi');
    case 'te':
      return const Locale('te');
    default:
      return const Locale('en');
  }
}
