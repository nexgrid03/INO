import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import 'launcher_glass_icon_tile.dart';

/// My Vaults: same glass box for every vault + PhonePe-sized coloured SVGs.
class MyVaultsRow extends StatelessWidget {
  const MyVaultsRow({
    super.key,
    required this.identityCount,
    required this.propertyCount,
    required this.investmentCount,
    required this.cardsCount,
    required this.onIdentity,
    required this.onProperty,
    required this.onInvestments,
    required this.onCards,
  });

  final int identityCount;
  final int propertyCount;
  final int investmentCount;
  final int cardsCount;
  final VoidCallback onIdentity;
  final VoidCallback onProperty;
  final VoidCallback onInvestments;
  final VoidCallback onCards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      (
        label: l10n.t('identity'),
        count: identityCount,
        svg: InoHomeIcons.identity,
        accent: AppColors.vaultIdentity,
        onTap: onIdentity,
      ),
      (
        label: l10n.t('property'),
        count: propertyCount,
        svg: InoHomeIcons.property,
        accent: AppColors.vaultProperty,
        onTap: onProperty,
      ),
      (
        label: l10n.t('investments'),
        count: investmentCount,
        svg: InoHomeIcons.investments,
        accent: AppColors.vaultInvestments,
        onTap: onInvestments,
      ),
      (
        label: l10n.t('cards'),
        count: cardsCount,
        svg: InoHomeIcons.cards,
        accent: AppColors.vaultCards,
        onTap: onCards,
      ),
    ];

    Widget tile(int i) => LauncherGlassIconTile(
          label: items[i].label,
          count: items[i].count,
          svgAsset: items[i].svg,
          accent: items[i].accent,
          onTap: items[i].onTap,
        );

    // Narrow phones: 2×2 keeps labels readable.
    if (context.isMobileSmall) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: tile(0)),
              const SizedBox(width: 10),
              Expanded(child: tile(1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: tile(2)),
              const SizedBox(width: 10),
              Expanded(child: tile(3)),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tile(i)),
        ],
      ],
    );
  }
}
