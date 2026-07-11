import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/area_unit.dart';
import '../../services/area_conversion_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';
import 'area_unit_picker.dart';

/// A reusable, self-contained "Quick Convert" card: enter a value, pick a
/// From/To unit, and see the result instantly. Drop it anywhere.
///
/// All maths is delegated to [AreaConversionService] — no factors live here.
class AreaQuickConverter extends StatefulWidget {
  const AreaQuickConverter({
    super.key,
    this.initialFrom = AreaUnit.squareMetres,
    this.initialTo = AreaUnit.squareYards,
    this.initialValue = 1,
    this.title = 'Quick Convert',
  });

  final AreaUnit initialFrom;
  final AreaUnit initialTo;
  final double initialValue;
  final String title;

  @override
  State<AreaQuickConverter> createState() => _AreaQuickConverterState();
}

class _AreaQuickConverterState extends State<AreaQuickConverter> {
  static const _service = AreaConversionService.instance;

  late final TextEditingController _controller =
      TextEditingController(text: _trim(widget.initialValue));
  late AreaUnit _from = widget.initialFrom;
  late AreaUnit _to = widget.initialTo;

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_controller.text.trim()) ?? 0;

  void _swap() {
    HapticFeedback.selectionClick();
    setState(() {
      final t = _from;
      _from = _to;
      _to = t;
    });
  }

  Future<void> _pickUnit({required bool isFrom}) async {
    final picked = await showAreaUnitPicker(
      context,
      selected: isFrom ? _from : _to,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final result = _service.convert(_value, _from, _to);

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_vert_rounded,
                  color: AppColors.lightBlue, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(widget.title,
                  style: AppText.title.copyWith(color: palette.textPrimary)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Value input.
          TextField(
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            style: AppText.title.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter value',
              hintStyle: AppText.body.copyWith(color: palette.textFaint),
              filled: true,
              fillColor: palette.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              border: _border(palette.border),
              enabledBorder: _border(palette.border),
              focusedBorder: _border(AppColors.primaryGreen, 1.6),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // From / swap / To.
          Row(
            children: [
              Expanded(
                child: _UnitSelector(
                  label: 'From',
                  unit: _from,
                  onTap: () => _pickUnit(isFrom: true),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: PressableScale(
                  pressedScale: 0.9,
                  child: Material(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _swap,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.swap_horiz_rounded,
                            color: AppColors.primaryGreen, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _UnitSelector(
                  label: 'To',
                  unit: _to,
                  onTap: () => _pickUnit(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Result.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: AppColors.insightGradient,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_service.formatWithUnit(_value, _from)}  =',
                  style: AppText.caption
                      .copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 2),
                Text(
                  _service.formatWithUnit(result, _to),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.headline
                      .copyWith(color: Colors.white, fontSize: 24),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: BorderSide(color: c, width: w),
      );
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({
    required this.label,
    required this.unit,
    required this.onTap,
  });

  final String label;
  final AreaUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
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
              onTap: onTap,
              child: Container(
                height: 48,
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
