import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import 'launcher_glass_icon_tile.dart';

/// Property & Finance Tools grid for Divine Glass Home.
///
/// [ThemeStyle.clay] uses soft-3D PNGs; aqua / launcher / aquaLight restore
/// the tinted SVG set from before the 3D Home icons landed.
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
    final use3d = InoStyle.usesHome3dIcons(context);
    final tools = [
      (
        label: l10n.t('areaCalc'),
        image: use3d ? InoHomeIcons3d.finArea : null,
        svg: use3d ? null : InoHomeIcons.area,
        accent: AppColors.primaryGreen,
        onTap: onOpenArea,
      ),
      (
        label: l10n.t('emiCalc'),
        image: use3d ? InoHomeIcons3d.finEmi : null,
        svg: use3d ? null : InoHomeIcons.emi,
        accent: AppColors.accentIndigo,
        onTap: onOpenEmi,
      ),
      (
        label: l10n.t('sipCalc'),
        image: use3d ? InoHomeIcons3d.finSip : null,
        svg: use3d ? null : InoHomeIcons.sip,
        accent: AppColors.accentViolet,
        onTap: onOpenSip,
      ),
      (
        label: l10n.t('stampDuty'),
        image: use3d ? InoHomeIcons3d.finStamp : null,
        svg: use3d ? null : InoHomeIcons.stamp,
        accent: AppColors.accentAmber,
        onTap: onOpenStampDuty,
      ),
      (
        label: l10n.t('unitConv'),
        image: use3d ? InoHomeIcons3d.finUnit : null,
        svg: use3d ? null : InoHomeIcons.unit,
        accent: AppColors.accentCyan,
        onTap: onOpenUnitConv,
      ),
      (
        label: l10n.t('taxCalc'),
        image: use3d ? InoHomeIcons3d.finTax : null,
        svg: use3d ? null : InoHomeIcons.tax,
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
