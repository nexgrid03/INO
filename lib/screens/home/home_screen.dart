import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Temporary landing screen shown after login.
///
/// This is a placeholder — the real dashboard (documents, property,
/// insurance, health, net worth, etc.) will replace it later.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('INO')),
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
              'Welcome to INO',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
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
