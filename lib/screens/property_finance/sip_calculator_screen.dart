import 'package:flutter/material.dart';

import '../../services/sip_calculator_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/property_finance/calc_widgets.dart';

/// SIP Calculator — monthly investment + return + years → invested amount,
/// estimated returns and future value.
class SipCalculatorScreen extends StatefulWidget {
  const SipCalculatorScreen({super.key});

  @override
  State<SipCalculatorScreen> createState() => _SipCalculatorScreenState();
}

class _SipCalculatorScreenState extends State<SipCalculatorScreen> {
  final _monthly = TextEditingController();
  final _return = TextEditingController();
  final _years = TextEditingController();

  @override
  void dispose() {
    _monthly.dispose();
    _return.dispose();
    _years.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final monthly = _num(_monthly);
    final ret = _num(_return);
    final years = _num(_years).round();
    final valid = monthly > 0 && years > 0;

    final result = valid
        ? SipCalculatorService.instance.calculate(
            monthlyInvestment: monthly,
            annualReturnPercent: ret,
            years: years,
          )
        : SipResult.zero;

    return CalculatorScaffold(
      title: 'SIP Calculator',
      subtitle: 'Project your mutual-fund growth',
      children: [
        CalcInputCard(
          title: 'Investment Details',
          children: [
            CalcField(
              label: 'Monthly Investment',
              controller: _monthly,
              prefix: '₹',
              hint: 'e.g. 10000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: 'Expected Return (% per year)',
              controller: _return,
              suffix: '%',
              hint: 'e.g. 12',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: 'Time Period (Years)',
              controller: _years,
              suffix: 'yrs',
              hint: 'e.g. 10',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          const CalcHint(
              message:
                  'Enter a monthly amount and duration to project your returns.')
        else ...[
          HeroResultCard(
            label: 'Future Value',
            value: rupees(result.futureValue.round()),
            copyText: rupees(result.futureValue.round()),
            gradient: AppColors.insightGradient,
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                  label: 'Invested Amount',
                  value: rupees(result.investedAmount.round())),
              ResultRow(
                label: 'Estimated Returns',
                value: rupees(result.estimatedReturns.round()),
                valueColor: AppColors.primaryGreen,
              ),
              ResultRow(
                  label: 'Total Value',
                  value: rupees(result.futureValue.round())),
            ],
          ),
        ],
      ],
    );
  }
}
