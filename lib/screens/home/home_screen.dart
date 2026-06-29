import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';

/// Temporary landing screen shown after login.
///
/// It receives the signed-in user's [UserProfile] (fetched from public.users)
/// and greets them by name — proof that we retrieved the profile. The real
/// dashboard (documents, property, insurance, …) will replace this later.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  Future<void> _signOut(BuildContext context) async {
    await AuthService.instance.signOut();
    if (!context.mounted) return;
    // Clear the navigation stack and return to Login.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstName = profile.fullName.split(' ').first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('INO'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 72,
              color: AppColors.primaryGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome, $firstName 👋',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              profile.email,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            const Text(
              'Dashboard coming soon',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
