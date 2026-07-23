import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// One row in a [SettingsGroup].
///
/// Follows the Stitch settings-row language: a brand-tinted rounded square
/// holding a teal icon, a single-line title, and a trailing control — a
/// [Switch], a muted [value] label, or a chevron. The [danger] variant flips
/// the tint to red (Log Out / Delete Account), so hierarchy still comes from
/// typography and grouping.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.value,
    this.onTap,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;

  /// A trailing widget (e.g. a [Switch]) that overrides the default chevron.
  final Widget? trailing;

  /// A muted trailing value (e.g. the selected language) shown before a chevron.
  final String? value;

  final VoidCallback? onTap;

  /// Destructive styling — red icon + title, no chevron (Log Out / Delete).
  final bool danger;

  /// Whether a chevron shows when the row is tappable and has no [trailing].
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color fg = danger ? AppColors.critical : palette.textPrimary;
    final Color iconFg = danger ? AppColors.critical : AppColors.primaryGreen;
    final Color iconBg = danger
        ? AppColors.critical.withValues(alpha: 0.10)
        : AppColors.primaryGreen.withValues(alpha: palette.isDark ? 0.16 : 0.10);

    Widget? tail = trailing;
    tail ??= (value != null)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value!,
                style: AppText.body.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: palette.textFaint),
            ],
          )
        : (onTap != null && showChevron && !danger)
            ? Icon(Icons.chevron_right_rounded,
                size: 20, color: palette.textFaint)
            : null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconFg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: -0.1,
              ),
            ),
          ),
          if (tail != null) ...[const SizedBox(width: 8), tail],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
