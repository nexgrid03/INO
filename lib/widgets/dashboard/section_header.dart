import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Consistent header above every dashboard section: a title and an optional
/// trailing "See all" action. Keeps vertical rhythm uniform so the long scroll
/// reads as one organised system rather than stacked widgets.
///
/// [subtitle] is retained for call-site compatibility but is never rendered —
/// section headings are title-only across the app.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Deep brand teal — stays readable over the sky wash while scrolling,
    // unlike a faint TextButton default that blends into the gradient.
    final actionColor = AppColors.primaryGreen;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: iconColor ?? actionColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
                color: palette.headingInk,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (actionLabel != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: actionColor.withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: palette.isDark ? 0.25 : 0.05,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel!,
                        style: TextStyle(
                          color: actionColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: actionColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
