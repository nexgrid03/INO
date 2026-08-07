import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/wallet_detail_models.dart';
import '../../theme/app_theme.dart';
import '../common/shiny_icon.dart';
import '../dashboard/ino_card.dart';
import '../divine_glass/divine_glass.dart';

/// Section 5 - a single document record card.
///
/// Tap opens the viewer; the ⋮ button (and a swipe-left) opens the quick-action
/// menu (share / download / edit / move / delete); a swipe-right toggles
/// favorite. Shows a glossy icon badge, name, category · upload date, and a
/// colour-coded status badge. Premium mobile interactions, no extra packages.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.record,
    required this.onOpen,
    required this.onFavorite,
    required this.onMore,
    this.walletAccent,
    this.protected = false,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
  });

  /// Home My Vaults accent for this wallet — default chrome when no doc-type tint.
  final Color? walletAccent;

  Color get _iconColor => walletAccent ?? AppColors.primaryGreen;

  final DocumentRecord record;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  /// When true, this document is biometric-protected - shows a lock badge.
  final bool protected;

  /// When true the card renders in multi-select mode: swipe actions are
  /// disabled, a selection check replaces the ⋮ button, and [onOpen] is treated
  /// by the parent as a toggle.
  final bool selectionMode;

  /// Whether this card is currently selected (only meaningful in [selectionMode]).
  final bool selected;

  /// Long-press handler - used by the parent to enter multi-select mode.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (selectionMode) {
      return _card(
        context,
        onTap: onOpen,
        borderColor: selected ? _iconColor : null,
        trailing: _SelectionCheck(selected: selected, accent: _iconColor),
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
          color: _iconColor,
          icon: record.isFavorite
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
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
        child: _card(context, onTap: onOpen, trailing: _moreButton(context)),
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
    if (divineGlassEnabled(context)) {
      return _launcherCard(
        context,
        onTap: onTap,
        borderColor: borderColor,
        trailing: trailing,
      );
    }
    return InoCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      borderColor: borderColor,
      child: Row(
        children: [
          // Glossy icon badge with a favorite star overlay.
          Stack(
            clipBehavior: Clip.none,
            children: [
              ShinyIcon(
                icon: record.icon,
                color: _iconColor,
                size: 46,
                iconSize: 23,
                radius: 13,
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
                    child: const Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              if (protected)
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _iconColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
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
                _ExtractedSummary(record: record, accent: _iconColor),
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

  /// Figma Identity Wallet glass card (Launcher only).
  Widget _launcherCard(
    BuildContext context, {
    VoidCallback? onTap,
    Color? borderColor,
    required Widget trailing,
  }) {
    final accent = _accentFor(record);
    final meta = _launcherMeta(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DivineGlassDocumentCard(
          title: record.name,
          subtitle: '${record.category} · ${inoFormatDate(record.uploadedAt)}',
          icon: record.icon,
          accent: accent,
          status: record.status,
          leftMeta: meta.$1,
          rightMeta: meta.$2,
          onTap: onTap,
          trailing: selectionMode
              ? trailing
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DivineGlassStatusChip.fromStatus(record.status),
                    trailing,
                  ],
                ),
        ),
        if (record.isFavorite)
          const Positioned(
            top: 10,
            left: 52,
            child: Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
          ),
      ],
    );
  }

  Color _accentFor(DocumentRecord record) {
    final type = record.extraction.documentType?.toLowerCase() ?? '';
    if (type.contains('pan')) return const Color(0xFFCC9200);
    if (type.contains('passport')) return const Color(0xFF6B7FD7);
    if (type.contains('driving') || type.contains('license')) {
      return _iconColor;
    }
    if (type.contains('aadhaar') || type.contains('aadhar')) {
      return _iconColor;
    }
    final name = record.name.toLowerCase();
    if (name.contains('pan')) return const Color(0xFFCC9200);
    if (name.contains('passport')) return const Color(0xFF6B7FD7);
    if (name.contains('license') || name.contains('driving')) {
      return const Color(0xFF89F3F9);
    }
    // Health / medical docs get the mint accent used on the Health Wallet tile.
    final category = record.category.toLowerCase();
    if (category.contains('medical') ||
        category.contains('health') ||
        category.contains('prescription') ||
        category.contains('report')) {
      return const Color(0xFF22C55E);
    }
    return _iconColor;
  }

  (DivineGlassMetaCell, Widget) _launcherMeta(BuildContext context) {
    final palette = AppPalette.of(context);
    final data = record.extraction.data;
    final number = data['number'] ?? record.recordNumber;
    final masked = number == null || number.isEmpty
        ? '—'
        : _ExtractedSummary._maskedNumber(number);

    final left = DivineGlassMetaCell(
      label: record.expiresAt != null ? 'Expiry Date' : 'Number',
      value: record.expiresAt != null
          ? inoFormatDate(record.expiresAt!)
          : masked,
    );

    if (protected) {
      return (
        left,
        DivineGlassMetaCell(
          label: 'Security',
          value: 'Encrypted',
          alignEnd: true,
          valueColor: _iconColor,
          leading: Icon(
            Icons.lock_rounded,
            size: 14,
            color: _iconColor,
          ),
        ),
      );
    }

    final name = data['name'];
    if (name != null && name.trim().isNotEmpty) {
      return (
        left,
        DivineGlassMetaCell(
          label: 'Linked To',
          value: name.trim(),
          alignEnd: true,
        ),
      );
    }

    if (record.status == DocumentStatus.active) {
      return (
        left,
        DivineGlassMetaCell(
          label: 'Status',
          value: 'Verified',
          alignEnd: true,
          valueColor: _iconColor,
        ),
      );
    }

    return (
      left,
      DivineGlassMetaCell(
        label: 'Updated',
        value: inoFormatDate(record.updatedAt),
        alignEnd: true,
        valueColor: palette.textPrimary,
      ),
    );
  }

  Widget _moreButton(BuildContext context) => IconButton(
    onPressed: onMore,
    visualDensity: VisualDensity.compact,
    icon: Icon(
      Icons.more_vert_rounded,
      color: AppPalette.of(context).textFaint,
    ),
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
  const _SelectionCheck({required this.selected, required this.accent});

  final bool selected;
  final Color accent;

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
          color: selected ? accent : Colors.transparent,
          border: Border.all(
            color: selected ? accent : palette.textFaint,
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

/// A compact, at-a-glance summary of a document's KEY extracted (OCR) fields -
/// so the user sees the essentials (name / DOB / masked number) right in the
/// wallet list without opening the document. Renders nothing for documents with
/// no extracted data, so non-OCR records look exactly as before.
class _ExtractedSummary extends StatelessWidget {
  const _ExtractedSummary({required this.record, this.accent});

  final DocumentRecord record;
  final Color? accent;

  /// Masks the document number for a list view: the last 4 stay visible, the
  /// rest are hidden. A 12-digit Aadhaar keeps its familiar "XXXX XXXX 1234"
  /// grouping.
  static String _maskedNumber(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12) return 'XXXX XXXX ${digits.substring(8)}';
    if (v.length > 4) {
      return '${'•' * (v.length - 4)}${v.substring(v.length - 4)}';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final data = record.extraction.data;
    if (data.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[];
    void add(IconData icon, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) {
        chips.add(_MiniChip(
            icon: icon, label: v, palette: palette, accent: accent));
      }
    }

    add(Icons.person_rounded, data['name']);
    add(Icons.cake_rounded, data['dob']);
    final number = data['number'];
    if (number != null) add(Icons.tag_rounded, _maskedNumber(number));

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.palette,
    this.accent,
  });

  final IconData icon;
  final String label;
  final AppPalette palette;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.primaryGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tint),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
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
