import 'package:flutter/material.dart';

import '../../models/wallet_detail_models.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Section 5 — a single document record card.
///
/// Tap opens the viewer; the ⋮ button (and a swipe-left) opens the quick-action
/// menu (share / download / edit / move / delete); a swipe-right toggles
/// favorite. Shows a gradient icon chip, name, category · upload date, and a
/// colour-coded status badge. Premium mobile interactions, no extra packages.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.record,
    required this.accent,
    required this.onOpen,
    required this.onFavorite,
    required this.onMore,
  });

  final DocumentRecord record;
  final List<Color> accent;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(record.id),
      // Swipe right = favorite, swipe left = actions. Both are non-destructive:
      // confirmDismiss performs the action then returns false so the row stays.
      background: _swipeBg(
        align: Alignment.centerLeft,
        color: AppColors.primaryGreen,
        icon: record.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        label: record.isFavorite ? 'Unfavorite' : 'Favorite',
      ),
      secondaryBackground: _swipeBg(
        align: Alignment.centerRight,
        color: AppColors.lightBlue,
        icon: Icons.more_horiz_rounded,
        label: 'Actions',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavorite();
        } else {
          onMore();
        }
        return false;
      },
      child: InoCard(
        padding: const EdgeInsets.all(14),
        onTap: onOpen,
        child: Row(
          children: [
            // Gradient icon chip with a favorite star overlay.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: accent,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: accent.first.withValues(alpha: 0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(record.icon, color: Colors.white, size: 23),
                ),
                if (record.isFavorite)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.star_rounded,
                          size: 13, color: AppColors.warning),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _MetaLine(record: record),
                  const SizedBox(height: 7),
                  _StatusBadge(status: record.status),
                ],
              ),
            ),
            // Quick action menu.
            IconButton(
              onPressed: onMore,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_vert_rounded,
                  color: AppPalette.of(context).textFaint),
              tooltip: 'Quick actions',
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeBg({
    required Alignment align,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: align,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.record});

  final DocumentRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      '${record.category}  ·  ${inoFormatDate(record.uploadedAt)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: palette.textSecondary),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DocumentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
