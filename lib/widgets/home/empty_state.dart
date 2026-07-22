import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/illustration_badge.dart';
import '../profile/settings_scaffold.dart';

/// A meaningful empty state: a soft gradient illustration, a title, a short
/// description and an optional call-to-action. Reused across the dashboard's
/// destination pages (no activity, no notifications, no assets, …).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Premium illustrated badge (layered gradient discs + accent dots).
            IllustrationBadge(icon: icon, size: compact ? 84 : 120),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: 220,
                child: SettingsPrimaryButton(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full-page error state with a retry action — used for network / load
/// failures on the dashboard destination pages.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.onRetry,
    this.message,
  });

  final VoidCallback onRetry;

  /// Overrides the default "something went wrong" copy when provided.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: l10n.t('couldntLoad'),
      message: message ?? l10n.t('somethingWentWrong'),
      actionLabel: l10n.t('retry'),
      onAction: onRetry,
    );
  }
}
