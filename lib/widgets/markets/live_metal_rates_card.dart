import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/metal_rates_provider.dart';
import '../../services/fuel_rates_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';

/// Live Gold & Silver rates plus user-entered Petrol & Diesel (₹/litre).
///
/// Metals come from [MetalRatesProvider]. Fuel is typed in when needed and
/// persisted on-device via [FuelRatesStore].
class LiveMetalRatesCard extends StatefulWidget {
  const LiveMetalRatesCard({super.key});

  @override
  State<LiveMetalRatesCard> createState() => _LiveMetalRatesCardState();
}

class _LiveMetalRatesCardState extends State<LiveMetalRatesCard>
    with SingleTickerProviderStateMixin {
  final MetalRatesProvider _provider = MetalRatesProvider.instance;
  final FuelRatesStore _fuel = FuelRatesStore.instance;

  late final TextEditingController _petrol;
  late final TextEditingController _diesel;
  final _petrolFocus = FocusNode();
  final _dieselFocus = FocusNode();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _petrol = TextEditingController();
    _diesel = TextEditingController();
    _provider.ensureStarted();
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
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        final p = _provider;
        return InoCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, p),
              const SizedBox(height: AppSpacing.md),
              _body(context, p),
              const SizedBox(height: AppSpacing.md),
              _fuelSection(context),
            ],
          ),
        );
      },
    );
  }

  Widget _fuelSection(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
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
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _FuelTile(
            name: 'Diesel',
            subtitle: '₹/L',
            icon: Icons.oil_barrel_rounded,
            color: AppColors.skyBlue,
            controller: _diesel,
            focusNode: _dieselFocus,
            onSubmit: (v) => _fuel.setDiesel(_parseFuel(v)),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, MetalRatesProvider p) {
    final palette = AppPalette.of(context);
    final offline = p.isOffline;
    return Row(
      children: [
        offline ? _offlineBadge() : _liveBadge(),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Market rates',
            style: AppText.subtitle.copyWith(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _RefreshButton(
          spinning: p.isRefreshing,
          onTap: () => p.refresh(force: true),
        ),
      ],
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: AppText.label.copyWith(
              color: AppColors.success,
              fontSize: 10.5,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 12,
            color: AppColors.warning,
          ),
          const SizedBox(width: 5),
          Text(
            'OFFLINE',
            style: AppText.label.copyWith(
              color: AppColors.warning,
              fontSize: 10.5,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, MetalRatesProvider p) {
    if (!p.hasData && p.status == MetalRatesStatus.loading) {
      return _loading(context);
    }
    if (!p.hasData && p.status == MetalRatesStatus.error) {
      return _errorState(context, p);
    }

    final rates = p.rates;
    if (rates == null) return _loading(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetalTile(
                name: 'Gold',
                subtitle: '24K',
                icon: Icons.circle,
                color: AppColors.gold,
                priceText: _inr(rates.goldPerGram),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetalTile(
                name: 'Silver',
                subtitle: 'Fine',
                icon: Icons.circle,
                color: AppColors.silver,
                priceText: _inr(rates.silverPerGram),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _footer(context, p),
      ],
    );
  }

  Widget _footer(BuildContext context, MetalRatesProvider p) {
    final palette = AppPalette.of(context);
    final updated = p.lastUpdated;
    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: 13,
          color: palette.textFaint,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            updated == null
                ? 'Updating…'
                : 'Last updated ${_fmtTime(updated)}'
                      '${p.isOffline ? ' · showing last known' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _loading(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(child: _ShimmerTile(pulse: _pulse)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _ShimmerTile(pulse: _pulse)),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.primaryGreen,
            backgroundColor: palette.surfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _errorState(BuildContext context, MetalRatesProvider p) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 20,
          color: AppColors.critical,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            p.error ?? 'Could not load rates',
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PressableScale(
          pressedScale: 0.94,
          child: GestureDetector(
            onTap: () => p.refresh(force: true),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Text(
                'Retry',
                style: AppText.label.copyWith(
                  color: AppColors.primaryGreen,
                  fontSize: 12.5,
                ),
              ),
            ),
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

  static String _fmtTime(DateTime dt) {
    final h24 = dt.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = h24 < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
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
    // Same chrome as [_MetalTile] — icon + name + subtitle, then a styled
    // input where the live price would sit.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
      ),
      child: Column(
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
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
      ),
      child: Column(
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
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.spinning, required this.onTap});

  final bool spinning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.88,
      child: Material(
        color: palette.surfaceVariant,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: spinning ? null : onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: spinning
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primaryGreen,
                    ),
                  )
                : Icon(
                    Icons.refresh_rounded,
                    size: 19,
                    color: AppColors.primaryGreen,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  const _ShimmerTile({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(pulse),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: palette.border),
        ),
      ),
    );
  }
}
