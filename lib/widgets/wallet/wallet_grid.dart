import 'package:flutter/material.dart';

import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
import '../dashboard/fade_slide_in.dart';
import '../dashboard/ino_card.dart';
import '../dashboard/section_header.dart';

/// Section 3 — Wallet Categories grid.
///
/// A 2-column grid of large wallet cards. Each leads with a gradient icon chip,
/// names the wallet, previews its contents, and shows the headline metric
/// (documents, policies, portfolio value …). Cards stagger in for a premium
/// "vault unfolding" reveal and squish on press.
class WalletGrid extends StatelessWidget {
  const WalletGrid({super.key, required this.categories, this.onOpen});

  final List<WalletCategory> categories;
  final void Function(WalletCategory category)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Your Wallets',
          subtitle: '${categories.length} secure vaults',
          icon: Icons.grid_view_rounded,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 640 ? 3 : 2;
            const gap = 12.0;
            final cardW = (w - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < categories.length; i++)
                  SizedBox(
                    width: cardW,
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: (i * 60).clamp(0, 480)),
                      offset: 18,
                      child: _WalletCategoryCard(
                        category: categories[i],
                        onTap: () => onOpen?.call(categories[i]),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WalletCategoryCard extends StatelessWidget {
  const _WalletCategoryCard({required this.category, required this.onTap});

  final WalletCategory category;
  final VoidCallback onTap;

  String get _preview {
    final c = category.contents;
    if (c.isEmpty) return '';
    if (c.length <= 2) return c.join(' · ');
    return '${c.take(2).join(' · ')} +${c.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: category.gradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: category.gradient.first.withValues(alpha: 0.34),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(category.icon, color: Colors.white, size: 23),
              ),
              const Spacer(),
              Icon(Icons.arrow_outward_rounded,
                  size: 18, color: palette.textFaint),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  category.metric,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  category.metricLabel,
                  style: TextStyle(fontSize: 11.5, color: palette.textFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
