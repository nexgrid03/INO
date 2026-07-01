import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../theme/theme_controller.dart';
import '../shell/main_shell.dart';
import 'complete_profile_screen.dart';

/// Guards against two callers (e.g. the sign-in future and a retry) both
/// routing at once and pushing the shell twice.
bool _routingAfterAuth = false;

/// Decides where an authenticated user goes and navigates there.
///
/// This is the single source of truth for post-auth routing, shared by every
/// sign-in path (Google, email, …). It navigates on the app-root navigator
/// ([InoApp.navigatorKey]) rather than a screen's own context, so it works even
/// if the screen that started sign-in was disposed while an external picker
/// (Android Credential Manager) was open — the root cause of the "nothing
/// happens after picking an account" bug.
///
///   • no profile row yet, or an incomplete one (no phone) → Complete Profile
///   • otherwise → the app shell (Home)
Future<void> routeAfterAuth({
  required String authUserId,
  required String fullName,
  required String email,
}) async {
  if (_routingAfterAuth) {
    developer.log('routeAfterAuth ignored — already routing', name: 'auth');
    return;
  }
  _routingAfterAuth = true;
  try {
    final navContext = InoApp.navigatorKey.currentContext;
    if (navContext == null) {
      developer.log('routeAfterAuth: no app navigator available', name: 'auth');
      return;
    }

    developer.log('routeAfterAuth: fetching profile for $authUserId',
        name: 'auth');
    final existing =
        await UserRepository.instance.getProfileByAuthId(authUserId);

    if (!navContext.mounted) {
      developer.log('routeAfterAuth: navigator gone after fetch', name: 'auth');
      return;
    }

    final bool needsDetails = existing == null || _isIncomplete(existing);
    if (needsDetails) {
      developer.log(
        'routeAfterAuth → CompleteProfile (existing=${existing != null})',
        name: 'auth',
      );
      Navigator.of(navContext).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CompleteProfileScreen(
            authUserId: authUserId,
            fullName: existing?.fullName ?? fullName,
            email: existing?.email ?? email,
            existingProfile: existing,
          ),
        ),
        (route) => false,
      );
    } else {
      developer.log('routeAfterAuth → Home (shell)', name: 'auth');
      goToShell(navContext, existing);
    }
  } finally {
    _routingAfterAuth = false;
  }
}

/// A profile is "incomplete" (first-time) when it has no phone number yet —
/// the one detail Google can't provide. Simple and robust without a schema
/// change; swap for a dedicated `onboarded` column if one is added later.
bool _isIncomplete(UserProfile profile) =>
    profile.phone == null || profile.phone!.trim().isEmpty;

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
