import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/property_finance/finance_tools.dart';
import '../../screens/property_finance/property_finance_tools_screen.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import 'launcher_glass_icon_tile.dart';

/// Property & Finance Tools grid for Divine Glass Home.
class LauncherFinanceTools extends StatelessWidget {
  const LauncherFinanceTools({super.key});

  static const double _gap = 10;

  static String? _svgPath(String id) => switch (id) {
        'area' => InoHomeIcons.area,
        'emi' => InoHomeIcons.emi,
        'sip' => InoHomeIcons.sip,
        'valuation' => InoHomeIcons.stamp,
        'gold' => InoHomeIcons.tax,
        'fx' => InoHomeIcons.unit,
        'stamp' => InoHomeIcons.stamp,
        'tax' => InoHomeIcons.tax,
        _ => null,
      };

  static String? _imagePath(String id) => switch (id) {
        'area' => InoHomeIcons3d.finArea,
        'emi' => InoHomeIcons3d.finEmi,
        'sip' => InoHomeIcons3d.finSip,
        'valuation' => InoHomeIcons3d.finStamp,
        'gold' => InoHomeIcons3d.finTax,
        'fx' => InoHomeIcons3d.finUnit,
        'stamp' => InoHomeIcons3d.finStamp,
        'tax' => InoHomeIcons3d.finTax,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final use3d = InoStyle.usesHome3dIcons(context);

    final tools = financeTools.take(6).map((tool) {
      return (
        label: PropertyFinanceToolsScreen.titleOf(l10n, tool),
        image: use3d ? _imagePath(tool.id) : null,
        svg: use3d ? null : _svgPath(tool.id),
        accent: tool.color,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: tool.builder),
        ),
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Always 3-across on phones (2×3 grid of 6 tools).
        final perRow = context.isTablet ? context.toolsColumns.clamp(3, 6) : 3;
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
