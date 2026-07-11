import 'package:flutter/material.dart';

import '../../models/area_unit.dart';
import '../../services/property_valuation_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/property/area_unit_picker.dart';
import '../../widgets/property_finance/calc_widgets.dart';

/// Property Valuation Calculator — area × rate → market value, with an optional
/// purchase price to show profit / loss (appreciation).
class PropertyValuationScreen extends StatefulWidget {
  const PropertyValuationScreen({super.key});

  @override
  State<PropertyValuationScreen> createState() =>
      _PropertyValuationScreenState();
}

class _PropertyValuationScreenState extends State<PropertyValuationScreen> {
  final _area = TextEditingController();
  final _rate = TextEditingController();
  final _purchase = TextEditingController();
  AreaUnit _unit = AreaUnit.squareYards;

  static const _svc = PropertyValuationService.instance;

  @override
  void dispose() {
    _area.dispose();
    _rate.dispose();
    _purchase.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _pickUnit() async {
    final picked =
        await showAreaUnitPicker(context, selected: _unit, title: 'Area Unit');
    if (picked != null) setState(() => _unit = picked);
  }

  @override
  Widget build(BuildContext context) {
    final area = _num(_area);
    final rate = _num(_rate);
    final purchase = _num(_purchase);
    final valid = area > 0 && rate > 0;
    final marketValue = _svc.marketValue(area: area, ratePerUnit: rate);
    final showProfit = valid && purchase > 0;
    final pnl = showProfit
        ? _svc.profitLoss(purchasePrice: purchase, currentValue: marketValue)
        : ProfitLoss.zero;

    return CalculatorScaffold(
      title: 'Property Valuation',
      subtitle: 'Estimate market value & appreciation',
      children: [
        CalcInputCard(
          title: 'Property Details',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: CalcField(
                    label: 'Area',
                    controller: _area,
                    hint: 'e.g. 312',
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: _UnitSelector(unit: _unit, onTap: _pickUnit),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: 'Rate per ${_unit.shortLabel}',
              controller: _rate,
              prefix: '₹',
              hint: 'e.g. 35000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: 'Purchase Price (optional — for profit/loss)',
              controller: _purchase,
              prefix: '₹',
              hint: 'e.g. 5000000',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          const CalcHint(
              message:
                  'Enter the area and rate per unit to estimate the property value.')
        else ...[
          HeroResultCard(
            label: 'Market Value',
            value: rupees(marketValue.round()),
            copyText: rupees(marketValue.round()),
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                label: 'Calculation',
                value:
                    '${indianGroup(area)} × ${indianGroup(rate)}',
              ),
              ResultRow(
                  label: 'In words', value: rupeesWords(marketValue)),
            ],
          ),
          if (showProfit) ...[
            const SizedBox(height: AppSpacing.md),
            HeroResultCard(
              label: pnl.isProfit
                  ? 'Profit  (+${pnl.percent.toStringAsFixed(1)}%)'
                  : 'Loss  (${pnl.percent.toStringAsFixed(1)}%)',
              value: rupees(pnl.amount.abs().round()),
              copyText: rupees(pnl.amount.round()),
              gradient: LinearGradient(
                colors: pnl.isProfit
                    ? const [AppColors.primaryGreen, AppColors.secondaryGreen]
                    : const [AppColors.critical, Color(0xFFF08A5D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ResultBreakdownCard(
              rows: [
                ResultRow(
                    label: 'Purchase Price',
                    value: rupees(purchase.round())),
                ResultRow(
                    label: 'Current Value',
                    value: rupees(marketValue.round())),
                ResultRow(
                  label: pnl.isProfit ? 'Profit' : 'Loss',
                  value: rupees(pnl.amount.round()),
                  valueColor: pnl.isProfit
                      ? AppColors.primaryGreen
                      : AppColors.critical,
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({required this.unit, required this.onTap});

  final AreaUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unit',
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11.5)),
        const SizedBox(height: 6),
        PressableScale(
          pressedScale: 0.98,
          child: Material(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        unit.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: palette.textFaint),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
