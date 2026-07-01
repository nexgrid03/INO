import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/account_status_card.dart';
import '../../widgets/profile/profile_header_card.dart';
import '../../widgets/profile/settings_section.dart';
import '../../widgets/profile/settings_tile.dart';
import '../../widgets/profile/storage_meter.dart';
import '../auth/login_screen.dart';

/// The Profile screen — INO's account management & security center.
///
/// A premium, vault-like settings surface: profile header, account status,
/// Security Center, Data & Storage, Preferences, Support, and a confirmed
/// logout. No FAB, no analytics — clean and professional. All data-driven from
/// [UserProfile]; the theme row is wired to the app's live theme toggle.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final UserProfile profile;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late bool _biometric = widget.profile.biometricEnabled;
  bool _notifications = true;
  bool _autoBackup = true;
  late String _language = _languageLabel(widget.profile.preferredLanguage);

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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  String get _themeLabel {
    switch (widget.themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

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
    if (picked != null) setState(() => _language = picked);
  }

  // ---- Logout --------------------------------------------------------------

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

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final p = widget.profile;

    final sections = <Widget>[
      ProfileHeaderCard(
        fullName: p.fullName,
        email: p.email,
        phone: p.phone ?? '',
        photoUrl: p.profilePhoto,
        onEdit: () => _toast('Edit Profile — coming soon'),
      ),
      AccountStatusCard(
        lastBackup: 'Today, 9:24 AM',
        cloudSynced: true,
        vaultEnabled: true,
        biometricEnabled: _biometric,
      ),
      _securitySection(),
      _dataSection(),
      _preferencesSection(),
      _supportSection(),
      _logoutButton(),
    ];

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, AppSpacing.md, AppSpacing.screen, 120),
          itemCount: sections.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
          itemBuilder: (context, i) {
            if (i == 0) return _Header(name: p.fullName);
            final section = sections[i - 1];
            return FadeSlideIn(
              delay: Duration(milliseconds: (i * 55).clamp(0, 360)),
              child: section,
            );
          },
        ),
      ),
    );
  }

  Widget _securitySection() {
    return SettingsSection(
      title: 'Security Center',
      icon: Icons.shield_rounded,
      tiles: [
        SettingsTile(
          icon: Icons.fingerprint_rounded,
          color: AppColors.primaryGreen,
          title: 'Biometric Authentication',
          subtitle: 'Face ID / fingerprint unlock',
          trailing: _switch(
            _biometric,
            (v) async {
              setState(() => _biometric = v);
              try {
                await UserRepository.instance.updateBiometricEnabled(
                  authUserId: widget.profile.authUserId,
                  enabled: v,
                );
                _toast('Biometric ${v ? 'enabled' : 'disabled'}');
              } catch (_) {
                setState(() => _biometric = !v);
                _toast('Failed to update biometric settings');
              }
            },
          ),
        ),
        SettingsTile(
          icon: Icons.password_rounded,
          color: AppColors.lightBlue,
          title: 'Change Password',
          subtitle: 'Update your account password',
          onTap: () => _toast('Change Password — coming soon'),
        ),
        SettingsTile(
          icon: Icons.verified_user_rounded,
          color: AppColors.secondaryGreen,
          title: 'Two-Factor Authentication',
          subtitle: 'Add an extra layer of security',
          onTap: () => _toast('Two-Factor Authentication — coming soon'),
        ),
        SettingsTile(
          icon: Icons.devices_rounded,
          color: const Color(0xFF8B6CEF),
          title: 'Device Management',
          subtitle: 'Manage signed-in devices',
          onTap: () => _toast('Device Management — coming soon'),
        ),
      ],
    );
  }

  Widget _dataSection() {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Data & Storage',
          icon: Icons.cloud_rounded,
          iconColor: AppColors.lightBlue,
        ),
        InoCard(
          radius: AppRadius.card,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(4),
                child: StorageMeter(
                  usedLabel: '1.2 GB',
                  totalLabel: '5 GB',
                  fraction: 0.24,
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 12,
                  endIndent: 12,
                  color: palette.border),
              SettingsTile(
                icon: Icons.backup_rounded,
                color: AppColors.primaryGreen,
                title: 'Cloud Backup',
                subtitle: 'Encrypted backup to the cloud',
                onTap: () => _toast('Cloud Backup — coming soon'),
              ),
              _divider(palette),
              SettingsTile(
                icon: Icons.file_download_outlined,
                color: AppColors.lightBlue,
                title: 'Export Data',
                subtitle: 'Export documents & records',
                onTap: () => _toast('Export Data — coming soon'),
              ),
              _divider(palette),
              SettingsTile(
                icon: Icons.download_for_offline_outlined,
                color: AppColors.secondaryGreen,
                title: 'Download Account Data',
                subtitle: 'Get a copy of everything',
                onTap: () => _toast('Download Account Data — coming soon'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preferencesSection() {
    final palette = AppPalette.of(context);
    return SettingsSection(
      title: 'Preferences',
      icon: Icons.tune_rounded,
      tiles: [
        SettingsTile(
          icon: Icons.notifications_rounded,
          color: const Color(0xFFF5704A),
          title: 'Notifications',
          subtitle: 'Reminders & alerts',
          trailing: _switch(
            _notifications,
            (v) => setState(() => _notifications = v),
          ),
        ),
        SettingsTile(
          icon: Icons.language_rounded,
          color: AppColors.lightBlue,
          title: 'Language',
          onTap: _pickLanguage,
          trailing: _valueTrailing(_language, palette),
        ),
        SettingsTile(
          icon: widget.themeMode == ThemeMode.dark
              ? Icons.dark_mode_rounded
              : Icons.light_mode_rounded,
          color: AppColors.primaryGreen,
          title: 'Theme',
          onTap: widget.onToggleTheme,
          trailing: _valueTrailing(_themeLabel, palette),
        ),
        SettingsTile(
          icon: Icons.cloud_sync_rounded,
          color: AppColors.secondaryGreen,
          title: 'Auto Backup',
          subtitle: 'Back up daily over Wi-Fi',
          trailing:
              _switch(_autoBackup, (v) => setState(() => _autoBackup = v)),
        ),
      ],
    );
  }

  Widget _supportSection() {
    return SettingsSection(
      title: 'Support',
      icon: Icons.help_outline_rounded,
      tiles: [
        SettingsTile(
          icon: Icons.help_center_rounded,
          color: AppColors.primaryGreen,
          title: 'Help Center',
          onTap: () => _toast('Help Center — coming soon'),
        ),
        SettingsTile(
          icon: Icons.support_agent_rounded,
          color: AppColors.lightBlue,
          title: 'Contact Support',
          onTap: () => _toast('Contact Support — coming soon'),
        ),
        SettingsTile(
          icon: Icons.privacy_tip_rounded,
          color: AppColors.secondaryGreen,
          title: 'Privacy Policy',
          onTap: () => _toast('Privacy Policy — coming soon'),
        ),
        SettingsTile(
          icon: Icons.description_rounded,
          color: const Color(0xFF8B6CEF),
          title: 'Terms & Conditions',
          onTap: () => _toast('Terms & Conditions — coming soon'),
        ),
        SettingsTile(
          icon: Icons.info_outline_rounded,
          color: AppColors.warning,
          title: 'About INO',
          subtitle: 'Version 1.0.0',
          onTap: () => _toast('About INO — coming soon'),
        ),
      ],
    );
  }

  Widget _logoutButton() {
    return PressableScale(
      child: Material(
        color: AppColors.critical.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _confirmLogout,
          child: Container(
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(
                  color: AppColors.critical.withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded,
                    color: AppColors.critical, size: 20),
                SizedBox(width: 8),
                Text(
                  'Logout',
                  style: TextStyle(
                    color: AppColors.critical,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Small helpers -------------------------------------------------------

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

  Widget _valueTrailing(String value, AppPalette palette) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: AppText.caption.copyWith(
                color: palette.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 22, color: palette.textFaint),
      ],
    );
  }

  Widget _divider(AppPalette palette) => Divider(
        height: 1,
        thickness: 1,
        indent: 58,
        endIndent: 12,
        color: palette.border,
      );
}

/// The page title header ("Profile" + a short subtitle).
class _Header extends StatelessWidget {
  const _Header({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profile',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Manage your account & security',
          style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
        ),
      ],
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
