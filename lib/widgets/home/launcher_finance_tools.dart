import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import 'launcher_glass_icon_tile.dart';

/// Property & Finance Tools grid for Launcher (soft-3D PNG glass tiles).
///
/// Uses explicit tile widths from [LayoutBuilder] so three-across rows never
/// overflow / clip the last tile (e.g. SIP Calc) on phone widths.
class LauncherFinanceTools extends StatelessWidget {
  const LauncherFinanceTools({
    super.key,
    required this.onOpenArea,
    required this.onOpenEmi,
    required this.onOpenSip,
    required this.onOpenStampDuty,
    required this.onOpenUnitConv,
    required this.onOpenTax,
  });

  final VoidCallback onOpenArea;
  final VoidCallback onOpenEmi;
  final VoidCallback onOpenSip;
  final VoidCallback onOpenStampDuty;
  final VoidCallback onOpenUnitConv;
  final VoidCallback onOpenTax;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tools = [
      (
        label: l10n.t('areaCalc'),
        image: InoHomeIcons3d.finArea,
        accent: AppColors.primaryGreen,
        onTap: onOpenArea,
      ),
      (
        label: l10n.t('emiCalc'),
        image: InoHomeIcons3d.finEmi,
        accent: AppColors.accentIndigo,
        onTap: onOpenEmi,
      ),
      (
        label: l10n.t('sipCalc'),
        image: InoHomeIcons3d.finSip,
        accent: AppColors.accentViolet,
        onTap: onOpenSip,
      ),
      (
        label: l10n.t('stampDuty'),
        image: InoHomeIcons3d.finStamp,
        accent: AppColors.accentAmber,
        onTap: onOpenStampDuty,
      ),
      (
        label: l10n.t('unitConv'),
        image: InoHomeIcons3d.finUnit,
        accent: AppColors.accentCyan,
        onTap: onOpenUnitConv,
      ),
      (
        label: l10n.t('taxCalc'),
        image: InoHomeIcons3d.finTax,
        accent: AppColors.accentEmerald,
        onTap: onOpenTax,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perRow = context.toolsColumns.clamp(2, 3);
        final tileW = ((width - _gap * (perRow - 1)) / perRow)
            .clamp(0.0, width)
            .toDouble();

        final rows = <Widget>[];
        for (var i = 0; i < tools.length; i += perRow) {
          final end = (i + perRow).clamp(0, tools.length);
          final slice = tools.sublist(i, end);
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < slice.length; j++) ...[
                  if (j > 0) const SizedBox(width: _gap),
                  SizedBox(
                    width: tileW,
                    child: LauncherGlassIconTile(
                      label: slice[j].label,
                      imageAsset: slice[j].image,
                      accent: slice[j].accent,
                      onTap: slice[j].onTap,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
