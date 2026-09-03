import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import 'quick_action_button.dart';

/// Launcher Quick Actions (4): Scan · Documents · Reminder · Voice.
///
/// Equal [Expanded] cells + shared disc sizing keep the row aligned.
class LauncherQuickActions extends StatelessWidget {
  const LauncherQuickActions({
    super.key,
    required this.onScan,
    required this.onAddDocument,
    required this.onAddReminder,
    required this.onVoice,
  });

  final VoidCallback onScan;
  final VoidCallback onAddDocument;
  final VoidCallback onAddReminder;
  final VoidCallback onVoice;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final use3d = InoStyle.usesHome3dIcons(context);
    final actions = [
      QuickActionButton(
        imageAsset: use3d ? InoHomeIcons3d.scan : null,
        svgAsset: use3d ? null : InoHomeIcons.scan,
        label: l10n.t('scan'),
        color: AppColors.primaryGreen,
        onTap: onScan,
        enlarged: true,
      ),
      QuickActionButton(
        imageAsset: use3d ? InoHomeIcons3d.documents : null,
        svgAsset: use3d ? null : InoHomeIcons.documents,
        label: l10n.t('documents'),
        color: AppColors.primaryGreen,
        onTap: onAddDocument,
        enlarged: true,
      ),
      QuickActionButton(
        imageAsset: use3d ? InoHomeIcons3d.reminder : null,
        svgAsset: use3d ? null : InoHomeIcons.reminder,
        label: l10n.t('reminder'),
        color: AppColors.primaryGreen,
        onTap: onAddReminder,
        enlarged: true,
      ),
      QuickActionButton(
        imageAsset: use3d ? InoHomeIcons3d.voice : null,
        svgAsset: use3d ? null : InoHomeIcons.voice,
        label: l10n.t('voice'),
        color: AppColors.primaryGreen,
        onTap: onVoice,
        enlarged: true,
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}
