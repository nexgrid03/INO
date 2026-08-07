import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/fuel_rates_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Markets rates UI: Gold & Silver price cards + Petrol & Diesel inputs.
///
/// Metals are display-only card UI (no live fetch required). Fuel rates are
/// typed in and persisted via [FuelRatesStore].
class LiveMetalRatesCard extends StatefulWidget {
  const LiveMetalRatesCard({super.key});

  @override
  State<LiveMetalRatesCard> createState() => _LiveMetalRatesCardState();
}

class _LiveMetalRatesCardState extends State<LiveMetalRatesCard> {
  final FuelRatesStore _fuel = FuelRatesStore.instance;

  late final TextEditingController _petrol;
  late final TextEditingController _diesel;
  final _petrolFocus = FocusNode();
  final _dieselFocus = FocusNode();

  /// Indicative display prices for the card UI (₹/gram).
  static const _goldPerGram = 10250.0;
  static const _silverPerGram = 128.0;

  @override
  void initState() {
    super.initState();
    _petrol = TextEditingController();
    _diesel = TextEditingController();
    _fuel.ensureLoaded().then((_) {
      if (mounted) _syncFuelFields();
    });
    _fuel.addListener(_syncFuelFields);
    _petrolFocus.addListener(() {
      if (!_petrolFocus.hasFocus) _fuel.setPetrol(_parseFuel(_petrol.text));
    });
    _dieselFocus.addListener(() {
      if (!_dieselFocus.hasFocus) _fuel.setDiesel(_parseFuel(_diesel.text));
    });
  }

  void _syncFuelFields() {
    if (!mounted) return;
    if (!_petrolFocus.hasFocus) {
      final v = _fuel.petrolPerLitre;
      final text = v == null ? '' : _fmtFuel(v);
      if (_petrol.text != text) _petrol.text = text;
    }
    if (!_dieselFocus.hasFocus) {
      final v = _fuel.dieselPerLitre;
      final text = v == null ? '' : _fmtFuel(v);
      if (_diesel.text != text) _diesel.text = text;
    }
    setState(() {});
  }

  static String _fmtFuel(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  static double? _parseFuel(String raw) {
    final t = raw.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  @override
  void dispose() {
    _fuel.removeListener(_syncFuelFields);
    _petrol.dispose();
    _diesel.dispose();
    _petrolFocus.dispose();
    _dieselFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // No full-bleed glass panel — sky shows through; each rate is its own card.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Market rates',
          style: AppText.subtitle.copyWith(
            color: palette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InoCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: _MetalTile(
            name: 'Gold',
            subtitle: '24K',
            icon: Icons.circle,
            color: AppColors.gold,
            priceText: _inr(_goldPerGram),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        InoCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: _MetalTile(
            name: 'Silver',
            subtitle: 'Fine',
            icon: Icons.circle,
            color: AppColors.silver,
            priceText: _inr(_silverPerGram),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        InoCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: _FuelTile(
            name: 'Petrol',
            subtitle: '₹/L',
            icon: Icons.local_gas_station_rounded,
            color: AppColors.primaryGreen,
            controller: _petrol,
            focusNode: _petrolFocus,
            onSubmit: (v) => _fuel.setPetrol(_parseFuel(v)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        InoCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: _FuelTile(
            name: 'Diesel',
            subtitle: '₹/L',
            icon: Icons.oil_barrel_rounded,
            color: AppColors.primaryGreen,
            controller: _diesel,
            focusNode: _dieselFocus,
            onSubmit: (v) => _fuel.setDiesel(_parseFuel(v)),
          ),
        ),
      ],
    );
  }

  static String _inr(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final whole = fixed.substring(0, dot);
    final frac = fixed.substring(dot + 1);
    return '₹${_indianGroup(whole)}.$frac';
  }

  static String _indianGroup(String s) {
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var head = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (head.length > 2) {
      groups.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) groups.insert(0, head);
    return '${groups.join(',')},$last3';
  }
}

class _FuelTile extends StatelessWidget {
  const _FuelTile({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fill = palette.isDark ? palette.surface : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 12, color: color),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              subtitle,
              style: AppText.label.copyWith(
                color: palette.textFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: AppText.headline.copyWith(
            color: palette.textPrimary,
            fontSize: 18,
            letterSpacing: -0.3,
            fontWeight: FontWeight.w800,
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
            hintStyle: AppText.headline.copyWith(
              color: palette.textFaint,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            prefixText: '₹ ',
            prefixStyle: AppText.subtitle.copyWith(
              color: palette.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            isDense: true,
            filled: true,
            fillColor: fill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'per litre',
          style: AppText.caption.copyWith(
            color: palette.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _MetalTile extends StatelessWidget {
  const _MetalTile({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.priceText,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String priceText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 11, color: color),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              style: AppText.subtitle.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              subtitle,
              style: AppText.label.copyWith(
                color: palette.textFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            priceText,
            style: AppText.headline.copyWith(
              color: palette.textPrimary,
              fontSize: 20,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'per gram',
          style: AppText.caption.copyWith(
            color: palette.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
