import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
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
    final actions = [
      QuickActionButton(
        imageAsset: InoHomeIcons3d.scan,
        label: l10n.t('scan'),
        color: AppColors.primaryGreen,
        onTap: onScan,
        enlarged: true,
      ),
      QuickActionButton(
        imageAsset: InoHomeIcons3d.documents,
        label: l10n.t('documents'),
        color: AppColors.primaryGreen,
        onTap: onAddDocument,
        enlarged: true,
      ),
      QuickActionButton(
        imageAsset: InoHomeIcons3d.reminder,
        label: l10n.t('reminder'),
        color: AppColors.primaryGreen,
        onTap: onAddReminder,
        enlarged: true,
      ),
      QuickActionButton(
        imageAsset: InoHomeIcons3d.voice,
        label: l10n.t('voice'),
        color: AppColors.primaryGreen,
        onTap: onVoice,
        enlarged: true,
      ),
    ];

    Widget rowOf(List<Widget> kids) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < kids.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(child: kids[i]),
            ],
          ],
        );

    if (context.isMobileSmall) {
      return Column(
        children: [
          rowOf([actions[0], actions[1]]),
          const SizedBox(height: 12),
          rowOf([actions[2], actions[3]]),
        ],
      );
    }

    return rowOf(actions);
  }
}
