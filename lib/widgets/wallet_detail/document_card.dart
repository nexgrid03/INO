import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    this.protected = false,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
  });

  final DocumentRecord record;
  final List<Color> accent;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  /// When true, this document is biometric-protected — shows a lock badge.
  final bool protected;

  /// When true the card renders in multi-select mode: swipe actions are
  /// disabled, a selection check replaces the ⋮ button, and [onOpen] is treated
  /// by the parent as a toggle.
  final bool selectionMode;

  /// Whether this card is currently selected (only meaningful in [selectionMode]).
  final bool selected;

  /// Long-press handler — used by the parent to enter multi-select mode.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (selectionMode) {
      return _card(
        context,
        onTap: onOpen,
        borderColor: selected ? AppColors.primaryGreen : null,
        trailing: _SelectionCheck(selected: selected),
      );
    }
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Dismissible(
      key: ValueKey(record.id),
      // Swipe right = favorite, swipe left = actions. Both are non-destructive:
      // confirmDismiss performs the action then returns false so the row stays.
      background: _swipeBg(
        align: Alignment.centerLeft,
        color: AppColors.primaryGreen,
        icon: record.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        label: record.isFavorite ? l10n.t('unfavorite') : l10n.t('favorite'),
      ),
      secondaryBackground: _swipeBg(
        align: Alignment.centerRight,
        color: AppColors.lightBlue,
        icon: Icons.more_horiz_rounded,
        label: l10n.t('actions'),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavorite();
        } else {
          onMore();
        }
        return false;
      },
      child: _card(
        context,
        onTap: onOpen,
        trailing: _moreButton(context),
      ),
      ),
    );
  }

  /// The card surface + its row content, shared by the normal and selection
  /// renderings so both look identical apart from the trailing control.
  Widget _card(
    BuildContext context, {
    VoidCallback? onTap,
    Color? borderColor,
    required Widget trailing,
  }) {
    return InoCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      borderColor: borderColor,
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
              if (protected)
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        size: 10, color: Colors.white),
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
          trailing,
        ],
      ),
    );
  }

  Widget _moreButton(BuildContext context) => IconButton(
        onPressed: onMore,
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.more_vert_rounded,
            color: AppPalette.of(context).textFaint),
        tooltip: AppLocalizations.of(context).t('quickActionsTooltip'),
      );

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

/// The circular check shown in place of the ⋮ button while multi-selecting.
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.primaryGreen : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primaryGreen : palette.textFaint,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
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
            status.localizedLabel(AppLocalizations.of(context)),
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
