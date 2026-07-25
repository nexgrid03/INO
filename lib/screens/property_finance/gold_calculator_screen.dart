import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../services/gold_calculator_service.dart';
import '../../services/gold_price_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/currency_selector.dart';

/// Gold Calculator - weight + purity + live/placeholder 24K rate → current
/// value and price per gram. Works in any currency and every common gold
/// weight unit (grams / kg / tola / sovereign / troy ounce).
class GoldCalculatorScreen extends StatefulWidget {
  const GoldCalculatorScreen({super.key});

  @override
  State<GoldCalculatorScreen> createState() => _GoldCalculatorScreenState();
}

class _GoldCalculatorScreenState extends State<GoldCalculatorScreen> {
  final _weight = TextEditingController();
  late final TextEditingController _price = TextEditingController(
    text: GoldPriceService.instance.current.pricePerGram24k
        .toStringAsFixed(0),
  );

  GoldWeightUnit _unit = GoldWeightUnit.grams;
  GoldPurity _purity = GoldPurity.k22;

  @override
  void dispose() {
    _weight.dispose();
    _price.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  static String _grams(double g) {
    final s = g.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  String _unitLabel(AppLocalizations l10n, GoldWeightUnit u) =>
      switch (u) {
        GoldWeightUnit.grams => l10n.t('unitGrams'),
        GoldWeightUnit.kilograms => l10n.t('unitKilograms'),
        GoldWeightUnit.tola => l10n.t('unitTola'),
        GoldWeightUnit.sovereign => l10n.t('unitSovereign'),
        GoldWeightUnit.ounce => l10n.t('unitOunce'),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = Currencies.byCode(AppSettings.instance.currency.value);

    final weight = _num(_weight);
    final price = _num(_price);
    final valid = weight > 0 && price > 0;
    final isLive = GoldPriceService.instance.current.isLive;

    final result = valid
        ? GoldCalculatorService.instance.calculate(
            weight: weight,
            unit: _unit,
            purity: _purity,
            pricePerGram24k: price,
          )
        : GoldValue.zero;

    return CalculatorScaffold(
      title: l10n.t('goldCalculator'),
      subtitle: l10n.t('goldSubtitle'),
      trailing: CurrencySelector(onChanged: (_) => setState(() {})),
      children: [
        CalcInputCard(
          title: l10n.t('goldDetails'),
          children: [
            CalcField(
              label: l10n.t('weight'),
              controller: _weight,
              hint: 'e.g. 10',
              suffix: _unitLabel(l10n, _unit).toLowerCase(),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcSegmented<GoldWeightUnit>(
              label: l10n.t('unit'),
              options: GoldWeightUnit.values,
              selected: _unit,
              labelOf: (u) => _unitLabel(l10n, u),
              onChanged: (u) => setState(() => _unit = u),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcSegmented<GoldPurity>(
              label: l10n.t('purity'),
              options: GoldPurity.values,
              selected: _purity,
              labelOf: (p) => p.label,
              onChanged: (p) => setState(() => _purity = p),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: isLive ? l10n.t('goldPriceLive') : l10n.t('goldPriceEdit'),
              controller: _price,
              prefix: currency.symbol,
              hint: 'e.g. 7350',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          CalcHint(message: l10n.t('goldHint'))
        else ...[
          HeroResultCard(
            label: '${l10n.t('currentGoldValue')} (${_purity.label})',
            value: money(result.totalValue.round(), currency),
            copyText: money(result.totalValue.round(), currency),
            gradient: const LinearGradient(
              colors: [AppColors.gold, Color(0xFFF5C542)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                  label: l10n.t('weight'),
                  value: '${_grams(result.weightInGrams)} g'),
              ResultRow(
                  label: '${l10n.t('pricePerGram')} (${_purity.label})',
                  value: money(result.pricePerGram.round(), currency)),
              ResultRow(
                  label: '${l10n.t('pricePerGram')} (24K)',
                  value: money(price.round(), currency)),
            ],
          ),
        ],
      ],
    );
  }
}
