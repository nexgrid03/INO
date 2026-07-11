import 'package:flutter/material.dart';

import '../../services/emi_calculator_service.dart';
import '../../theme/app_dimens.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/property_finance/calc_widgets.dart';

/// EMI Calculator — loan amount + interest + tenure → monthly EMI, total
/// interest and total payment.
class EmiCalculatorScreen extends StatefulWidget {
  const EmiCalculatorScreen({super.key});

  @override
  State<EmiCalculatorScreen> createState() => _EmiCalculatorScreenState();
}

class _EmiCalculatorScreenState extends State<EmiCalculatorScreen> {
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _years = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _years.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final principal = _num(_amount);
    final rate = _num(_rate);
    final years = _num(_years);
    final months = (years * 12).round();
    final valid = principal > 0 && months > 0;

    final result = valid
        ? EmiCalculatorService.instance.calculate(
            principal: principal,
            annualRatePercent: rate,
            months: months,
          )
        : EmiResult.zero;

    return CalculatorScaffold(
      title: 'EMI Calculator',
      subtitle: 'Loan repayment breakdown',
      children: [
        CalcInputCard(
          title: 'Loan Details',
          children: [
            CalcField(
              label: 'Loan Amount',
              controller: _amount,
              prefix: '₹',
              hint: 'e.g. 5000000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: 'Interest Rate (% per year)',
              controller: _rate,
              suffix: '%',
              hint: 'e.g. 8.5',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: 'Loan Tenure (Years)',
              controller: _years,
              suffix: 'yrs',
              hint: 'e.g. 20',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          const CalcHint(
              message:
                  'Enter a loan amount and tenure to see your monthly EMI.')
        else ...[
          HeroResultCard(
            label: 'Monthly EMI',
            value: rupees(result.emi.round()),
            copyText: rupees(result.emi.round()),
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                  label: 'Principal', value: rupees(result.principal.round())),
              ResultRow(
                  label: 'Total Interest',
                  value: rupees(result.totalInterest.round())),
              ResultRow(
                  label: 'Total Payment',
                  value: rupees(result.totalPayment.round())),
            ],
          ),
        ],
      ],
    );
  }
}
