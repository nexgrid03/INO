import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../services/sip_calculator_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/currency_selector.dart';

/// SIP Calculator - monthly investment + return + years → invested amount,
/// estimated returns and future value. Works in any currency (header pill).
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
    final l10n = AppLocalizations.of(context);
    final currency = Currencies.byCode(AppSettings.instance.currency.value);

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
      title: l10n.t('sipCalculator'),
      subtitle: l10n.t('sipSubtitle'),
      trailing: CurrencySelector(onChanged: (_) => setState(() {})),
      children: [
        CalcInputCard(
          title: l10n.t('investmentDetails'),
          children: [
            CalcField(
              label: l10n.t('monthlyInvestment'),
              controller: _monthly,
              prefix: currency.symbol,
              hint: 'e.g. 10000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: l10n.t('expectedReturnPerYear'),
              controller: _return,
              suffix: '%',
              hint: 'e.g. 12',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: l10n.t('timePeriodYears'),
              controller: _years,
              hint: 'e.g. 10',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          CalcHint(message: l10n.t('sipHint'))
        else ...[
          HeroResultCard(
            label: l10n.t('futureValue'),
            value: money(result.futureValue.round(), currency),
            copyText: money(result.futureValue.round(), currency),
            gradient: AppColors.insightGradient,
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                  label: l10n.t('investedAmount'),
                  value: money(result.investedAmount.round(), currency)),
              ResultRow(
                label: l10n.t('estimatedReturns'),
                value: money(result.estimatedReturns.round(), currency),
                valueColor: AppColors.primaryGreen,
              ),
              ResultRow(
                  label: l10n.t('totalValue'),
                  value: money(result.futureValue.round(), currency)),
            ],
          ),
        ],
      ],
    );
  }
}
