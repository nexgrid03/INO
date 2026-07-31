import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';
import '../auth/login_screen.dart';

/// A polished "coming soon" destination for the non-Home tabs.
///
/// Keeps the bottom-nav contract complete (every tab routes somewhere real and
/// on-brand) while those screens are built out. The Profile tab additionally
/// exposes sign-out so the auth loop stays testable end to end.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({
    super.key,
    required this.titleKey,
    required this.icon,
    required this.messageKey,
    this.showSignOut = false,
  });

  /// Translation keys (not literals) so the tab follows the app language while
  /// callers can still build it in a `const` list.
  final String titleKey;
  final IconData icon;
  final String messageKey;
  final bool showSignOut;

  Future<void> _signOut(BuildContext context) async {
    await AuthService.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.tealMist,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.tealPale),
                    boxShadow: AppShadows.card,
                  ),
                  child: Icon(icon, color: AppColors.primaryGreen, size: 44),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.t(titleKey),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.t(messageKey),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n.t('comingSoon'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                if (showSignOut) ...[
                  const SizedBox(height: 32),
                  PressableScale(
                    child: OutlinedButton.icon(
                      onPressed: () => _signOut(context),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.critical,
                        backgroundColor: Colors.white,
                        side: BorderSide(
                            color: AppColors.critical.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      label: Text(l10n.t('signOut'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
