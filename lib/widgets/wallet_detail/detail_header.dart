import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 1 — Wallet Detail header.
///
/// Back button + search/filter controls, then a gradient wallet icon with the
/// wallet name & subtitle, and a totals row (documents · last updated). Mirrors
/// the home/wallet header styling for full consistency.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.totalDocuments,
    required this.lastUpdatedLabel,
    required this.onBack,
    required this.onSearch,
    required this.onFilter,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final int totalDocuments;
  final String lastUpdatedLabel;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _IconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: onBack,
            ),
            const Spacer(),
            _IconButton(
              icon: Icons.search_rounded,
              tooltip: 'Search',
              onTap: onSearch,
            ),
            const SizedBox(width: 8),
            _IconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Sort & filter',
              onTap: onFilter,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppShadows.glow(gradient.first, opacity: 0.34),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.folder_rounded, size: 15, color: palette.textFaint),
            const SizedBox(width: 6),
            Text(
              '$totalDocuments Documents',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 3, height: 3, decoration: BoxDecoration(
              color: palette.textFaint, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Icon(Icons.schedule_rounded, size: 15, color: palette.textFaint),
            const SizedBox(width: 6),
            Text(
              lastUpdatedLabel,
              style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 21, color: palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
