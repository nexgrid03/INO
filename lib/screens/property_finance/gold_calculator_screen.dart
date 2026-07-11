import 'package:flutter/material.dart';

import '../../services/gold_calculator_service.dart';
import '../../services/gold_price_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/property_finance/calc_widgets.dart';

/// Gold Calculator — weight + purity + live/placeholder 24K rate → current
/// value and price per gram.
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

  @override
  Widget build(BuildContext context) {
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
      title: 'Gold Calculator',
      subtitle: 'Value your gold by weight & purity',
      children: [
        CalcInputCard(
          title: 'Gold Details',
          children: [
            CalcField(
              label: 'Weight',
              controller: _weight,
              hint: 'e.g. 10',
              suffix: _unit.label.toLowerCase(),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcSegmented<GoldWeightUnit>(
              label: 'Unit',
              options: GoldWeightUnit.values,
              selected: _unit,
              labelOf: (u) => u.label,
              onChanged: (u) => setState(() => _unit = u),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcSegmented<GoldPurity>(
              label: 'Purity',
              options: GoldPurity.values,
              selected: _purity,
              labelOf: (p) => p.label,
              onChanged: (p) => setState(() => _purity = p),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: isLive
                  ? '24K Price / gram (live)'
                  : '24K Price / gram (edit to today\'s rate)',
              controller: _price,
              prefix: '₹',
              hint: 'e.g. 7350',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          const CalcHint(
              message:
                  'Enter a weight and the current 24K price to value your gold.')
        else ...[
          HeroResultCard(
            label: 'Current Gold Value (${_purity.label})',
            value: rupees(result.totalValue.round()),
            copyText: rupees(result.totalValue.round()),
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
                  label: 'Weight', value: '${_grams(result.weightInGrams)} g'),
              ResultRow(
                  label: 'Price / gram (${_purity.label})',
                  value: rupees(result.pricePerGram.round())),
              ResultRow(
                  label: 'Price / gram (24K)', value: rupees(price.round())),
            ],
          ),
        ],
      ],
    );
  }
}
