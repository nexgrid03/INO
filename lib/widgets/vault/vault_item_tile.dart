import 'package:flutter/material.dart';

import '../../models/vault_item.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A single credential row in the vault list: category glyph, title, a masked
/// username, a favorite star, and a chevron. Tapping opens the detail screen.
class VaultItemTile extends StatelessWidget {
  const VaultItemTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final subtitle = item.username.isNotEmpty ? item.username : (item.url ?? '');

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.card),
          child: Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: item.category.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(item.category.icon,
                    color: item.category.color, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle
                          .copyWith(color: palette.textPrimary),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleFavorite,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  item.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: item.favorite
                      ? AppColors.warning
                      : palette.textFaint,
                  size: 22,
                ),
              ),
              Icon(AppIcons.chevron, color: palette.textFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
