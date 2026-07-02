import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/supabase_config.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// About INO — real app version, build number and environment, read from the
/// bundle via package_info_plus (never hard-coded).
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // Leave as null → shown as '—'.
    }
  }

  String get _environment {
    final host = Uri.tryParse(SupabaseConfig.url)?.host ?? '';
    final project = host.split('.').first;
    return project.isEmpty ? 'Production' : 'Production · $project';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final info = _info;
    final version = info?.version ?? '—';
    final build = info?.buildNumber ?? '—';
    final pkg = info?.packageName ?? '—';

    return SettingsScaffold(
      title: 'About INO',
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.lg, AppSpacing.screen, AppSpacing.xl),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('INO',
                    style: AppText.headline.copyWith(color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Intelligent Network Organizer',
                    style: AppText.body.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _InfoRow(label: 'Version', value: version, copyable: true),
                _divider(palette),
                _InfoRow(label: 'Build number', value: build),
                _divider(palette),
                _InfoRow(label: 'Package', value: pkg),
                _divider(palette),
                _InfoRow(label: 'Environment', value: _environment),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text('© ${_year()} INO. All rights reserved.',
                style: AppText.caption.copyWith(color: palette.textFaint)),
          ),
        ],
      ),
    );
  }

  static int _year() => DateTime.now().year;

  Widget _divider(AppPalette palette) =>
      Divider(height: 1, thickness: 1, color: palette.border, indent: 16, endIndent: 16);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: copyable
          ? () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                BiometricUx.successSnack(context, '$label copied.');
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(label,
                style: AppText.body.copyWith(color: palette.textSecondary)),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppText.subtitle.copyWith(color: palette.textPrimary),
              ),
            ),
            if (copyable) ...[
              const SizedBox(width: 6),
              Icon(Icons.copy_rounded, size: 15, color: palette.textFaint),
            ],
          ],
        ),
      ),
    );
  }
}
