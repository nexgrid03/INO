import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/area_unit.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../services/property_valuation_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/property/area_unit_picker.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/currency_selector.dart';

/// Property Valuation Calculator - area × rate → market value, with an optional
/// purchase price to show profit / loss (appreciation). Works in any currency
/// and any supported land unit.
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
    final picked = await showAreaUnitPicker(context,
        selected: _unit, title: AppLocalizations.of(context).t('areaUnit'));
    if (picked != null) setState(() => _unit = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = Currencies.byCode(AppSettings.instance.currency.value);

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
      title: l10n.t('propertyValuation'),
      subtitle: l10n.t('valuationSubtitle'),
      trailing: CurrencySelector(onChanged: (_) => setState(() {})),
      children: [
        CalcInputCard(
          title: l10n.t('propertyDetails'),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: CalcField(
                    label: l10n.t('area'),
                    controller: _area,
                    hint: 'e.g. 312',
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: _UnitSelector(
                    unit: _unit,
                    label: l10n.t('unit'),
                    onTap: _pickUnit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: '${l10n.t('ratePer')} ${_unit.shortLabel}',
              controller: _rate,
              prefix: currency.symbol,
              hint: 'e.g. 35000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label: l10n.t('purchasePriceOptional'),
              controller: _purchase,
              prefix: currency.symbol,
              hint: 'e.g. 5000000',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          CalcHint(message: l10n.t('valuationHint'))
        else ...[
          HeroResultCard(
            label: l10n.t('marketValue'),
            value: money(marketValue.round(), currency),
            copyText: money(marketValue.round(), currency),
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                label: l10n.t('calculation'),
                value: currency.indianGrouping
                    ? '${indianGroup(area)} × ${indianGroup(rate)}'
                    : '${westernGroup(area)} × ${westernGroup(rate)}',
              ),
              ResultRow(
                  label: l10n.t('inWords'),
                  value: moneyWords(marketValue, currency)),
            ],
          ),
          if (showProfit) ...[
            const SizedBox(height: AppSpacing.md),
            _ProfitLossCard(
              isProfit: pnl.isProfit,
              title: pnl.isProfit ? l10n.t('profit') : l10n.t('loss'),
              percentLabel: pnl.isProfit
                  ? '+${pnl.percent.toStringAsFixed(1)}%'
                  : '${pnl.percent.toStringAsFixed(1)}%',
              value: money(pnl.amount.abs().round(), currency),
              copyText: money(pnl.amount.round(), currency),
            ),
            const SizedBox(height: AppSpacing.md),
            ResultBreakdownCard(
              rows: [
                ResultRow(
                    label: l10n.t('purchasePrice'),
                    value: money(purchase.round(), currency)),
                ResultRow(
                    label: l10n.t('currentValue'),
                    value: money(marketValue.round(), currency)),
                ResultRow(
                  label: pnl.isProfit ? l10n.t('profit') : l10n.t('loss'),
                  value: money(pnl.amount.round(), currency),
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

/// The profit / loss result on a white glass card: a pastel trend chip, a
/// tinted percent pill and a copy action - no saturated gradient block, per
/// the Divine Glass language (the market-value hero above stays the single
/// brand-gradient card).
class _ProfitLossCard extends StatelessWidget {
  const _ProfitLossCard({
    required this.isProfit,
    required this.title,
    required this.percentLabel,
    required this.value,
    required this.copyText,
  });

  final bool isProfit;
  final String title;
  final String percentLabel;
  final String value;
  final String copyText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = isProfit ? AppColors.positive : AppColors.negative;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.internal),
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(
                  isProfit
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppText.subtitle
                      .copyWith(color: palette.textSecondary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: accent.withValues(alpha: 0.30)),
                ),
                child: Text(
                  percentLabel,
                  style: AppText.label.copyWith(color: accent),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              PressableScale(
                pressedScale: 0.9,
                child: Material(
                  color: accent.withValues(alpha: 0.10),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => copyToClipboard(context, copyText,
                        message: '$title copied'),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(Icons.copy_rounded, color: accent, size: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.bigNumber.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({
    required this.unit,
    required this.label,
    required this.onTap,
  });

  final AreaUnit unit;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
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
