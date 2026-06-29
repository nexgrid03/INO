import 'package:flutter/material.dart';

import 'screens/splash/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
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
