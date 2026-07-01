import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/profile_header_card.dart';
import '../../widgets/profile/settings_group.dart';
import '../../widgets/profile/settings_row.dart';
import '../auth/login_screen.dart';
import 'edit_profile_screen.dart';

/// The Profile screen — a premium, grouped **settings** page (Apple Settings /
/// Google Account), NOT a dashboard.
///
/// One primary element (the tappable identity header) followed by quiet,
/// uniform rows organised under small section captions. Emphasis comes from
/// typography and grouping; destructive actions sit at the very bottom as small
/// red rows. All controls preserve their existing behaviour (biometric,
/// language picker, theme toggle, confirmed logout, …).
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

class _ProfileScreenState extends State<ProfileScreen> {
  /// Local copy so edits show immediately; also pushed up via onProfileUpdated.
  late UserProfile _profile = widget.profile;
  late bool _biometric = widget.profile.biometricEnabled;
  bool _notifications = true;
  bool _autoBackup = true;
  late String _language = _languageLabel(widget.profile.preferredLanguage);

  bool get _isDark => widget.themeMode == ThemeMode.dark;

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

  // ---- Build ---------------------------------------------------------------

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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final p = _profile;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Ordered content: title, identity header, then grouped settings.
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
            trailing: _switch(_biometric, (v) {
              setState(() => _biometric = v);
              _toast('Biometric ${v ? 'enabled' : 'disabled'}');
            }),
          ),
          SettingsRow(
            icon: Icons.password_rounded,
            title: 'Change Password',
            onTap: () => _toast('Change Password — coming soon'),
          ),
          SettingsRow(
            icon: Icons.verified_user_rounded,
            title: 'Two-Factor Authentication',
            onTap: () => _toast('Two-Factor Authentication — coming soon'),
          ),
          SettingsRow(
            icon: Icons.devices_rounded,
            title: 'Trusted Devices',
            onTap: () => _toast('Trusted Devices — coming soon'),
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Data & Storage',
        children: [
          _StorageRow(
            usedLabel: '1.2 GB',
            totalLabel: '5 GB',
            fraction: 0.24,
          ),
          SettingsRow(
            icon: Icons.cloud_sync_rounded,
            title: 'Auto Backup',
            trailing:
                _switch(_autoBackup, (v) => setState(() => _autoBackup = v)),
          ),
          SettingsRow(
            icon: Icons.backup_rounded,
            title: 'Cloud Backup',
            onTap: () => _toast('Cloud Backup — coming soon'),
          ),
          SettingsRow(
            icon: Icons.file_download_outlined,
            title: 'Export Data',
            onTap: () => _toast('Export Data — coming soon'),
          ),
          SettingsRow(
            icon: Icons.download_for_offline_outlined,
            title: 'Download Account Data',
            onTap: () => _toast('Download Account Data — coming soon'),
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Preferences',
        children: [
          SettingsRow(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            trailing: _switch(
                _notifications, (v) => setState(() => _notifications = v)),
          ),
          SettingsRow(
            icon: Icons.dark_mode_rounded,
            title: 'Dark Mode',
            trailing: _switch(_isDark, (_) => widget.onToggleTheme()),
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
            onTap: () => _toast('Help Center — coming soon'),
          ),
          SettingsRow(
            icon: Icons.support_agent_rounded,
            title: 'Contact Support',
            onTap: () => _toast('Contact Support — coming soon'),
          ),
          SettingsRow(
            icon: Icons.info_outline_rounded,
            title: 'About INO',
            value: '1.0.0',
            onTap: () => _toast('About INO — coming soon'),
          ),
        ],
      ),
      SettingsGroup(
        caption: 'Legal',
        children: [
          SettingsRow(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy Policy',
            onTap: () => _toast('Privacy Policy — coming soon'),
          ),
          SettingsRow(
            icon: Icons.description_rounded,
            title: 'Terms & Conditions',
            onTap: () => _toast('Terms & Conditions — coming soon'),
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
            onTap: () => _toast('Delete Account — coming soon'),
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
            // Big breath under the title & header; roomy section gaps elsewhere.
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
/// slim gradient bar, so the progress cue stays without a dashboard card.
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
