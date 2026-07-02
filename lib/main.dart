import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/lock/app_lock.dart';
import 'screens/splash/splash_screen.dart';
import 'services/biometric_service.dart';
import 'services/document_protection_store.dart';
import 'services/vault_guard.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  // Flutter needs this before any async work runs before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Create the Supabase client once, at startup. After this, the rest of the
  // app reaches Supabase via `Supabase.instance.client` (see AuthService).
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // Load the biometric app-lock preference before the first frame so the lock
  // screen is already up on cold start when it's enabled (no content flash).
  await BiometricService.instance.loadLockState();

  // Biometric security services: the per-document protection flags and the
  // session guard that gates protected documents / sensitive actions.
  await DocumentProtectionStore.instance.load();
  VaultGuard.instance.init();

  runApp(const InoApp());
}

class InoApp extends StatelessWidget {
  const InoApp({super.key});

  /// App-root navigator, so post-auth navigation can run even if the screen
  /// that started sign-in was disposed (e.g. Android Credential Manager
  /// recreating the Activity while the Google picker was open). Without this,
  /// navigation was tied to the login widget's `context`/`mounted` and was
  /// silently dropped — the "nothing happens after picking an account" bug.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// App-root messenger, so error snackbars still show when the originating
  /// screen is no longer mounted (auth never fails silently).
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'INO',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          // Wrap every route in the biometric app-lock gate. It's inert unless
          // the user has enabled the lock, in which case it covers the app on
          // cold start and each return from the background.
          builder: (context, child) =>
              AppLock(child: child ?? const SizedBox.shrink()),
          home: const SplashScreen(),
        );
      },
    );
  }
}
