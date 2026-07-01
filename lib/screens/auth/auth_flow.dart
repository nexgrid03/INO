import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../theme/theme_controller.dart';
import '../shell/main_shell.dart';

/// Completes the authentication flow by entering the app shell.
///
/// Uses [Navigator.pushAndRemoveUntil] so the entire auth stack (Login → Signup
/// → OTP → Biometric) is cleared — the back button from Home never returns to a
/// sign-in screen. Mirrors how the shell was wired to theme control before.
void goToShell(BuildContext context, UserProfile profile) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => MainShell(
        profile: profile,
        themeMode: ThemeController.mode.value,
        onToggleTheme: () => ThemeController.toggle(context),
      ),
    ),
    (route) => false,
  );
}
