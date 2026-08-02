import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// One pending item shown in the Launcher Home horizontal strip.
class LauncherPendingItem {
  const LauncherPendingItem({
    required this.title,
    required this.status,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String title;
  final String status;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
}

/// PhonePe-style horizontal pending cards (Launcher theme only).
class PendingActionsRow extends StatelessWidget {
  const PendingActionsRow({
    super.key,
    required this.items,
    this.onViewAll,
  });

  final List<LauncherPendingItem> items;
  final VoidCallback? onViewAll;

  static const _glass = (
    enableBlur: false,
    frostLight: 0.72,
    frostDark: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    final frost = dark ? _glass.frostDark : _glass.frostLight;

    if (items.isEmpty) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(16),
                enableBlur: false,
                frost: frost,
                shadow: false,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.t('noPendingItems'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            if (onViewAll != null) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: PressableScale(
                  pressedScale: 0.97,
                  child: GestureDetector(
                    onTap: onViewAll,
                    behavior: HitTestBehavior.opaque,
                    child: LiquidGlass(
                      borderRadius: BorderRadius.circular(16),
                      enableBlur: false,
                      frost: frost,
                      shadow: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                l10n.t('viewOthers'),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.primaryGreen,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: AppColors.primaryGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length + (onViewAll != null ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (onViewAll != null && i == items.length) {
            return PressableScale(
              child: GestureDetector(
                onTap: onViewAll,
                child: LiquidGlass(
                  borderRadius: BorderRadius.circular(16),
                  enableBlur: false,
                  frost: frost,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: const Center(
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.primaryGreen,
                      size: 32,
                    ),
                  ),
                ),
              ),
            );
          }
          final item = items[i];
          return PressableScale(
            child: GestureDetector(
              onTap: item.onTap,
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(16),
                enableBlur: false,
                frost: frost,
                shadow: false,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: SizedBox(
                  width: 164,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: item.accent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          item.icon,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: item.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
