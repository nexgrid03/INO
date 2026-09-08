import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/shared_prefs_cache.dart';
import '../models/user_profile.dart';
import '../repositories/user_repository.dart';
import '../screens/auth/login_screen.dart'; // VerificationChannel
import '../theme/app_dimens.dart';
import '../theme/app_theme.dart';
import '../widgets/auth/auth_primary_button.dart';
import '../widgets/profile/link_entity_sheet.dart';
import 'auth_service.dart';

enum AccountVerificationStatus {
  onlyPhoneVerified,
  onlyEmailVerified,
  fullyVerified;

  bool get isFullyVerified => this == AccountVerificationStatus.fullyVerified;
  bool get needsEmailVerification => this == AccountVerificationStatus.onlyPhoneVerified;
  bool get needsPhoneVerification => this == AccountVerificationStatus.onlyEmailVerified;
}

class AccountSecurityService {
  AccountSecurityService._();
  static final AccountSecurityService instance = AccountSecurityService._();

  static const String _kReminderPrefix = 'pref_link_entity_reminder_seen_';

  /// Determines the current user's verification status by inspecting both the
  /// active Supabase Auth user and the local [UserProfile].
  AccountVerificationStatus getStatus(UserProfile profile) {
    final authUser = AuthService.instance.currentUser;
    if (authUser == null) {
      // Fallback to profile inspection if offline / session unavailable
      final hasPhone = profile.phone != null && profile.phone!.trim().isNotEmpty;
      final hasEmail = profile.email.trim().isNotEmpty;
      if (hasPhone && hasEmail) return AccountVerificationStatus.fullyVerified;
      if (hasPhone) return AccountVerificationStatus.onlyPhoneVerified;
      return AccountVerificationStatus.onlyEmailVerified;
    }

    final hasAuthPhone = authUser.phone != null && authUser.phone!.trim().isNotEmpty;
    final hasAuthEmail = authUser.email != null && authUser.email!.trim().isNotEmpty;

    if (hasAuthPhone && hasAuthEmail) {
      return AccountVerificationStatus.fullyVerified;
    }
    if (hasAuthPhone) {
      return AccountVerificationStatus.onlyPhoneVerified;
    }
    return AccountVerificationStatus.onlyEmailVerified;
  }

  /// Checks whether the first-time reminder popup was already shown for [userId].
  Future<bool> hasSeenReminder(String userId) async {
    try {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      return prefs.getBool('$_kReminderPrefix$userId') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Marks the reminder as seen so the user is never repeatedly interrupted.
  Future<void> setReminderSeen(String userId) async {
    try {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      await prefs.setBool('$_kReminderPrefix$userId', true);
    } catch (e) {
      developer.log('setReminderSeen failed: $e', name: 'security');
    }
  }

  /// Initiates linking an email to the currently signed-in account.
  Future<void> sendEmailLinkOtp(String email) async {
    final trimmed = email.trim();
    if (await AuthService.instance.identifierTaken(trimmed)) {
      throw const AuthException(
        'That email is already registered to another INO account.',
      );
    }
    await AuthService.instance.linkEmail(trimmed);
  }

  /// Confirms email linking OTP and synchronizes the profile table.
  Future<UserProfile> verifyAndSaveEmailLink({
    required String email,
    required String token,
    required UserProfile currentProfile,
  }) async {
    final res = await AuthService.instance.verifyEmailLink(
      email: email.trim(),
      token: token.trim(),
    );
    final user = res.user ?? AuthService.instance.currentUser;
    if (user == null) {
      throw const AuthException('Failed to authenticate updated session.');
    }

    // Update public.users database row with the new verified email
    final updated = await UserRepository.instance.updateProfile(
      authUserId: user.id,
      email: email.trim(),
    );
    return updated;
  }

  /// Initiates linking a phone number to the currently signed-in account.
  Future<void> sendPhoneLinkOtp(String phone) async {
    final trimmed = phone.trim();
    if (await AuthService.instance.identifierTaken(trimmed)) {
      throw const AuthException(
        'That mobile number is already registered to another INO account.',
      );
    }
    await AuthService.instance.linkPhone(trimmed);
  }

  /// Confirms phone linking OTP and synchronizes the profile table.
  Future<UserProfile> verifyAndSavePhoneLink({
    required String phone,
    required String token,
    required UserProfile currentProfile,
  }) async {
    final res = await AuthService.instance.verifyPhoneLink(
      phone: phone.trim(),
      token: token.trim(),
    );
    final user = res.user ?? AuthService.instance.currentUser;
    if (user == null) {
      throw const AuthException('Failed to authenticate updated session.');
    }

    // Update public.users database row with the new verified phone
    final updated = await UserRepository.instance.updateProfile(
      authUserId: user.id,
      phone: phone.trim(),
    );
    return updated;
  }

  /// Checks whether the signed-in user has verified their email address.
  /// If the user logged in with mobile number and has not verified their email,
  /// opens a mandatory gate dialog requiring email verification before proceeding.
  ///
  /// If email is already verified, returns `true` immediately without any dialog.
  Future<bool> ensureEmailVerified(
    BuildContext context, {
    required String reason,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return false;

    final profile = await UserRepository.instance.getCachedProfile(user.id) ??
        await UserRepository.instance.getProfileByAuthId(user.id);
    if (profile == null) return false;

    final status = getStatus(profile);
    if (!status.needsEmailVerification) {
      // Email is already verified — proceed immediately!
      return true;
    }

    if (!context.mounted) return false;

    // Show gate explanation dialog
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final palette = AppPalette.of(dialogCtx);
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
                    Icons.mark_email_read_rounded,
                    color: AppColors.primaryGreen,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Email Verification Required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                AuthPrimaryButton(
                  label: 'Verify Email Now',
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: Text(
                    'Cancel',
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
      },
    );

    if (proceed != true || !context.mounted) return false;

    // Open link entity sheet for email
    final updated = await showLinkEntitySheet(
      context,
      profile: profile,
      channel: VerificationChannel.email,
    );

    if (updated != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Email address verified successfully!'),
          backgroundColor: AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    }

    return false;
  }
}
