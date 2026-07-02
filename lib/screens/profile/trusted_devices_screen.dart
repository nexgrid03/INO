import 'package:flutter/material.dart';

import '../../services/trusted_device_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatting.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// Trusted Devices — the devices this install has recorded, with their last
/// active time and a "forget" action for anything but the current device.
class TrustedDevicesScreen extends StatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  State<TrustedDevicesScreen> createState() => _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends State<TrustedDevicesScreen> {
  List<TrustedDevice>? _devices;

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
    final ok = await TrustedDeviceService.instance.remove(device.id);
    if (!mounted) return;
    if (ok) {
      BiometricUx.successSnack(context, 'Removed ${device.name}.');
      _load();
    } else {
      BiometricUx.errorSnack(context, 'You can’t remove the current device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final devices = _devices;
    return SettingsScaffold(
      title: 'Trusted Devices',
      actions: [
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: palette.textPrimary),
          onPressed: _load,
        ),
      ],
      child: devices == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primaryGreen,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                    AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
                children: [
                  Text(
                    'These are the devices signed in to your INO account.',
                    style: AppText.body
                        .copyWith(color: palette.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                        child: const Text('This device',
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
                  'Active ${formatRelativeDate(device.lastActive)}',
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
              tooltip: 'Remove device',
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
