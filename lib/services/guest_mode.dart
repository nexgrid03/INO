import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../theme/app_dimens.dart';
import '../theme/app_theme.dart';
import '../widgets/common/shiny_icon.dart';

/// Guest "explore" mode - the signed-out session that starts when the user taps
/// **Get Started** on the secured-intro screen.
///
/// A guest lands directly on Home and can look around, but every action that
/// reads or writes their data funnels through [requireAuth], which shows the
/// sign-in sheet instead. In-memory only by design: a cold start walks the
/// splash → onboarding → intro flow again, and signing in clears the flag (see
/// [goToShell] in auth_flow.dart).
class GuestMode {
  GuestMode._();

  /// Whether the current shell session is an unauthenticated guest.
  static bool active = false;

  /// The placeholder profile the shell renders for a guest - never persisted,
  /// never sent to Supabase (every repository call is behind [requireAuth]).
  static UserProfile guestProfile() {
    final now = DateTime.now();
    return UserProfile(
      id: 'guest',
      authUserId: 'guest',
      fullName: 'Guest',
      email: '',
      preferredLanguage: 'en',
      biometricEnabled: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Gate for anything that needs a signed-in user.
  ///
  /// Returns `true` when the caller may proceed (not a guest). For a guest it
  /// shows the sign-in sheet and returns `false` - callers simply do:
  ///
  /// ```dart
  /// if (!await GuestMode.requireAuth(context)) return;
  /// ```
  static Future<bool> requireAuth(BuildContext context) async {
    if (!active) return true;
    await promptSignIn(context);
    return false;
  }

  /// The "sign in to continue" sheet shown when a guest taps a gated feature.
  static Future<void> promptSignIn(BuildContext context) {
    final palette = AppPalette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          20 + MediaQuery.of(sheetContext).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Center(
              child: ShinyIcon(
                icon: Icons.lock_person_rounded,
                color: AppColors.primaryGreen,
                size: 72,
                iconSize: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Sign in to continue',
              textAlign: TextAlign.center,
              style: AppText.headline.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your free INO account to store documents, '
              'set reminders and keep everything secured.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => _go(sheetContext, const LoginScreen()),
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _go(sheetContext, const SignupScreen()),
              child: const Text('Create Account'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(
                'Not now',
                style: TextStyle(color: palette.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Closes the sheet and opens an auth screen. The guest shell stays beneath
  /// it, so backing out of login lands back in explore mode; a successful
  /// sign-in replaces the whole stack via [routeAfterAuth].
  static void _go(BuildContext sheetContext, Widget screen) {
    Navigator.of(sheetContext).pop();
    Navigator.of(
      sheetContext,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => screen));
  }
}
