import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import 'launcher_glass_icon_tile.dart';

/// Property & Finance Tools grid for Launcher (SVG glass tiles).
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
        svg: InoHomeIcons.area,
        accent: AppColors.primaryGreen,
        onTap: onOpenArea,
      ),
      (
        label: l10n.t('emiCalc'),
        svg: InoHomeIcons.emi,
        accent: AppColors.accentIndigo,
        onTap: onOpenEmi,
      ),
      (
        label: l10n.t('sipCalc'),
        svg: InoHomeIcons.sip,
        accent: AppColors.accentViolet,
        onTap: onOpenSip,
      ),
      (
        label: l10n.t('stampDuty'),
        svg: InoHomeIcons.stamp,
        accent: AppColors.accentAmber,
        onTap: onOpenStampDuty,
      ),
      (
        label: l10n.t('unitConv'),
        svg: InoHomeIcons.unit,
        accent: AppColors.accentCyan,
        onTap: onOpenUnitConv,
      ),
      (
        label: l10n.t('taxCalc'),
        svg: InoHomeIcons.tax,
        accent: AppColors.accentEmerald,
        onTap: onOpenTax,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Phone: always 3 across so SIP is fully visible; never overflow.
        const perRow = 3;
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
                      svgAsset: slice[j].svg,
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
