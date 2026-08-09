import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// One pending item shown in the Launcher Home strip.
class LauncherPendingItem {
  const LauncherPendingItem({
    required this.title,
    required this.status,
    required this.icon,
    required this.accent,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String status;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
}

/// Full-width review-banner strip under Needs attention.
///
/// Renders nothing when there are no items (no empty "No pending" plate).
class PendingActionsRow extends StatefulWidget {
  const PendingActionsRow({
    super.key,
    required this.items,
    this.onViewAll,
  });

  final List<LauncherPendingItem> items;

  /// Fallback for Review taps when an item has no [LauncherPendingItem.onTap].
  final VoidCallback? onViewAll;

  static const double stripHeight = 68;

  @override
  State<PendingActionsRow> createState() => _PendingActionsRowState();
}

class _PendingActionsRowState extends State<PendingActionsRow> {
  final Set<int> _dismissed = {};

  static const _glass = (
    enableBlur: false,
    frostLight: 0.78,
    frostDark: 1.2,
  );

  List<MapEntry<int, LauncherPendingItem>> get _visible {
    return [
      for (var i = 0; i < widget.items.length; i++)
        if (!_dismissed.contains(i)) MapEntry(i, widget.items[i]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    // Never render an empty "No pending items" plate — Home omits the strip.
    if (visible.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    final frost = dark ? _glass.frostDark : _glass.frostLight;

    return SizedBox(
      height: context.horizontalCardHeight(PendingActionsRow.stripHeight),
      width: double.infinity,
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(18),
        enableBlur: false,
        frost: frost,
        shadow: true,
        padding: EdgeInsets.zero,
        child: visible.length == 1
            ? _ReviewBanner(
                item: visible.first.value,
                onReview: visible.first.value.onTap ?? widget.onViewAll,
                onDismiss: () => setState(
                  () => _dismissed.add(visible.first.key),
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final entry = visible[i];
                  return SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.85,
                    child: _ReviewBanner(
                      item: entry.value,
                      onReview: entry.value.onTap ?? widget.onViewAll,
                      onDismiss: () =>
                          setState(() => _dismissed.add(entry.key)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Shield · title/subtitle · Review → · ✕
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({
    required this.item,
    this.onReview,
    this.onDismiss,
  });

  final LauncherPendingItem item;
  final VoidCallback? onReview;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final subtitle = item.subtitle ??
        (item.status.isEmpty ? 'Review now to stay on track' : item.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration:  BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (onReview != null)
            PressableScale(
              child: GestureDetector(
                onTap: onReview,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Review',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded,
                          size: 13, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}
