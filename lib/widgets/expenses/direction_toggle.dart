import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/expense_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A two-segment control for the money direction — **Debited** (money out) and
/// **Credited** (money in) — used on the Add Transaction form below the amount.
///
/// Debited uses a subtle neutral/red accent, credited the app's teal/green, so
/// the selected side reads at a glance. When [highlight] is true (e.g. the
/// value was just auto-set from a scanned receipt) the selected segment briefly
/// pulses so the user notices it changed.
class DirectionToggle extends StatefulWidget {
  const DirectionToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.highlight = false,
  });

  final TransactionDirection value;
  final ValueChanged<TransactionDirection> onChanged;

  /// When true, the selected segment plays a one-shot attention pulse.
  final bool highlight;

  @override
  State<DirectionToggle> createState() => _DirectionToggleState();
}

class _DirectionToggleState extends State<DirectionToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  static const _debitColor = AppColors.critical; // money out — subtle red
  static const _creditColor = AppColors.primaryGreen; // money in — teal/green

  @override
  void initState() {
    super.initState();
    if (widget.highlight) _pulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(DirectionToggle old) {
    super.didUpdateWidget(old);
    // Re-pulse whenever a fresh auto-set arrives.
    if (widget.highlight && !old.highlight) _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _select(TransactionDirection d) {
    if (d == widget.value) return;
    HapticFeedback.selectionClick();
    widget.onChanged(d);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          _segment(
            palette,
            direction: TransactionDirection.debited,
            label: 'Debited',
            icon: Icons.south_west_rounded,
            accent: _debitColor,
          ),
          _segment(
            palette,
            direction: TransactionDirection.credited,
            label: 'Credited',
            icon: Icons.north_east_rounded,
            accent: _creditColor,
          ),
        ],
      ),
    );
  }

  Widget _segment(
    AppPalette palette, {
    required TransactionDirection direction,
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    final selected = widget.value == direction;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label ${direction == TransactionDirection.debited ? 'money out' : 'money in'}',
        child: PressableScale(
          pressedScale: 0.97,
          child: GestureDetector(
            onTap: () => _select(direction),
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                // A soft glow ring on the selected segment during a pulse.
                final t = selected ? (1 - (_pulse.value - 0.5).abs() * 2) : 0.0;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.chip - 4),
                    border: Border.all(
                      color: selected ? accent : Colors.transparent,
                      width: 1.4,
                    ),
                    boxShadow: t > 0
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.45 * t),
                              blurRadius: 14 * t,
                              spreadRadius: 1.5 * t,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 16,
                      color: selected ? accent : palette.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppText.subtitle.copyWith(
                      color: selected ? accent : palette.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
