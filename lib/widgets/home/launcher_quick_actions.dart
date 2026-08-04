import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import 'quick_action_button.dart';

/// Launcher Quick Actions (4): Scan · Documents · Reminder · Voice.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = [
      QuickActionButton(
        svgAsset: InoHomeIcons.scan,
        label: l10n.t('scan'),
        color: AppColors.primaryGreen,
        onTap: onScan,
        enlarged: true,
      ),
      QuickActionButton(
        svgAsset: InoHomeIcons.documents,
        label: l10n.t('documents'),
        color: AppColors.primaryGreen,
        onTap: onAddDocument,
        enlarged: true,
      ),
      QuickActionButton(
        svgAsset: InoHomeIcons.reminder,
        label: l10n.t('reminder'),
        color: AppColors.primaryGreen,
        onTap: onAddReminder,
        enlarged: true,
      ),
      QuickActionButton(
        svgAsset: InoHomeIcons.voice,
        label: l10n.t('voice'),
        color: AppColors.primaryGreen,
        onTap: onVoice,
        enlarged: true,
      ),
    ];

    // Very narrow phones: 2×2 so discs stay tappable without horizontal overflow.
    if (context.isMobileSmall) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: actions[0]),
              const SizedBox(width: 8),
              Expanded(child: actions[1]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: actions[2]),
              const SizedBox(width: 8),
              Expanded(child: actions[3]),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}
