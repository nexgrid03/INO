import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../services/emi_calculator_service.dart';
import '../../theme/app_dimens.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/currency_selector.dart';

/// How the loan tenure is entered.
enum _TenureUnit { years, months }

/// EMI Calculator - loan amount + interest + tenure → monthly EMI, total
/// interest and total payment. Works in any currency (header pill).
class EmiCalculatorScreen extends StatefulWidget {
  const EmiCalculatorScreen({super.key});

  @override
  State<EmiCalculatorScreen> createState() => _EmiCalculatorScreenState();
}

class _EmiCalculatorScreenState extends State<EmiCalculatorScreen> {
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _tenure = TextEditingController();
  _TenureUnit _tenureUnit = _TenureUnit.years;

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _tenure.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = Currencies.byCode(AppSettings.instance.currency.value);

    final principal = _num(_amount);
    final rate = _num(_rate);
    final tenure = _num(_tenure);
    final months = _tenureUnit == _TenureUnit.years
        ? (tenure * 12).round()
        : tenure.round();
    final valid = principal > 0 && months > 0;

    final result = valid
        ? EmiCalculatorService.instance.calculate(
            principal: principal,
            annualRatePercent: rate,
            months: months,
          )
        : EmiResult.zero;

    return CalculatorScaffold(
      title: l10n.t('emiCalculator'),
      subtitle: l10n.t('emiSubtitle'),
      trailing: CurrencySelector(onChanged: (_) => setState(() {})),
      children: [
        CalcInputCard(
          title: l10n.t('loanDetails'),
          children: [
            CalcField(
              label: l10n.t('loanAmount'),
              controller: _amount,
              prefix: currency.symbol,
              hint: 'e.g. 5000000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: l10n.t('interestRatePerYear'),
              controller: _rate,
              suffix: '%',
              hint: 'e.g. 8.5',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: l10n.t('loanTenure'),
              controller: _tenure,
              hint: _tenureUnit == _TenureUnit.years ? 'e.g. 20' : 'e.g. 240',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcSegmented<_TenureUnit>(
              label: l10n.t('unit'),
              options: _TenureUnit.values,
              selected: _tenureUnit,
              labelOf: (u) => u == _TenureUnit.years
                  ? l10n.t('years')
                  : l10n.t('months'),
              onChanged: (u) => setState(() => _tenureUnit = u),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          CalcHint(message: l10n.t('emiHint'))
        else ...[
          HeroResultCard(
            label: l10n.t('monthlyEmi'),
            value: money(result.emi.round(), currency),
            copyText: money(result.emi.round(), currency),
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                  label: l10n.t('principal'),
                  value: money(result.principal.round(), currency)),
              ResultRow(
                  label: l10n.t('totalInterest'),
                  value: money(result.totalInterest.round(), currency)),
              ResultRow(
                  label: l10n.t('totalPayment'),
                  value: money(result.totalPayment.round(), currency)),
            ],
          ),
        ],
      ],
    );
  }
}
