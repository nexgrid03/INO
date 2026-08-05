import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// One row in a [SettingsGroup].
///
/// Follows the reference settings-row language: a solid brand-gradient badge
/// carrying a white glyph (the same "one uniform brand hue" treatment as the
/// Home quick actions), a single-line title, and a trailing control - a
/// [Switch], a muted [value] label, or a chevron. The [danger] variant flips
/// the badge to red (Log Out / Delete Account), so hierarchy still comes from
/// typography and grouping.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.value,
    this.onTap,
    this.danger = false,
    this.showChevron = true,
    this.accent,
  });

  final IconData icon;
  final String title;

  /// Optional badge colour (e.g. per-account avatar hue). Falls back to brand.
  final Color? accent;

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

    Widget? tail = trailing;
    if (tail == null && value != null) {
      tail = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.34,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppText.body.copyWith(color: palette.textSecondary),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: palette.textFaint),
          ],
        ),
      );
    } else {
      tail ??= (onTap != null && showChevron && !danger)
          ? Icon(Icons.chevron_right_rounded,
              size: 20, color: palette.textFaint)
          : null;
    }

    final Color? badgeAccent = danger ? null : accent;
    final Gradient? badgeGradient = danger
        ? null
        : (badgeAccent != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  badgeAccent,
                  Color.lerp(badgeAccent, const Color(0xFF0F172A), 0.28)!,
                ],
              )
            : AppColors.brandGradient);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: badgeGradient,
              color: danger ? AppColors.critical : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: (danger
                          ? AppColors.critical
                          : (badgeAccent ?? AppColors.primaryGreen))
                      .withValues(alpha: 0.26),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
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
