import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/supabase_config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// About INO - real app version, build number and environment, read from the
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
      // Leave as null → shown as '-'.
    }
  }

  String _environmentLabel(AppLocalizations l10n) {
    final host = Uri.tryParse(SupabaseConfig.url)?.host ?? '';
    final project = host.split('.').first;
    final production = l10n.t('production');
    return project.isEmpty ? production : '$production · $project';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final info = _info;
    final version = info?.version ?? '-';
    final build = info?.buildNumber ?? '-';
    final pkg = info?.packageName ?? '-';

    return SettingsScaffold(
      title: l10n.t('aboutIno'),
      child: ListView(
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
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'INO',
                  textAlign: TextAlign.center,
                  style:
                      AppText.headline.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.t('intelligentNetworkOrganizer'),
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _InfoRow(
                    label: l10n.t('version'), value: version, copyable: true),
                _divider(palette),
                _InfoRow(label: l10n.t('buildNumber'), value: build),
                _divider(palette),
                _InfoRow(label: l10n.t('package'), value: pkg),
                _divider(palette),
                _InfoRow(
                    label: l10n.t('environment'),
                    value: _environmentLabel(l10n)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Column(
              children: [
                Text(
                  l10n
                      .t('allRightsReserved')
                      .replaceFirst('{year}', '${_year()}'),
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t('poweredByNexgrid'),
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _year() => DateTime.now().year;

  Widget _divider(AppPalette palette) => Divider(
        height: 1,
        thickness: 1,
        color: palette.border,
        indent: 16,
        endIndent: 16,
      );
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

  static const double _labelWidth = 118;
  static const double _copySlot = 28;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: copyable
          ? () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                BiometricUx.successSnack(
                    context,
                    AppLocalizations.of(context)
                        .t('copiedLabel')
                        .replaceFirst('{label}', label));
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: AppText.subtitle.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: _copySlot,
              child: copyable
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: palette.textSecondary,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
