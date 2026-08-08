import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/responsive/responsive_metric_text.dart';
import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../services/sip_calculator_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/divine_glass/divine_glass.dart';
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
          _EstimatedWealthCard(
            totalLabel: l10n.t('totalValue'),
            totalValue: money(result.futureValue.round(), currency),
            investedLabel: l10n.t('investedAmount'),
            returnsLabel: l10n.t('estimatedReturns'),
            investedFraction: result.futureValue > 0
                ? (result.investedAmount / result.futureValue).clamp(0.0, 1.0)
                : 0.0,
          ),
          const SizedBox(height: AppSpacing.md),
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

/// Divine Glass "Estimated Wealth" card - a donut of invested vs. returns with
/// the total value in the centre and a two-dot legend. Purely a visual
/// presentation of the already-computed SIP result.
class _EstimatedWealthCard extends StatelessWidget {
  const _EstimatedWealthCard({
    required this.totalLabel,
    required this.totalValue,
    required this.investedLabel,
    required this.returnsLabel,
    required this.investedFraction,
  });

  final String totalLabel;
  final String totalValue;
  final String investedLabel;
  final String returnsLabel;
  final double investedFraction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AdaptiveGlassCard(
      padding: const EdgeInsets.all(AppSpacing.internal),
      radius: AppRadius.card,
      child: Column(
        children: [
          Text(
            'ESTIMATED WEALTH',
            style: AppText.label.copyWith(
              color: palette.textSecondary,
              letterSpacing: 1.4,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 176,
            height: 176,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WealthDonutPainter(
                      investedFraction: investedFraction,
                      trackColor: palette.surfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        totalLabel,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      ResponsiveMetricText(
                        totalValue,
                        textAlign: TextAlign.center,
                        style: AppText.title.copyWith(
                          color: palette.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LegendDot(color: AppColors.primaryGreen, label: investedLabel),
              _LegendDot(color: AppColors.warning, label: returnsLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: AppText.caption.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _WealthDonutPainter extends CustomPainter {
  _WealthDonutPainter({
    required this.investedFraction,
    required this.trackColor,
  });

  /// Share of the total value that is invested capital (0..1); the remainder
  /// is estimated returns.
  final double investedFraction;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 20.0;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint arcPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Faint full track underneath, so hairline gaps never show through.
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      arcPaint(trackColor)..strokeCap = StrokeCap.butt,
    );

    const start = -math.pi / 2;
    final investedSweep = math.pi * 2 * investedFraction;
    final returnsSweep = math.pi * 2 - investedSweep;
    if (returnsSweep > 0.01) {
      canvas.drawArc(
        rect,
        start + investedSweep,
        returnsSweep,
        false,
        arcPaint(AppColors.warning),
      );
    }
    if (investedSweep > 0.01) {
      canvas.drawArc(
        rect,
        start,
        investedSweep,
        false,
        arcPaint(AppColors.primaryGreen),
      );
    }
  }

  @override
  bool shouldRepaint(_WealthDonutPainter old) =>
      old.investedFraction != investedFraction || old.trackColor != trackColor;
}
