import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/trusted_device_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatting.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';
import '../../widgets/common/ino_loader.dart';

/// Active Sessions - server-backed real device session management.
class TrustedDevicesScreen extends StatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  State<TrustedDevicesScreen> createState() => _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends State<TrustedDevicesScreen> {
  List<TrustedDevice>? _devices;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devices = await TrustedDeviceService.instance.list();
    if (!mounted) return;
    setState(() => _devices = devices);
  }

  Future<void> _remove(TrustedDevice device) async {
    final l10n = AppLocalizations.of(context);
    final ok = await TrustedDeviceService.instance.remove(device.id);
    if (!mounted) return;
    if (ok) {
      BiometricUx.successSnack(
        context,
        l10n.t('removedDevice').replaceAll('{name}', device.name),
      );
      _load();
    } else {
      BiometricUx.errorSnack(context, l10n.t('cantRemoveCurrentDevice'));
    }
  }

  Future<void> _signOutOtherDevices() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          l10n.t('signOutOtherDevices'),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          'Are you sure you want to sign out of all other devices?',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out', style: TextStyle(color: AppColors.critical)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _actionLoading = true);
    final ok = await TrustedDeviceService.instance.signOutOtherDevices();
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (ok) {
      BiometricUx.successSnack(
        context,
        'Signed out of all other devices',
      );
      _load();
    } else {
      BiometricUx.errorSnack(context, 'Failed to sign out other devices');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final devices = _devices;
    final otherDevicesExist = devices?.any((d) => !d.isCurrent) ?? false;

    return SettingsScaffold(
      title: 'Active Sessions',
      actions: [
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: palette.textPrimary),
          onPressed: _load,
        ),
      ],
      child: devices == null || _actionLoading
          ? const Center(child: InoLoader())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primaryGreen,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                    AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
                children: [
                  Text(
                    'Active device sessions registered on your account. Revoking a session signs out that device remotely.',
                    style: AppText.body.copyWith(
                      color: palette.textPrimary,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (otherDevicesExist) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.critical,
                        side: const BorderSide(color: AppColors.critical),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                      ),
                      onPressed: _signOutOtherDevices,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Sign Out Other Devices',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  for (final d in devices) ...[
                    _DeviceTile(device: d, onRemove: () => _remove(d)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onRemove});

  final TrustedDevice device;
  final VoidCallback onRemove;

  IconData get _icon => switch (device.platform) {
        'Android' || 'iOS' => Icons.smartphone_rounded,
        'macOS' || 'Windows' || 'Linux' => Icons.laptop_mac_rounded,
        _ => Icons.devices_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: AppColors.primaryGreen, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary),
                      ),
                    ),
                    if (device.isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(l10n.t('thisDevice'),
                            style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.t('activeAgo').replaceAll(
                        '{when}',
                        formatRelativeDate(l10n, device.lastActive),
                      ),
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          if (!device.isCurrent)
            IconButton(
              icon: const Icon(Icons.logout_rounded,
                  color: AppColors.critical, size: 20),
              onPressed: onRemove,
              tooltip: 'Revoke session & sign out',
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
