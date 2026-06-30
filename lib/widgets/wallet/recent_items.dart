import 'package:flutter/material.dart';

import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../dashboard/section_header.dart';

/// Section 5 — Recently Accessed.
///
/// A compact list of the last opened items, each with a gradient-tinted icon
/// chip, file name, a category badge and the last-opened time. Lives inside a
/// single card so the recents read as one tidy stack.
class RecentItemsSection extends StatelessWidget {
  const RecentItemsSection({super.key, required this.items, this.onOpen});

  final List<RecentItem> items;
  final void Function(RecentItem item)? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Recently Accessed',
          subtitle: 'Pick up where you left off',
          actionLabel: 'See all',
          icon: Icons.history_rounded,
        ),
        InoCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _RecentTile(item: items[i], onTap: () => onOpen?.call(items[i])),
                if (i != items.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 64,
                    endIndent: 16,
                    color: palette.border,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item, required this.onTap});

  final RecentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.30),
                      blurRadius: 9,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(item.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.category,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: item.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.lastOpened,
                          style:
                              TextStyle(fontSize: 11.5, color: palette.textFaint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
