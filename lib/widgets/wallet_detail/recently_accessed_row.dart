import 'package:flutter/material.dart';

import '../../models/wallet_models.dart' show RecentItem;
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../dashboard/section_header.dart';
import '../pressable_scale.dart';

/// Section 6 — Recently Accessed (horizontal).
///
/// A horizontally scrolling row of recently viewed records, each a compact card
/// with a tinted icon chip, name, category and last-viewed time.
class RecentlyAccessedRow extends StatelessWidget {
  const RecentlyAccessedRow({super.key, required this.items, this.onOpen});

  final List<RecentItem> items;
  final void Function(RecentItem item)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Recently Accessed',
          subtitle: 'Jump back in',
          icon: Icons.history_rounded,
        ),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RecentCard(
              item: items[i],
              onTap: () => onOpen?.call(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item, required this.onTap});

  final RecentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: SizedBox(
        width: 150,
        child: InoCard(
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
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
              const Spacer(),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${item.category} · ${item.lastOpened}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: palette.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
