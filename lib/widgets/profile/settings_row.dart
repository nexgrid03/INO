import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/shiny_icon.dart';

/// One row in a [SettingsGroup].
///
/// Follows the Stitch settings-row language: a glossy badge holding the row's
/// icon, a single-line title, and a trailing control - a [Switch], a muted
/// [value] label, or a chevron. The [danger] variant flips the accent to red
/// (Log Out / Delete Account), so hierarchy still comes from typography and
/// grouping.
///
/// Give each row its own [iconColor] so a long settings list reads as distinct
/// destinations rather than one repeated teal chip; it falls back to the brand
/// teal when omitted.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.value,
    this.onTap,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;

  /// The badge accent. Defaults to the brand teal; ignored when [danger] is set
  /// (destructive rows are always red).
  final Color? iconColor;

  /// An optional one-line explainer under the title (muted caption).
  final String? subtitle;

  /// A trailing widget (e.g. a [Switch]) that overrides the default chevron.
  final Widget? trailing;

  /// A muted trailing value (e.g. the selected language) shown before a chevron.
  final String? value;

  final VoidCallback? onTap;

  /// Destructive styling - red icon + title, no chevron (Log Out / Delete).
  final bool danger;

  /// Whether a chevron shows when the row is tappable and has no [trailing].
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color fg = danger ? AppColors.critical : palette.textPrimary;
    final Color accent = danger
        ? AppColors.critical
        : (iconColor ?? AppColors.primaryGreen);

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
          ShinyIcon(
            icon: icon,
            color: accent,
            size: 40,
            iconSize: 20,
            radius: 12,
            // Divine Glass: pastel glass chip carrying a coloured glyph, not a
            // saturated accent-filled badge.
            style: ShinyIconStyle.glass,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
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
