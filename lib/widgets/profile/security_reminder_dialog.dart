import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../screens/auth/login_screen.dart'; // VerificationChannel
import '../../services/account_security_service.dart';
import '../../services/guest_mode.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_primary_button.dart';
import 'link_entity_sheet.dart';

/// A first-time security reminder popup shown once per account when a user has
/// only verified one entity (e.g. mobile number only or email only).
class SecurityReminderDialog extends StatelessWidget {
  const SecurityReminderDialog({
    super.key,
    required this.profile,
    required this.channelToVerify,
    this.onProfileUpdated,
  });

  final UserProfile profile;
  final VerificationChannel channelToVerify;
  final ValueChanged<UserProfile>? onProfileUpdated;

  static Future<void> showIfEligible(
    BuildContext context, {
    required UserProfile profile,
    ValueChanged<UserProfile>? onProfileUpdated,
  }) async {
    if (GuestMode.active) return;
    if (profile.authUserId.isEmpty) return;

    final status = AccountSecurityService.instance.getStatus(profile);
    if (status.isFullyVerified) return;

    final seen = await AccountSecurityService.instance.hasSeenReminder(
      profile.authUserId,
    );
    if (seen) return;

    if (!context.mounted) return;

    // Mark as seen immediately so it won't trigger twice even if dismissed abruptly
    await AccountSecurityService.instance.setReminderSeen(profile.authUserId);

    if (!context.mounted) return;

    final channel = status.needsEmailVerification
        ? VerificationChannel.email
        : VerificationChannel.phone;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => SecurityReminderDialog(
        profile: profile,
        channelToVerify: channel,
        onProfileUpdated: onProfileUpdated,
      ),
    );
  }

  bool get _isEmail => channelToVerify == VerificationChannel.email;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screen,
        vertical: 24,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryGreen.withValues(alpha: 0.2),
                    AppColors.primaryGreen.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.verified_user_rounded,
                color: AppColors.primaryGreen,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),

            // Title
            Text(
              'Enhance Account Security',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),

            // Subtitle
            Text(
              _isEmail
                  ? 'You signed in with your mobile number. Verify your email address to secure your account and enable sign-in using either method.'
                  : 'You signed in with your email. Verify your mobile number to secure your account and enable fast SMS sign-in.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // CTA Buttons
            AuthPrimaryButton(
              label: _isEmail ? 'Verify Email Now' : 'Verify Mobile Number',
              onPressed: () async {
                Navigator.of(context).pop();
                final updated = await showLinkEntitySheet(
                  context,
                  profile: profile,
                  channel: channelToVerify,
                );
                if (updated != null) {
                  onProfileUpdated?.call(updated);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isEmail
                              ? 'Email address verified and linked successfully!'
                              : 'Mobile number verified and linked successfully!',
                        ),
                        backgroundColor: AppColors.primaryGreen,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Remind Me Later',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
