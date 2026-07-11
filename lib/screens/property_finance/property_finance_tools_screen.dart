import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/tool_card.dart';
import 'finance_tools.dart';

/// The Property & Finance Tools hub — a premium 2-column grid of every
/// calculator/utility, driven entirely by the [financeTools] registry.
class PropertyFinanceToolsScreen extends StatelessWidget {
  const PropertyFinanceToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CalculatorScaffold(
      title: 'Property & Finance Tools',
      subtitle: 'Smart tools for property & wealth calculations',
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
                        title: financeTools[i].title,
                        subtitle: financeTools[i].subtitle,
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
