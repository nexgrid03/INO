import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/tool_card.dart';
import 'finance_tools.dart';

/// The Property & Finance Tools hub - a premium 2-column grid of every
/// calculator/utility, driven entirely by the [financeTools] registry.
class PropertyFinanceToolsScreen extends StatelessWidget {
  const PropertyFinanceToolsScreen({super.key});

  /// The registry stores English strings (it's built without a context);
  /// resolve each tool's title/subtitle through l10n by id, falling back to
  /// the registry text for any future tool without translations yet.
  static String _title(AppLocalizations l10n, FinanceTool t) => switch (t.id) {
        'area' => l10n.t('areaConverter'),
        'valuation' => l10n.t('propertyValuation'),
        'emi' => l10n.t('emiCalculator'),
        'sip' => l10n.t('sipCalculator'),
        'gold' => l10n.t('goldCalculator'),
        _ => t.title,
      };

  static String _subtitle(AppLocalizations l10n, FinanceTool t) =>
      switch (t.id) {
        'area' => l10n.t('areaConverterSubtitle'),
        'valuation' => l10n.t('valuationSubtitle'),
        'emi' => l10n.t('emiSubtitle'),
        'sip' => l10n.t('sipSubtitle'),
        'gold' => l10n.t('goldSubtitle'),
        _ => t.subtitle,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold(
      title: l10n.t('propertyFinanceTools'),
      subtitle: l10n.t('financeToolsSubtitle'),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppSpacing.sm;
            final cardWidth = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < financeTools.length; i++)
                  SizedBox(
                    width: cardWidth,
                    height: 158,
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: (i * 60).clamp(0, 300)),
                      child: ToolGridCard(
                        icon: financeTools[i].icon,
                        title: _title(l10n, financeTools[i]),
                        subtitle: _subtitle(l10n, financeTools[i]),
                        color: financeTools[i].color,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: financeTools[i].builder),
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
