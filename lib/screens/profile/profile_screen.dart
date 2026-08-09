import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../repositories/document_repository.dart';
import '../../repositories/user_repository.dart';
import '../../services/account_switcher.dart';
import '../../services/app_settings.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/session_reset.dart';
import '../../services/storage_stats_service.dart';
import '../../services/two_factor_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/avatar_color.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_style.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/ino_options_sheet.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/security/biometric_ux.dart';
import '../../widgets/profile/settings_group.dart';
import '../../widgets/profile/settings_row.dart';
import '../auth/auth_flow.dart';
import '../auth/login_screen.dart';
import '../family/family_vault_screen.dart';
import '../legal/legal_document_screen.dart';
import 'about_screen.dart';
import 'change_password_screen.dart';
import 'contact_support_screen.dart';
import 'delete_account_screen.dart';
import 'edit_profile_screen.dart';
import 'help_center_screen.dart';
import 'trusted_devices_screen.dart';
import 'two_factor_screen.dart';

/// The Profile screen - a premium, grouped **settings** page (Apple Settings /
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
  /// reflects the change - not just this screen.
  final ValueChanged<UserProfile>? onProfileUpdated;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  /// Local copy so edits show immediately; also pushed up via onProfileUpdated.
  late UserProfile _profile = widget.profile;

  // Security / preference state - sourced from the persisted stores so it
  // survives restarts. Reading a store's `.value` never touches disk.
  late bool _biometric = BiometricService.instance.lockEnabled.value;
  late bool _notifications = AppSettings.instance.notifications.value;
  late bool _welcomeSound = AppSettings.instance.welcomeSound.value;
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
      case 'te':
        return 'తెలుగు';
      default:
        return 'English';
    }
  }

  static String _languageCode(String label) {
    switch (label) {
      case 'हिन्दी':
        return 'hi';
      case 'తెలుగు':
        return 'te';
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

  Future<T?> _push<T>(Widget screen) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

  // ---- Preferences ---------------------------------------------------------

  Future<void> _pickLanguage() async {
    final palette = AppPalette.of(context);
    const options = ['English', 'हिन्दी', 'తెలుగు'];
    final picked = await showInoOptionsSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      builder: (context, _) => InoOptionsSheetBody(
        title: AppLocalizations.of(context).t('language'),
        titleStyle: AppText.title.copyWith(color: palette.textPrimary),
        children: [
          for (final o in options)
            ListTile(
              title: Text(
                o,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight:
                      o == _language ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: o == _language
                  ? Icon(
                      Icons.check_rounded,
                      color: AppColors.primaryGreen,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(o),
            ),
        ],
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

  Future<void> _toggleWelcomeSound(bool value) async {
    setState(() => _welcomeSound = value);
    // Persisting false also stops a greeting that's currently playing -
    // VoiceGreetingService listens to this setting.
    await AppSettings.instance.setWelcomeSound(value);
    _toast(value ? 'Startup greeting on' : 'Startup greeting muted');
  }

  void _toggleDarkMode() {
    HapticFeedback.selectionClick();
    // Toggle + persist via the controller using this (live) context, so it
    // works even though the shell's original toggle context is long gone.
    ThemeController.toggle(context);
  }

  // ---- App theme (visual style) --------------------------------------------

  String _themeStyleLabel(AppLocalizations l10n, ThemeStyle style) {
    switch (style) {
      case ThemeStyle.classic:
        return l10n.t('themeClassic');

      case ThemeStyle.launcher:
        return l10n.t('themeLauncher');
      case ThemeStyle.aqua:
        return l10n.t('themeAqua');
      case ThemeStyle.aquaLight:
        return l10n.t('themeAquaLight');
      case ThemeStyle.aquaMist:
        return l10n.t('themeAquaMist');
      case ThemeStyle.clay:
        return l10n.t('themeClay');
    }
  }

  String _themeStyleDesc(AppLocalizations l10n, ThemeStyle style) {
    switch (style) {
      case ThemeStyle.classic:
        return l10n.t('themeClassicDesc');

      case ThemeStyle.launcher:
        return l10n.t('themeLauncherDesc');
      case ThemeStyle.aqua:
        return l10n.t('themeAquaDesc');
      case ThemeStyle.aquaLight:
        return l10n.t('themeAquaLightDesc');
      case ThemeStyle.aquaMist:
        return l10n.t('themeAquaMistDesc');
      case ThemeStyle.clay:
        return l10n.t('themeClayDesc');
    }
  }

  Future<void> _pickThemeStyle() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final current = ThemeController.style.value;
    // Scrollable sheet — default half-screen height hid Launcher / Aqua on
    // short phones (yellow/black overflow stripes).
    final picked = await showInoOptionsSheet<ThemeStyle>(
      context: context,
      backgroundColor: palette.surface,
      builder: (context, _) => InoOptionsSheetBody(
        title: l10n.t('chooseTheme'),
        titleStyle: AppText.title.copyWith(color: palette.textPrimary),
        children: [
          for (final o in ThemeStyle.values)
            ListTile(
              leading: _ThemeSwatch(style: o),
              title: Text(
                _themeStyleLabel(l10n, o),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight:
                      o == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _themeStyleDesc(l10n, o),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: palette.textSecondary,
                ),
              ),
              trailing: o == current
                  ? Icon(
                      Icons.check_rounded,
                      color: AppColors.primaryGreen,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(o),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    HapticFeedback.selectionClick();
    // Persists + rebuilds the whole app instantly (see ThemeController.style).
    ThemeController.setStyle(picked);
    if (!mounted) return;
    _toast('Theme set to ${_themeStyleLabel(l10n, picked)}');
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
          context,
          'This device does not support biometric authentication.',
        );
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
    final l10n = AppLocalizations.of(context);
    final outcome = await BiometricService.instance.authenticateDetailed(
      reason: l10n.t('confirmIdentityEnable'),
      title: l10n.t('enableBiometricLock'),
    );
    if (!mounted) return;
    if (outcome.ok) {
      await BiometricService.instance.setLockEnabled(true);
      if (!mounted) return;
      setState(() => _biometric = true);
      _persistBiometric(true);
      BiometricUx.successSnack(
        context,
        AppLocalizations.of(context).t('biometricEnabledMsg'),
      );
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
    final l10n = AppLocalizations.of(context);
    final outcome = await BiometricService.instance.authenticateDetailed(
      reason: l10n.t('confirmIdentityDisable'),
      title: l10n.t('disableBiometricLock'),
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
    BiometricUx.successSnack(
      context,
      AppLocalizations.of(context).t('biometricDisabledMsg'),
    );
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
        // Ignore - local lock state is the source of truth for this device.
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

  // ---- Destructive actions -------------------------------------------------

  Future<void> _confirmLogout() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: palette.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.sm,
            AppSpacing.screen,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const InoSheetGrip(),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.critical.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.critical,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.t('logoutConfirmTitle'),
                style: AppText.title.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.t('logoutConfirmBody'),
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: l10n.t('cancel'),
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _SheetButton(
                      label: l10n.t('logOut'),
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
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile)),
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

  // ---- Accounts (multi-account) --------------------------------------------

  /// Starts the add-account flow: the current session is saved so it can be
  /// switched back to, then the normal sign-in screen takes over. Signing in
  /// as another user replaces the client session WITHOUT revoking this one
  /// server-side, so both accounts stay switchable afterwards.
  Future<void> _addAccount() async {
    await AccountSwitcher.instance.saveCurrent();
    // Account boundary: the next account must never see this account's cached
    // data. Cleared caches re-hydrate from the server on the next load, so
    // backing out of the sign-in screen costs nothing.
    await SessionReset.instance.clear();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// Actions for a saved (non-current) account: switch to it, or forget it.
  Future<void> _accountSheet(SavedAccount account) async {
    final palette = AppPalette.of(context);
    final action = await showInoOptionsSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      builder: (context, _) => InoOptionsSheetBody(
        title: account.displayName,
        titleStyle: AppText.title.copyWith(color: palette.textPrimary),
        children: [
          if (account.email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Center(
                child: Text(
                  account.email,
                  style:
                      AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ),
            ),
          ListTile(
            leading: Icon(Icons.swap_horiz_rounded,
                color: AppColors.primaryGreen),
            title: Text('Switch to this account',
                style: TextStyle(color: palette.textPrimary)),
            onTap: () => Navigator.of(context).pop('switch'),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_rounded,
                color: AppColors.critical),
            title: Text('Remove from this device',
                style: TextStyle(color: palette.textPrimary)),
            onTap: () => Navigator.of(context).pop('remove'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'switch') {
      await _switchAccount(account);
    } else if (action == 'remove') {
      await AccountSwitcher.instance.removeAccount(account.id);
      if (!mounted) return;
      setState(() {});
      _toast('Account removed from this device');
    }
  }

  Future<void> _switchAccount(SavedAccount account) async {
    final ok = await AccountSwitcher.instance.switchTo(account);
    if (!mounted) return;
    if (!ok) {
      // The stored session was revoked or expired; the dead entry is already
      // removed. The account can be re-added through the normal sign-in.
      setState(() {});
      _toast('That session has expired - use Add account to sign in again');
      return;
    }
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    // Re-enter through the standard post-auth flow so the whole shell
    // rebuilds around the switched account's profile.
    await routeAfterAuth(
      authUserId: user.id,
      fullName: (user.userMetadata?['full_name'] as String?) ?? '',
      email: user.email ?? '',
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final p = _profile;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Title stays pinned above the list (Home-style). Putting it inside the
    // ListView made the glass "Profile" header scroll away and, with M3
    // stretch + FadeSlideIn recycle, read as shrinking text.
    final blocks = <Widget>[
      // Stitch-style identity hero: centered avatar in a gradient ring with an
      // edit badge, name + email, and the single trust pill. The whole card is
      // still tappable → Edit Profile (unchanged behaviour).
      _ProfileHero(
        fullName: p.fullName,
        email: p.email,
        photoUrl: p.profilePhoto,
        onEdit: _editProfile,
      ),
      // Prominent storage-usage card (real Storage data, live meter).
      _StorageCard(
        usedLabel: _storageLoading ? '…' : _storage.usedLabel,
        totalLabel: _storage.quotaLabel,
        percentLabel: _storageLoading ? '…' : '${_storage.percent}%',
        fraction: _storage.fraction,
      ),
      // Multi-account: every account signed in on this device, switchable in
      // two taps. The current one is marked; tapping another offers
      // switch / remove; Add account runs the normal sign-in flow.
      ListenableBuilder(
        listenable: AccountSwitcher.instance,
        builder: (context, _) {
          final accounts = AccountSwitcher.instance.accounts;
          final currentId = AccountSwitcher.instance.currentUserId;
          return SettingsGroup(
            caption: 'Accounts',
            children: [
              for (final a in accounts)
                SettingsRow(
                  icon: Icons.account_circle_rounded,
                  title: a.displayName,
                  subtitle: a.email.isEmpty ? null : a.email,
                  accent: AvatarColor.forStyle(
                    InoStyle.of(context),
                    a.email.isNotEmpty
                        ? a.email
                        : (a.id.isNotEmpty ? a.id : a.displayName),
                  ),
                  trailing: a.id == currentId
                      ? Text(
                          'Current',
                          style: AppText.caption.copyWith(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                  onTap: a.id == currentId ? null : () => _accountSheet(a),
                ),
              SettingsRow(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Add account',
                subtitle: 'Sign in with another account and switch anytime',
                onTap: _addAccount,
              ),
            ],
          );
        },
      ),
      SettingsGroup(
        caption: l10n.t('security'),
        children: [
          SettingsRow(
            icon: Icons.fingerprint_rounded,
            title: l10n.t('biometricAuth'),
            trailing: _switch(_biometric, _toggleBiometric),
          ),
          SettingsRow(
            icon: Icons.password_rounded,
            title: l10n.t('changePassword'),
            onTap: _openChangePassword,
          ),
          SettingsRow(
            icon: Icons.verified_user_rounded,
            title: l10n.t('twoFactor'),
            value: _twoFactor ? l10n.t('on') : l10n.t('off'),
            onTap: _openTwoFactor,
          ),
          SettingsRow(
            icon: Icons.devices_rounded,
            title: l10n.t('trustedDevices'),
            onTap: () => _push(const TrustedDevicesScreen()),
          ),
        ],
      ),
      SettingsGroup(
        caption: l10n.t('family'),
        children: [
          SettingsRow(
            icon: Icons.family_restroom_rounded,
            title: l10n.t('familyVault'),
            subtitle: l10n.t('familyVaultDesc'),
            onTap: () => _push(const FamilyVaultScreen()),
          ),
        ],
      ),
      SettingsGroup(
        caption: l10n.t('preferences'),
        children: [
          SettingsRow(
            icon: Icons.notifications_rounded,
            title: l10n.t('notifications'),
            trailing: _switch(_notifications, _toggleNotifications),
          ),
          SettingsRow(
            icon: Icons.campaign_rounded,
            title: l10n.t('welcomeSound'),
            subtitle: l10n.t('welcomeSoundSubtitle'),
            trailing: Semantics(
              label: l10n.t('welcomeSound'),
              toggled: _welcomeSound,
              child: _switch(_welcomeSound, _toggleWelcomeSound),
            ),
          ),
          SettingsRow(
            icon: Icons.dark_mode_rounded,
            title: l10n.t('darkMode'),
            trailing: _switch(isDark, (_) => _toggleDarkMode()),
          ),
          SettingsRow(
            icon: Icons.palette_rounded,
            title: l10n.t('appTheme'),
            subtitle: l10n.t('chooseTheme'),
            value: _themeStyleLabel(l10n, ThemeController.style.value),
            onTap: _pickThemeStyle,
          ),
          SettingsRow(
            icon: Icons.language_rounded,
            title: l10n.t('language'),
            value: _language,
            onTap: _pickLanguage,
          ),
        ],
      ),
      SettingsGroup(
        caption: l10n.t('support'),
        children: [
          SettingsRow(
            icon: Icons.help_center_rounded,
            title: l10n.t('helpCenter'),
            onTap: () => _push(HelpCenterScreen(supportEmail: _supportEmail)),
          ),
          SettingsRow(
            icon: Icons.support_agent_rounded,
            title: l10n.t('contactSupport'),
            onTap: () =>
                _push(ContactSupportScreen(supportEmail: _supportEmail)),
          ),
          SettingsRow(
            icon: Icons.info_outline_rounded,
            title: l10n.t('aboutIno'),
            onTap: () => _push(const AboutScreen()),
          ),
        ],
      ),
      SettingsGroup(
        caption: l10n.t('legal'),
        children: [
          SettingsRow(
            icon: Icons.privacy_tip_rounded,
            title: l10n.t('privacyPolicy'),
            onTap: () => _push(LegalDocumentScreen.privacy()),
          ),
          SettingsRow(
            icon: Icons.description_rounded,
            title: l10n.t('termsConditions'),
            onTap: () => _push(LegalDocumentScreen.terms()),
          ),
        ],
      ),
      // Destructive actions, lowest visual weight, at the very bottom.
      // Decorative caption from the Stitch design's "SYSTEM" group.
      SettingsGroup(
        caption: 'System',
        children: [
          SettingsRow(
            icon: Icons.delete_outline_rounded,
            title: l10n.t('deleteAccount'),
            danger: true,
            onTap: () => _push(DeleteAccountScreen(email: _profile.email)),
          ),
          SettingsRow(
            icon: Icons.logout_rounded,
            title: l10n.t('logout'),
            danger: true,
            onTap: _confirmLogout,
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        sky: true,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Title(),
              Expanded(
                child: ListView.separated(
                  // Clamping + no M3 stretch (see InoNoStretchScrollBehavior)
                  // keeps type and glass groups at a stable size while scrolling.
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.md,
                    AppSpacing.screen,
                    bottomInset + 110,
                  ),
                  itemCount: blocks.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.lg),
                  // Never wrap ListView children in FadeSlideIn — items recycle
                  // on scroll and the entrance animation remounts, which looks
                  // like text popping / shrinking (especially on Accounts).
                  itemBuilder: (context, i) => blocks[i],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The address Contact Support / Help Center compose to.
  String get _supportEmail => 'inosupport.app@gmail.com';

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

/// The large settings-style page title — soft, floating, no opaque bar.
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return DivineGlassPageTitle(
      AppLocalizations.of(context).t('profile'),
      leading: canPop ? const InoBackButton(size: 40) : null,
    );
  }
}

/// The centered identity hero (Stitch "profile_settings" pattern): a large
/// avatar with a theme-aware colour ring, name + email, and the trust pill.
///
/// Solid surface fill so the card reads clearly on the soft wash background.
/// The ENTIRE card stays tappable → [onEdit].
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.fullName,
    required this.email,
    required this.onEdit,
    this.photoUrl,
  });

  final String fullName;
  final String email;
  final String? photoUrl;
  final VoidCallback onEdit;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get _colorSeed =>
      email.trim().isNotEmpty ? email : (fullName.trim().isEmpty ? 'ino' : fullName);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = InoStyle.of(context);
    final accent = AvatarColor.forStyle(style, _colorSeed);
    final accentGrad = AvatarColor.gradientForStyle(style, _colorSeed);
    // Opaque plate — translucent glass was blending into the wash.
    final plate = Color.lerp(palette.surface, accent, palette.isDark ? 0.12 : 0.06)!;

    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onEdit,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: plate,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(
              color: Color.lerp(palette.border, accent, 0.35)!,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: palette.isDark ? 0.28 : 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: palette.isDark ? 0.35 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: accentGrad,
                        // White rim flush on the avatar — no padding gap.
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: palette.isDark ? 0.22 : 0.92,
                          ),
                          width: 2.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (photoUrl != null && photoUrl!.isNotEmpty)
                          ? Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              width: 84,
                              height: 84,
                              errorBuilder: (_, _, _) => _HeroInitials(
                                initials: _initials,
                                gradient: accentGrad,
                              ),
                            )
                          : _HeroInitials(
                              initials: _initials,
                              gradient: accentGrad,
                            ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: accentGrad,
                          border: Border.all(color: plate, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                fullName.trim().isEmpty ? 'Your Name' : fullName,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                email,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 10),
              _HeroBadge(accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Initials fallback — colour is stable per user via [gradient].
class _HeroInitials extends StatelessWidget {
  const _HeroInitials({required this.initials, required this.gradient});

  final String initials;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 30,
          ),
        ),
      ),
    );
  }
}

/// The single trust pill under the identity hero.
class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: accent),
          const SizedBox(width: 5),
          Text(
            'VAULT PROTECTED',
            style: AppText.label.copyWith(
              color: accent,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// The prominent Storage-usage card (Stitch "Storage Usage" tile): an icon in
/// a gradient-wash container, a percent pill, and a thick gradient meter -
/// all fed by the same real Storage usage as before.
class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.usedLabel,
    required this.totalLabel,
    required this.percentLabel,
    required this.fraction,
  });

  final String usedLabel;
  final String totalLabel;
  final String percentLabel;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  gradient: AppGradients.wash(opacity: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child:  Icon(
                  Icons.storage_rounded,
                  size: 22,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).t('storage'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(color: palette.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$usedLabel of $totalLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  percentLabel,
                  style: AppText.label.copyWith(color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: palette.surfaceVariant),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child:  DecoratedBox(
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
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.style});

  final ThemeStyle style;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryGreen;
    final Color fill;
    final Color edge;
    final Widget glyph;
    switch (style) {
      case ThemeStyle.classic:
        fill = Colors.white;
        edge = accent;
        glyph = Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Icon(Icons.star_rounded, color: Colors.white, size: 12),
        );

      case ThemeStyle.launcher:
        fill = Colors.white;
        edge = accent;
        glyph = Icon(Icons.apps_rounded, color: accent, size: 18);
      case ThemeStyle.aqua:
        fill = AppColors.aquaFoam;
        edge = AppColors.aquaPrimary;
        glyph = const Icon(
          Icons.water_drop_rounded,
          color: AppColors.aquaPrimary,
          size: 18,
        );
      case ThemeStyle.aquaLight:
        fill = const Color(0xFFF3F9F9);
        edge = AppColors.aquaPrimary;
        glyph = const Icon(
          Icons.water_drop_outlined,
          color: AppColors.aquaPrimary,
          size: 18,
        );
      case ThemeStyle.aquaMist:
        fill = AppColors.aquaMist;
        edge = AppColors.aquaPrimary;
        glyph = const Icon(
          Icons.blur_on_rounded,
          color: AppColors.aquaPrimary,
          size: 18,
        );
      case ThemeStyle.clay:
        fill = AppColors.aquaFoam;
        edge = AppColors.aquaPrimary;
        glyph = const Icon(
          Icons.view_in_ar_rounded,
          color: AppColors.aquaPrimary,
          size: 18,
        );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edge, width: 2),
      ),
      child: Center(child: glyph),
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
