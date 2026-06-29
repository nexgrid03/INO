import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/splash/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Flutter needs this before any async work runs before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Create the Supabase client once, at startup. After this, the rest of the
  // app reaches Supabase via `Supabase.instance.client` (see AuthService).
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const InoApp());
}

class InoApp extends StatelessWidget {
  const InoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'INO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
