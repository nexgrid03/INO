import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart' show sharedBlurFilter;
import '../pressable_scale.dart';

/// Section 14 - the expandable Floating Action Button.
///
/// Tapping the brand-gradient FAB fans out a labelled stack of "Add …" actions
/// and blurs the full screen behind an overlay (same pattern as the nav `+`
/// menu). The main button stays in-tree and rotates into a close icon.
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({
    super.key,
    required this.actions,
    this.onAction,
    this.accent,
  });

  final List<QuickAction> actions;
  final void Function(QuickAction action)? onAction;

  /// Optional vault accent for the main FAB glow (defaults to brand teal).
  final Color? accent;

  static final ValueNotifier<bool> isMenuOpenNotifier = ValueNotifier<bool>(false);
  static bool get isMenuOpen {
    final state = _activeState;
    if (state != null) {
      return state._isOpen || isMenuOpenNotifier.value;
    }
    return isMenuOpenNotifier.value;
  }
  static _ExpandableFabState? _activeState;

  static bool closeActiveMenu() {
    final state = _activeState;
    if (state != null && (state._isOpen || isMenuOpenNotifier.value)) {
      debugPrint('[ExpandableFab] Executing closeActiveMenu()');
      state._closeMenu();
      isMenuOpenNotifier.value = false;
      return true;
    }
    return false;
  }

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  OverlayEntry? _entry;
  bool _open = false;

  bool get _isOpen => _entry != null;

  void _toggle() {
    HapticFeedback.selectionClick();
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    if (_isOpen) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final fabOrigin = box.localToGlobal(Offset.zero);
    final fabSize = box.size;
    final overlay = Overlay.of(context);

    _entry = OverlayEntry(
      builder: (ctx) => _FabMenuOverlay(
        animation: _c,
        fabOrigin: fabOrigin,
        fabSize: fabSize,
        actions: widget.actions,
        onDismiss: _closeMenu,
        onSelect: _select,
      ),
    );
    overlay.insert(_entry!);
    ExpandableFab.isMenuOpenNotifier.value = true;
    debugPrint('[ExpandableFab] Menu opened');
    setState(() => _open = true);
    _c.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (!_isOpen) return;
    ExpandableFab.isMenuOpenNotifier.value = false;
    debugPrint('[ExpandableFab] Menu closed');
    await _c.reverse();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  Future<void> _select(QuickAction action) async {
    await _closeMenu();
    if (!mounted) return;
    widget.onAction?.call(action);
  }

  @override
  void initState() {
    super.initState();
    ExpandableFab._activeState = this;
  }

  @override
  void dispose() {
    if (ExpandableFab._activeState == this) {
      ExpandableFab._activeState = null;
    }
    _entry?.remove();
    _entry = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MainButton(
      controller: _c,
      onTap: _toggle,
      accent: widget.accent,
      open: _open,
    );
  }
}

/// Full-screen blur scrim + action stack, positioned above the FAB.
class _FabMenuOverlay extends StatelessWidget {
  const _FabMenuOverlay({
    required this.animation,
    required this.fabOrigin,
    required this.fabSize,
    required this.actions,
    required this.onDismiss,
    required this.onSelect,
  });

  final Animation<double> animation;
  final Offset fabOrigin;
  final Size fabSize;
  final List<QuickAction> actions;
  final VoidCallback onDismiss;
  final void Function(QuickAction) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final count = actions.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        onDismiss();
      },
      child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: BackdropFilter(
                    // Bucketed + cached: a fresh ImageFilter per frame makes
                    // the engine rebuild the blur on every animation tick.
                    filter: sharedBlurFilter(7 * v),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.15 * v),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: size.width - fabOrigin.dx - fabSize.width,
                bottom: size.height - fabOrigin.dy + 6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < count; i++)
                      _MiniAction(
                        controller: animation,
                        index: count - 1 - i,
                        total: count,
                        action: actions[i],
                        palette: palette,
                        onTap: () => onSelect(actions[i]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
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

  final Animation<double> controller;
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
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.border),
                boxShadow: palette.cardShadow,
              ),
              child: Text(
                localizedQuickActionLabel(
                  AppLocalizations.of(context),
                  action.label,
                ),
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
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border),
                  boxShadow: [
                    BoxShadow(
                      color: action.color.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: palette.surface,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: Icon(action.icon, color: action.color, size: 22),
                    ),
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
  const _MainButton({
    required this.controller,
    required this.onTap,
    required this.open,
    this.accent,
  });

  final AnimationController controller;
  final VoidCallback onTap;
  final bool open;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.primaryGreen;
    final fill = accent != null
        ? AppColors.vaultFillGradient(accent!)
        : InoStyle.gradient(context, AppColors.brandGradient);
    return PressableScale(
      pressedScale: 0.92,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: fill,
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.40),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: tint.withValues(alpha: 0.22),
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
                child: Icon(
                  open ? Icons.close_rounded : Icons.add_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
