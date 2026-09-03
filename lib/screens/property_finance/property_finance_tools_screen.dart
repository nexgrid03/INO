import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/theme_style.dart';
import '../../widgets/common/ino_svg_icon.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/tool_card.dart';
import 'finance_tools.dart';

/// The Property & Finance Tools hub - one full-width row per tool on phones,
/// two columns on tablet+, driven entirely by the [financeTools] registry.
class PropertyFinanceToolsScreen extends StatelessWidget {
  const PropertyFinanceToolsScreen({super.key});

  /// The registry stores English strings (it's built without a context);
  /// resolve each tool's title/subtitle through l10n by id, falling back to
  /// the registry text for any future tool without translations yet.
  static String titleOf(AppLocalizations l10n, FinanceTool t) => switch (t.id) {
        'area' => l10n.t('areaConverter'),
        'valuation' => l10n.t('propertyValuation'),
        'emi' => l10n.t('emiCalculator'),
        'sip' => l10n.t('sipCalculator'),
        'gold' => l10n.t('goldCalculator'),
        'fx' => l10n.t('currencyCalculator'),
        'tax' => l10n.t('taxCalc'),
        'stamp' => l10n.t('stampDuty'),
        _ => t.title,
      };

  static String subtitleOf(AppLocalizations l10n, FinanceTool t) =>
      switch (t.id) {
        'area' => l10n.t('areaConverterSubtitle'),
        'valuation' => l10n.t('valuationSubtitle'),
        'emi' => l10n.t('emiSubtitle'),
        'sip' => l10n.t('sipSubtitle'),
        'gold' => l10n.t('goldSubtitle'),
        'fx' => l10n.t('currencySubtitle'),
        'stamp' => l10n.t('stampDutySubtitle'),
        'tax' => l10n.t('taxCalcSubtitle'),
        _ => t.subtitle,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final use3d = InoStyle.usesHome3dIcons(context);
    return CalculatorScaffold(
      title: l10n.t('propertyFinanceTools'),
      subtitle: l10n.t('financeToolsSubtitle'),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const gap = AppSpacing.sm;
            final cols = ScreenBreakpoints.getFinanceHubColumns(width);
            final cardWidth = ResponsiveGridTile.tileWidth(
              availableWidth: width,
              columns: cols,
              gap: gap,
            );
            final rowHeight = ScreenBreakpoints.getFinanceHubRowHeight(width);

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < financeTools.length; i++)
                  ResponsiveGridTile(
                    width: cardWidth,
                    minHeight: rowHeight,
                    height: rowHeight,
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: (i * 60).clamp(0, 300)),
                      child: ToolGridCard(
                        icon: financeTools[i].icon,
                        imageAsset: use3d
                            ? InoHomeIcons3d.financeGlyph(financeTools[i].id)
                            : null,
                        svgAsset: use3d
                            ? null
                            : InoHomeIcons.financeSvg(financeTools[i].id),
                        title: titleOf(l10n, financeTools[i]),
                        subtitle: subtitleOf(l10n, financeTools[i]),
                        color: financeTools[i].color,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: financeTools[i].builder,
                          ),
                        ),
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
