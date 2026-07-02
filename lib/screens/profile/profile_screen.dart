import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/user_profile.dart';
import '../../repositories/document_repository.dart';
import '../../repositories/user_repository.dart';
import '../../services/app_settings.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/biometric_service.dart';
import '../../services/data_export_service.dart';
import '../../services/storage_stats_service.dart';
import '../../services/two_factor_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/security/biometric_ux.dart';
import '../../widgets/profile/profile_header_card.dart';
import '../../widgets/profile/settings_group.dart';
import '../../widgets/profile/settings_row.dart';
import '../auth/login_screen.dart';
import '../legal/legal_document_screen.dart';
import 'about_screen.dart';
import 'change_password_screen.dart';
import 'cloud_backup_screen.dart';
import 'contact_support_screen.dart';
import 'delete_account_screen.dart';
import 'edit_profile_screen.dart';
import 'help_center_screen.dart';
import 'trusted_devices_screen.dart';
import 'two_factor_screen.dart';

/// The Profile screen — a premium, grouped **settings** page (Apple Settings /
/// Google Account), NOT a dashboard.
///
/// Every row is fully functional: real biometric lock, Supabase-backed password
/// change / 2FA / account deletion, a live storage meter, persisted preferences
/// (theme, language, notifications, auto-backup) and real export / backup /
/// support flows. No placeholders, no "coming soon".
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.themeMode,
    required this.onToggleTheme,
    this.onProfileUpdated,
  });

  final UserProfile profile;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  /// Notifies the owner (the shell) when the profile is edited, so every tab
  /// reflects the change — not just this screen.
  final ValueChanged<UserProfile>? onProfileUpdated;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  /// Local copy so edits show immediately; also pushed up via onProfileUpdated.
  late UserProfile _profile = widget.profile;

  // Security / preference state — sourced from the persisted stores so it
  // survives restarts. Reading a store's `.value` never touches disk.
  late bool _biometric = BiometricService.instance.lockEnabled.value;
  late bool _notifications = AppSettings.instance.notifications.value;
  late bool _autoBackup = AppSettings.instance.autoBackup.value;
  bool _twoFactor = AppSettings.instance.twoFactor.value;
  late String _language = _languageLabel(widget.profile.preferredLanguage);

  // Live storage meter, computed from real Storage objects.
  StorageUsage _storage = StorageUsage.empty;
  bool _storageLoading = true;

  /// True while we've sent the user to the OS to enrol a biometric and are
  /// waiting for them to return, so we can re-check and continue automatically.
  bool _awaitingEnrollment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh the storage meter whenever documents change (upload / delete).
    DocumentRepository.revision.addListener(_onDocsChanged);
    _loadStorage();
    _syncTwoFactor();
  }

  @override
  void dispose() {
    DocumentRepository.revision.removeListener(_onDocsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the OS biometric-enrollment screen → check again and, if a
    // biometric is now enrolled, continue straight to the confirm prompt.
    if (state == AppLifecycleState.resumed && _awaitingEnrollment) {
      _awaitingEnrollment = false;
      _recheckEnrollmentThenEnable();
    }
  }

  void _onDocsChanged() => _loadStorage();

  Future<void> _loadStorage() async {
    final usage = await StorageStatsService.instance.load();
    if (!mounted) return;
    setState(() {
      _storage = usage;
      _storageLoading = false;
    });
  }

  Future<void> _syncTwoFactor() async {
    final enabled = await TwoFactorService.instance.isEnabled();
    if (!mounted) return;
    if (enabled != _twoFactor) setState(() => _twoFactor = enabled);
  }

  static String _languageLabel(String code) {
    switch (code) {
      case 'hi':
        return 'हिन्दी';
      case 'ta':
        return 'தமிழ்';
      default:
        return 'English';
    }
  }

  static String _languageCode(String label) {
    switch (label) {
      case 'हिन्दी':
        return 'hi';
      case 'தமிழ்':
        return 'ta';
      default:
        return 'en';
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    error
        ? BiometricUx.errorSnack(context, message)
        : BiometricUx.successSnack(context, message);
  }

  Future<T?> _push<T>(Widget screen) => Navigator.of(context).push<T>(
        MaterialPageRoute(builder: (_) => screen),
      );

  // ---- Preferences ---------------------------------------------------------

  Future<void> _pickLanguage() async {
    final palette = AppPalette.of(context);
    const options = ['English', 'हिन्दी', 'தமிழ்'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            _SheetGrip(),
            const SizedBox(height: AppSpacing.sm),
            Text('Language',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            for (final o in options)
              ListTile(
                title: Text(o,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight:
                          o == _language ? FontWeight.w700 : FontWeight.w500,
                    )),
                trailing: o == _language
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.primaryGreen)
                    : null,
                onTap: () => Navigator.of(context).pop(o),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (picked == null || picked == _language) return;
    setState(() => _language = picked);
    final code = _languageCode(picked);
    // Persist locally (instant) and mirror onto the profile row (best effort).
    await AppSettings.instance.setLanguage(code);
    _persistLanguage(code);
    _toast('Language set to $picked');
  }

  void _persistLanguage(String code) {
    unawaited(() async {
      try {
        final updated = await UserRepository.instance.updateProfile(
          authUserId: _profile.authUserId,
          preferredLanguage: code,
        );
        if (!mounted) return;
        setState(() => _profile = updated);
        widget.onProfileUpdated?.call(updated);
      } catch (_) {
        // Local preference is the source of truth for this device.
      }
    }());
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notifications = value);
    await AppSettings.instance.setNotifications(value);
    _toast(value ? 'Notifications enabled' : 'Notifications turned off');
  }

  Future<void> _toggleAutoBackup(bool value) async {
    setState(() => _autoBackup = value);
    await AppSettings.instance.setAutoBackup(value);
    if (!mounted) return;
    if (value) {
      _toast('Auto backup on — backing up now…');
      unawaited(_silentBackup());
    } else {
      _toast('Auto backup turned off');
    }
  }

  Future<void> _silentBackup() async {
    try {
      await BackupService.instance.backupNow(profile: _profile);
    } catch (_) {
      // Silent — the manual Cloud Backup screen surfaces errors explicitly.
    }
  }

  void _toggleDarkMode() {
    HapticFeedback.selectionClick();
    // Toggle + persist via the controller using this (live) context, so it
    // works even though the shell's original toggle context is long gone.
    ThemeController.toggle(context);
  }

  // ---- Biometric app-lock --------------------------------------------------

  Future<void> _toggleBiometric(bool value) =>
      value ? _enableBiometric() : _disableBiometric();

  Future<void> _enableBiometric() async {
    final support = await BiometricService.instance.support();
    if (!mounted) return;
    switch (support) {
      case BiometricSupport.unsupported:
        BiometricUx.errorSnack(
            context, 'This device does not support biometric authentication.');
      case BiometricSupport.notEnrolled:
        final openSettings = await BiometricUx.noBiometricsDialog(context);
        if (!mounted) return;
        if (openSettings) {
          _awaitingEnrollment = true;
          await BiometricService.instance.openEnrollmentSettings();
        }
      case BiometricSupport.ready:
        await _confirmAndEnable();
    }
  }

  Future<void> _recheckEnrollmentThenEnable() async {
    final support = await BiometricService.instance.support();
    if (!mounted) return;
    if (support == BiometricSupport.ready) await _confirmAndEnable();
  }

  Future<void> _confirmAndEnable() async {
    final outcome = await BiometricService.instance.authenticateDetailed(
      reason: 'Confirm your identity to enable biometric lock',
      title: 'Enable Biometric Lock',
    );
    if (!mounted) return;
    if (outcome.ok) {
      await BiometricService.instance.setLockEnabled(true);
      if (!mounted) return;
      setState(() => _biometric = true);
      _persistBiometric(true);
      BiometricUx.successSnack(
          context, 'Biometric authentication enabled successfully.');
    } else {
      final error = outcome.error;
      if (error != null && !error.isSilent) {
        BiometricUx.errorSnack(context, error.message);
      }
    }
  }

  Future<void> _disableBiometric() async {
    final confirmed = await BiometricUx.disableBiometricDialog(context);
    if (!mounted || !confirmed) return;
    final outcome = await BiometricService.instance.authenticateDetailed(
      reason: 'Confirm your identity to disable biometric lock',
      title: 'Disable Biometric Lock',
    );
    if (!mounted) return;
    if (!outcome.ok) {
      final error = outcome.error;
      if (error != null && !error.isSilent) {
        BiometricUx.errorSnack(context, error.message);
      }
      return;
    }
    await BiometricService.instance.setLockEnabled(false);
    if (!mounted) return;
    setState(() => _biometric = false);
    _persistBiometric(false);
    BiometricUx.successSnack(context, 'Biometric authentication disabled.');
  }

  void _persistBiometric(bool value) {
    unawaited(() async {
      try {
        final updated = await UserRepository.instance.updateProfile(
          authUserId: _profile.authUserId,
          biometricEnabled: value,
        );
        if (!mounted) return;
        setState(() => _profile = updated);
        widget.onProfileUpdated?.call(updated);
      } catch (_) {
        // Ignore — local lock state is the source of truth for this device.
      }
    }());
  }

  // ---- Security / support navigation --------------------------------------

  Future<void> _openChangePassword() async {
    await _push(ChangePasswordScreen(email: _profile.email));
  }

  Future<void> _openTwoFactor() async {
    await _push(const TwoFactorScreen());
    if (!mounted) return;
    setState(() => _twoFactor = AppSettings.instance.twoFactor.value);
  }

  // ---- Data & storage ------------------------------------------------------

  /// Builds the full account archive with a progress dialog, then shares it.
  Future<void> _exportData({required String subject}) async {
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProgressDialog(
        title: 'Preparing your data',
        progress: progress,
      ),
    );
    try {
      final archive = await DataExportService.instance.build(
        profile: _profile,
        onProgress: (p) => progress.value = p,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss progress
      await Share.shareXFiles([XFile(archive.file.path)], subject: subject);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Export failed. Please try again.', error: true);
    } finally {
      // Dispose after the dialog's exit transition, so its listener is already
      // detached (avoids "used after disposed" on the fast error path).
      Future.delayed(const Duration(milliseconds: 400), progress.dispose);
    }
  }

  // ---- Destructive actions -------------------------------------------------

  Future<void> _confirmLogout() async {
    final palette = AppPalette.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetGrip(),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.critical.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout_rounded,
                    color: AppColors.critical, size: 28),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Log out of INO?',
                  style: AppText.title.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your vault stays encrypted and synced. You can sign back in anytime.',
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _SheetButton(
                      label: 'Log Out',
                      danger: true,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await _performLogout();
  }

  Future<void> _performLogout() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: _profile),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _profile = updated;
      _biometric = updated.biometricEnabled;
      _language = _languageLabel(updated.preferredLanguage);
    });
    widget.onProfileUpdated?.call(updated);
    _toast('Profile updated');
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final p = _profile;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final blocks = <Widget>[
      _Title(),
      ProfileHeaderCard(
        fullName: p.fullName,
        email: p.email,
        photoUrl: p.profilePhoto,
        onEdit: _editProfile,
      ),
      SettingsGroup(
        caption: 'Security',
        children: [
          SettingsRow(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Authentication',
            trailing: _switch(_biometric, _toggleBiometric),
          ),
          SettingsRow(
            icon: Icons.password_rounded,
            title: 'Change Password',
            onTap: _openChangePassword,
          ),
          SettingsRow(
            icon: Icons.verified_user_rounded,
            title: 'Two-Factor Authentication',
            value: _twoFactor ? 'On' : 'Off',
            onTap: _openTwoFactor,
          ),
          SettingsRow(
            icon: Icons.devices_rounded,
            title: 'Trusted Devices',
            onTap: () => _push(const TrustedDevicesScreen()),
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Data & Storage',
        children: [
          _StorageRow(
            usedLabel: _storageLoading ? '…' : _storage.usedLabel,
            totalLabel: _storage.quotaLabel,
            fraction: _storage.fraction,
          ),
          SettingsRow(
            icon: Icons.cloud_sync_rounded,
            title: 'Auto Backup',
            trailing: _switch(_autoBackup, _toggleAutoBackup),
          ),
          SettingsRow(
            icon: Icons.backup_rounded,
            title: 'Cloud Backup',
            onTap: () => _push(CloudBackupScreen(profile: _profile)),
          ),
          SettingsRow(
            icon: Icons.file_download_outlined,
            title: 'Export Data',
            onTap: () => _exportData(subject: 'INO data export'),
          ),
          SettingsRow(
            icon: Icons.download_for_offline_outlined,
            title: 'Download Account Data',
            onTap: () => _exportData(subject: 'INO account archive'),
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Preferences',
        children: [
          SettingsRow(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            trailing: _switch(_notifications, _toggleNotifications),
          ),
          SettingsRow(
            icon: Icons.dark_mode_rounded,
            title: 'Dark Mode',
            trailing: _switch(isDark, (_) => _toggleDarkMode()),
          ),
          SettingsRow(
            icon: Icons.language_rounded,
            title: 'Language',
            value: _language,
            onTap: _pickLanguage,
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Support',
        children: [
          SettingsRow(
            icon: Icons.help_center_rounded,
            title: 'Help Center',
            onTap: () => _push(HelpCenterScreen(supportEmail: _supportEmail)),
          ),
          SettingsRow(
            icon: Icons.support_agent_rounded,
            title: 'Contact Support',
            onTap: () =>
                _push(ContactSupportScreen(supportEmail: _supportEmail)),
          ),
          SettingsRow(
            icon: Icons.info_outline_rounded,
            title: 'About INO',
            onTap: () => _push(const AboutScreen()),
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Legal',
        children: [
          SettingsRow(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy Policy',
            onTap: () => _push(LegalDocumentScreen.privacy()),
          ),
          SettingsRow(
            icon: Icons.description_rounded,
            title: 'Terms & Conditions',
            onTap: () => _push(LegalDocumentScreen.terms()),
          ),
        ],
      ),
      // Destructive actions, lowest visual weight, at the very bottom.
      SettingsGroup(
        children: [
          SettingsRow(
            icon: Icons.delete_outline_rounded,
            title: 'Delete Account',
            danger: true,
            onTap: () => _push(DeleteAccountScreen(email: _profile.email)),
          ),
          SettingsRow(
            icon: Icons.logout_rounded,
            title: 'Logout',
            danger: true,
            onTap: _confirmLogout,
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
              AppSpacing.screen, bottomInset + 100),
          itemCount: blocks.length,
          separatorBuilder: (_, i) => SizedBox(
            height: i < 1 ? AppSpacing.lg : AppSpacing.section,
          ),
          itemBuilder: (context, i) => FadeSlideIn(
            delay: Duration(milliseconds: (i * 50).clamp(0, 320)),
            child: blocks[i],
          ),
        ),
      ),
    );
  }

  /// The address Contact Support / Help Center compose to.
  String get _supportEmail => 'support@ino.app';

  Widget _switch(bool value, ValueChanged<bool> onChanged) {
    return Switch.adaptive(
      value: value,
      onChanged: (v) {
        HapticFeedback.selectionClick();
        onChanged(v);
      },
      activeTrackColor: AppColors.primaryGreen,
    );
  }
}

/// The large settings-style page title.
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.xs, 4, 0),
      child: Text(
        'Profile',
        style: AppText.display.copyWith(color: palette.textPrimary),
      ),
    );
  }
}

/// The Storage summary — a normal settings row (icon · title · usage) with a
/// slim gradient bar, fed by real Storage usage.
class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.usedLabel,
    required this.totalLabel,
    required this.fraction,
  });

  final String usedLabel;
  final String totalLabel;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.storage_rounded,
                size: 19, color: palette.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Storage',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$usedLabel of $totalLabel',
                      style:
                          AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(color: palette.surfaceVariant),
                        FractionallySizedBox(
                          widthFactor: fraction.clamp(0.0, 1.0),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small, non-dismissible progress dialog for export / archive builds.
class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.title, required this.progress});

  final String title;
  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: value == 0 ? null : value,
                  minHeight: 6,
                  backgroundColor: palette.surfaceVariant,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primaryGreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetGrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: palette.border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: Material(
        color: danger ? AppColors.critical : palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 50,
            child: Center(
              child: Text(
                label,
                style: AppText.subtitle.copyWith(
                  color: danger ? Colors.white : palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
