import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/dashboard_models.dart';
import '../../services/fuel_rates_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../common/shiny_icon.dart';
import '../dashboard/sparkline.dart';
import '../pressable_scale.dart';

/// Market Snapshot - Gold, Silver, Petrol & Diesel in one card.
///
/// Metals are live/fallback quotes. Petrol & diesel are optional text fields
/// the user fills when needed ([FuelRatesStore]).
class MarketCard extends StatefulWidget {
  const MarketCard({super.key, required this.quotes, this.onTap});

  final List<MarketQuote> quotes;
  final VoidCallback? onTap;

  @override
  State<MarketCard> createState() => _MarketCardState();
}

class _MarketCardState extends State<MarketCard> {
  final _fuel = FuelRatesStore.instance;
  late final TextEditingController _petrol;
  late final TextEditingController _diesel;
  final _petrolFocus = FocusNode();
  final _dieselFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _petrol = TextEditingController();
    _diesel = TextEditingController();
    _fuel.ensureLoaded().then((_) {
      if (mounted) _syncFuel();
    });
    _fuel.addListener(_syncFuel);
    _petrolFocus.addListener(() {
      if (!_petrolFocus.hasFocus) _fuel.setPetrol(_parse(_petrol.text));
    });
    _dieselFocus.addListener(() {
      if (!_dieselFocus.hasFocus) _fuel.setDiesel(_parse(_diesel.text));
    });
  }

  void _syncFuel() {
    if (!mounted) return;
    if (!_petrolFocus.hasFocus) {
      final v = _fuel.petrolPerLitre;
      final text = v == null ? '' : _fmt(v);
      if (_petrol.text != text) _petrol.text = text;
    }
    if (!_dieselFocus.hasFocus) {
      final v = _fuel.dieselPerLitre;
      final text = v == null ? '' : _fmt(v);
      if (_diesel.text != text) _diesel.text = text;
    }
    setState(() {});
  }

  static String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  static double? _parse(String raw) {
    final t = raw.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  @override
  void dispose() {
    _fuel.removeListener(_syncFuel);
    _petrol.dispose();
    _diesel.dispose();
    _petrolFocus.dispose();
    _dieselFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final quotes = widget.quotes;

    MarketQuote? goldQuote;
    MarketQuote? silverQuote;
    for (final q in quotes) {
      if (q.label.toLowerCase().contains('gold')) {
        goldQuote = q;
      } else if (q.label.toLowerCase().contains('silver')) {
        silverQuote = q;
      }
    }

    String changeOf(MarketQuote? q, String fallback) => q != null
        ? '${q.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%'
        : fallback;

    final metals = Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          decoration: BoxDecoration(
            gradient: AppGradients.wash(opacity: 0.06),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.card),
            ),
          ),
          child: Row(
            children: [
              const _LiveDot(),
              const SizedBox(width: 8),
              Text(
                'Live rates',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Text(
                'INR',
                style: TextStyle(
                  color: palette.textFaint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _MetalRow(
          name: 'Gold',
          caption: '24K fine',
          icon: Icons.diamond_rounded,
          badgeColor: AppColors.gold,
          price: goldQuote?.price ?? '₹10,250',
          change: changeOf(goldQuote, '+0.35%'),
          spark: const [10.0, 10.5, 10.3, 11.0, 11.2, 11.8, 12.0],
        ),
        Divider(color: palette.border, height: 1, indent: 18, endIndent: 18),
        _MetalRow(
          name: 'Silver',
          caption: '999 pure',
          icon: Icons.auto_awesome_rounded,
          badgeColor: AppColors.silver,
          price: silverQuote?.price ?? '₹120.50',
          change: changeOf(silverQuote, '+0.28%'),
          spark: const [8.0, 8.4, 8.2, 8.7, 8.6, 9.1, 9.4],
        ),
      ],
    );

    final fuel = Column(
      children: [
        Divider(color: palette.border, height: 1, indent: 18, endIndent: 18),
        _FuelRow(
          name: 'Petrol',
          caption: 'per litre',
          icon: Icons.local_gas_station_rounded,
          badgeColor: AppColors.primaryGreen,
          controller: _petrol,
          focusNode: _petrolFocus,
          onSubmit: (v) => _fuel.setPetrol(_parse(v)),
        ),
        Divider(color: palette.border, height: 1, indent: 18, endIndent: 18),
        _FuelRow(
          name: 'Diesel',
          caption: 'per litre',
          icon: Icons.oil_barrel_rounded,
          badgeColor: AppColors.skyBlue,
          controller: _diesel,
          focusNode: _dieselFocus,
          onSubmit: (v) => _fuel.setDiesel(_parse(v)),
        ),
      ],
    );

    final card = LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.card),
      blur: 20,
      child: Column(
        children: [
          if (widget.onTap == null)
            metals
          else
            PressableScale(
              pressedScale: 0.98,
              child: GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: metals,
              ),
            ),
          fuel,
        ],
      ),
    );

    return card;
  }
}

/// Same layout language as [_MetalRow]: shiny icon badge + name/caption, with
/// a styled ₹ input where the live price would sit.
class _FuelRow extends StatelessWidget {
  const _FuelRow({
    required this.name,
    required this.caption,
    required this.icon,
    required this.badgeColor,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final String name;
  final String caption;
  final IconData icon;
  final Color badgeColor;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fill = palette.isDark ? palette.surfaceVariant : Colors.white;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          ShinyIcon(
            icon: icon,
            color: badgeColor,
            size: 42,
            iconSize: 21,
            radius: 14,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: TextStyle(
                    color: palette.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
              onEditingComplete: () {
                onSubmit(controller.text);
                focusNode.unfocus();
              },
              onSubmitted: (v) {
                onSubmit(v);
                focusNode.unfocus();
              },
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: TextStyle(
                  color: palette.textFaint,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                isDense: true,
                filled: true,
                fillColor: fill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: badgeColor, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One metal: identity left, trend centre, price + change right.
class _MetalRow extends StatelessWidget {
  const _MetalRow({
    required this.name,
    required this.caption,
    required this.icon,
    required this.badgeColor,
    required this.price,
    required this.change,
    required this.spark,
  });

  final String name;
  final String caption;
  final IconData icon;
  final Color badgeColor;
  final String price;
  final String change;
  final List<double> spark;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isUp = !change.startsWith('-');
    final trendColor = isUp ? AppColors.positive : AppColors.negative;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          ShinyIcon(
            icon: icon,
            color: badgeColor,
            size: 42,
            iconSize: 21,
            radius: 14,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: TextStyle(
                    color: palette.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                height: 30,
                child: Sparkline(
                  values: spark,
                  color: trendColor,
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A softly pulsing teal dot - the "live" affordance in the card header.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.45,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.45),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
