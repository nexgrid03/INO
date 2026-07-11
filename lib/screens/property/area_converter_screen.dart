import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/area_unit.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/property/area_conversion_summary.dart';
import '../../widgets/property/area_quick_converter.dart';
import '../../widgets/property/area_unit_picker.dart';

/// Property Area Converter & Land Calculator.
///
/// Enter a property area (value + unit) to see it converted into every common
/// Indian land unit (with a Copy All), plus a standalone quick From→To
/// converter. Purely a calculator tool — it reads/writes no documents, so it
/// can't affect existing property data.
class AreaConverterScreen extends StatefulWidget {
  const AreaConverterScreen({
    super.key,
    this.initialValue,
    this.initialUnit = AreaUnit.squareYards,
  });

  /// Optionally pre-fill the area (e.g. launched with a known plot size).
  final double? initialValue;
  final AreaUnit initialUnit;

  @override
  State<AreaConverterScreen> createState() => _AreaConverterScreenState();
}

class _AreaConverterScreenState extends State<AreaConverterScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue == null ? '' : _trim(widget.initialValue!),
  );
  late AreaUnit _unit = widget.initialUnit;

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_controller.text.trim()) ?? 0;

  Future<void> _pickUnit() async {
    final picked = await showAreaUnitPicker(context,
        selected: _unit, title: 'Area Unit');
    if (picked != null) setState(() => _unit = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final value = _value;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                    AppSpacing.screen, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AreaInputCard(
                      controller: _controller,
                      unit: _unit,
                      onChanged: () => setState(() {}),
                      onPickUnit: _pickUnit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (value > 0)
                      AreaConversionSummary(value: value, fromUnit: _unit)
                    else
                      const _EmptyHint(),
                    const SizedBox(height: AppSpacing.md),
                    AreaQuickConverter(
                      initialFrom: _unit,
                      initialTo: AreaUnit.squareFeet,
                      initialValue: value > 0 ? value : 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Area input card
// ---------------------------------------------------------------------------

class _AreaInputCard extends StatelessWidget {
  const _AreaInputCard({
    required this.controller,
    required this.unit,
    required this.onChanged,
    required this.onPickUnit,
  });

  final TextEditingController controller;
  final AreaUnit unit;
  final VoidCallback onChanged;
  final VoidCallback onPickUnit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c, width: w),
        );

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Property Area',
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Value.
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Value',
                        style: AppText.label
                            .copyWith(color: palette.textFaint, fontSize: 11)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => onChanged(),
                      style:
                          AppText.title.copyWith(color: palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'e.g. 312',
                        hintStyle:
                            AppText.body.copyWith(color: palette.textFaint),
                        filled: true,
                        fillColor: palette.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        border: border(palette.border),
                        enabledBorder: border(palette.border),
                        focusedBorder: border(AppColors.primaryGreen, 1.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Unit.
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unit',
                        style: AppText.label
                            .copyWith(color: palette.textFaint, fontSize: 11)),
                    const SizedBox(height: 5),
                    PressableScale(
                      pressedScale: 0.98,
                      child: Material(
                        color: palette.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onPickUnit,
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.chip),
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
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: palette.textFaint, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Enter an area value above to see it converted into every unit.',
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.lg),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Area Converter',
                    style: AppText.headline.copyWith(
                        color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text('Convert between all Indian land units',
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
