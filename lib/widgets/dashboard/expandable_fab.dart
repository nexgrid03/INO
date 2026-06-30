import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 14 — the expandable Floating Action Button.
///
/// Tapping the brand-gradient FAB fans out a labelled stack of "Add …" actions
/// (document, reminder, investment, property, insurance, health record) and
/// dims the screen behind a scrim. The main button rotates into a close icon.
/// Driven by a single controller; each mini-action staggers in via an Interval.
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({
    super.key,
    required this.actions,
    this.onAction,
  });

  final List<QuickAction> actions;
  final void Function(QuickAction action)? onAction;

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _open = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
    if (_open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  void _select(QuickAction action) {
    _toggle();
    widget.onAction?.call(action);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final count = widget.actions.length;

    return Stack(
      alignment: Alignment.bottomRight,
      clipBehavior: Clip.none,
      children: [
        // Scrim — only hit-testable while open.
        if (_open || _c.value > 0)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_open,
              child: FadeTransition(
                opacity: _c,
                child: GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),

        // Action stack + main button.
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < count; i++)
                _MiniAction(
                  controller: _c,
                  // Later items lead so the column opens top-down smoothly.
                  index: count - 1 - i,
                  total: count,
                  action: widget.actions[i],
                  palette: palette,
                  onTap: () => _select(widget.actions[i]),
                ),
              const SizedBox(height: 6),
              _MainButton(controller: _c, onTap: _toggle),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.controller,
    required this.index,
    required this.total,
    required this.action,
    required this.palette,
    required this.onTap,
  });

  final AnimationController controller;
  final int index;
  final int total;
  final QuickAction action;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = (index / total) * 0.6;
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final v = anim.value.clamp(0.0, 1.0);
        if (v == 0) return const SizedBox.shrink();
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 16),
            child: Transform.scale(scale: 0.85 + v * 0.15, child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label pill.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
                boxShadow: palette.cardShadow,
              ),
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            PressableScale(
              pressedScale: 0.9,
              child: Material(
                color: action.color,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                elevation: 3,
                shadowColor: action.color.withValues(alpha: 0.5),
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Icon(action.icon, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({required this.controller, required this.onTap});

  final AnimationController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.92,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.brandGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.40),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
            // Light-blue ambient halo for a premium floating feel.
            BoxShadow(
              color: AppColors.lightBlue.withValues(alpha: 0.30),
              blurRadius: 24,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Transform.rotate(
                angle: controller.value * 0.785398, // 45°
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
