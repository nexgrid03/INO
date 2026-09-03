import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import 'quick_actions.dart';
import 'quick_menu_editor.dart';

/// One bottom-navigation destination.
///
/// Carries a translation *key* rather than a literal so the const [tabs] table
/// stays const while the visible label follows the app language.
class NavItem {
  const NavItem(this.labelKey, this.active, this.inactive);
  final String labelKey;
  final IconData active;
  final IconData inactive;

  /// The destination's name in the active language.
  String label(AppLocalizations l10n) => l10n.t(labelKey);
}

/// The INO floating bottom navigation bar - a premium, minimal white pill.
///
/// Five slots: Home · Vault · **+** · Alerts · Profile. The four side tabs
/// each carry a bespoke micro-interaction (a bounce, a lift, a bell wiggle, a
/// fade+scale) plus a smoothly sliding active-indicator dot.
///
/// The centre "+" carries the quick menu:
///  • **Tap** - fans out the user's picked features (up to 5, customisable via
///    the small Edit chip) over a dimmed, blurred backdrop.
///  • **Press & hold** - the same features appear as a radial wheel; keep
///    holding, slide onto an option and let go to open it. Sliding back to
///    the centre and releasing cancels.
///
/// Shared verbatim between [MainShell] and pushed routes so navigation looks
/// and behaves identically everywhere.
class InoBottomNav extends StatefulWidget {
  const InoBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
    this.onQuickMenuAction,
    this.homeTabKey,
    this.vaultTabKey,
    this.quickAddKey,
    this.alertsTabKey,
    this.profileTabKey,
  });

  final Key? homeTabKey;
  final Key? vaultTabKey;
  final Key? quickAddKey;
  final Key? alertsTabKey;
  final Key? profileTabKey;

  /// The active tab (0 Home · 1 Vault · 3 Alerts · 4 Profile). Index 2 is the
  /// centre "+" button and is never a resting page.
  final int index;

  /// Fired for the four real destinations only (never for the centre button).
  final void Function(int) onSelect;

  /// Fired after the quick menu (tap fan-out or hold-wheel) resolves to a
  /// feature.
  final void Function(QuickMenuAction)? onQuickMenuAction;

  /// The five primary destinations - single source of truth for every surface.
  static const List<NavItem> tabs = [
    NavItem('home', Icons.home_rounded, Icons.home_outlined),
    NavItem(
      'vault',
      Icons.account_balance_wallet_rounded,
      Icons.account_balance_wallet_outlined,
    ),
    NavItem('scan', Icons.document_scanner_rounded, Icons.document_scanner_rounded),
    NavItem(
      'alerts',
      Icons.notifications_rounded,
      Icons.notifications_none_rounded,
    ),
    NavItem('profile', Icons.person_rounded, Icons.person_outline_rounded),
  ];

  /// Global notifier indicating whether the FAB quick menu is currently open.
  static final ValueNotifier<bool> isMenuOpenNotifier = ValueNotifier<bool>(false);

  /// Helper getter to check if the FAB quick menu is currently open.
  static bool get isMenuOpen {
    final state = _activeState;
    if (state != null) {
      return state._open || state._wheelOpen || isMenuOpenNotifier.value;
    }
    return isMenuOpenNotifier.value;
  }

  static _InoBottomNavState? _activeState;

  /// Closes the active FAB menu if open. Returns `true` if a menu was closed.
  static bool closeActiveMenu() {
    final state = _activeState;
    if (state != null && (state._open || state._wheelOpen || isMenuOpenNotifier.value)) {
      debugPrint('[FAB Menu] Executing closeActiveMenu() on active nav state.');
      state._closeMenu();
      state._onHoldCancel();
      isMenuOpenNotifier.value = false;
      return true;
    }
    return false;
  }

  @override
  State<InoBottomNav> createState() => _InoBottomNavState();
}

class _InoBottomNavState extends State<InoBottomNav>
    with SingleTickerProviderStateMixin {
  /// Drives the "+" morph (+ ⇄ ×) and the open/close of BOTH overlays (the
  /// tap fan-out and the hold-wheel) - they never coexist, so one controller
  /// keeps every piece of motion on the same clock.
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 260),
  );

  final GlobalKey _scanKey = GlobalKey();
  OverlayEntry? _entry; // tap fan-out
  OverlayEntry? _wheelEntry; // press-and-hold wheel

  /// Live wheel state: overlay-local pointer + the currently highlighted slot.
  final ValueNotifier<int?> _highlight = ValueNotifier<int?>(null);
  List<QuickMenuAction> _wheelActions = const [];
  Offset _wheelCenter = Offset.zero;
  RenderBox? _overlayBox;

  bool get _open => _entry != null;
  bool get _wheelOpen => _wheelEntry != null;

  @override
  void initState() {
    super.initState();
    InoBottomNav._activeState = this;
  }

  @override
  void dispose() {
    if (InoBottomNav._activeState == this) {
      InoBottomNav._activeState = null;
    }
    _entry?.remove();
    _wheelEntry?.remove();
    _highlight.dispose();
    _menu.dispose();
    super.dispose();
  }

  // ---- Shared geometry -------------------------------------------------------

  /// Centre of the "+" button in overlay space (fallback: bottom-centre).
  Offset _buttonCenter() {
    final box = _scanKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    _overlayBox = overlayBox;
    if (box != null && overlayBox != null) {
      return box.localToGlobal(box.size.center(Offset.zero),
          ancestor: overlayBox);
    }
    final size = MediaQuery.sizeOf(context);
    return Offset(size.width / 2, size.height - 60);
  }

  /// Item angles (degrees, screen coords: -90 is straight up) for [n] slots -
  /// a symmetric arc centred over the button that widens with the count.
  /// Spreads are tuned so neighbouring icons keep even visual gaps at the
  /// menu / wheel radius (outer slots used to look cramped vs the crown).
  static List<double> arcAngles(int n) {
    if (n <= 1) return const [-90];
    final spread = switch (n) {
      2 => 70.0,
      3 => 118.0,
      4 => 148.0,
      _ => 168.0,
    };
    final start = -90 - spread / 2;
    final step = spread / (n - 1);
    return [for (var i = 0; i < n; i++) start + step * i];
  }

  static Offset _onArc(double angleDeg, double radius) {
    final rad = angleDeg * math.pi / 180;
    return Offset(math.cos(rad) * radius, math.sin(rad) * radius);
  }

  // ---- Tap fan-out menu ------------------------------------------------------

  void _toggleMenu() {
    if (_wheelOpen) return; // a hold is in flight
    _open ? _closeMenu() : _openMenu();
  }

  void _openMenu() {
    if (_open) return;
    HapticFeedback.lightImpact();
    final center = _buttonCenter();
    final actions = selectedQuickMenuActions();

    _entry = OverlayEntry(
      builder: (_) => _ScanMenu(
        animation: _menu,
        center: center,
        actions: actions,
        onDismiss: _closeMenu,
        onSelect: _selectAction,
        onEdit: _openEditor,
      ),
    );
    Overlay.of(context).insert(_entry!);
    InoBottomNav.isMenuOpenNotifier.value = true;
    debugPrint('[FAB Menu] FAB menu opened (current tab: ${widget.index})');
    setState(() {}); // repaint the morphing "+"
    _menu.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (!_open) return;
    HapticFeedback.lightImpact();
    InoBottomNav.isMenuOpenNotifier.value = false;
    debugPrint('[FAB Menu] FAB menu closed (current tab: ${widget.index})');
    await _menu.reverse();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  Future<void> _selectAction(QuickMenuAction action) async {
    HapticFeedback.selectionClick();
    await _closeMenu();
    if (!mounted) return;
    widget.onQuickMenuAction?.call(action);
  }

  Future<void> _openEditor() async {
    await _closeMenu();
    if (!mounted) return;
    await showQuickMenuEditor(context);
  }

  // ---- Press-and-hold wheel --------------------------------------------------

  static const double _wheelRadius = 126;

  void _onHoldStart(LongPressStartDetails details) {
    if (_open || _wheelOpen) return;
    HapticFeedback.mediumImpact();
    _wheelCenter = _buttonCenter();
    _wheelActions = selectedQuickMenuActions();
    _highlight.value = null;

    _wheelEntry = OverlayEntry(
      builder: (_) => _QuickWheel(
        animation: _menu,
        center: _wheelCenter,
        actions: _wheelActions,
        highlight: _highlight,
        onDismiss: _onHoldCancel,
      ),
    );
    Overlay.of(context).insert(_wheelEntry!);
    InoBottomNav.isMenuOpenNotifier.value = true;
    debugPrint('[FAB Menu] FAB hold-wheel opened (current tab: ${widget.index})');
    setState(() {}); // morph + → ×
    _menu.forward(from: 0);
    _trackPointer(details.globalPosition);
  }

  void _onHoldMove(LongPressMoveUpdateDetails details) {
    if (_wheelOpen) _trackPointer(details.globalPosition);
  }

  Future<void> _onHoldEnd(LongPressEndDetails details) async {
    if (!_wheelOpen) return;
    final picked = _highlight.value;
    final action = (picked != null && picked < _wheelActions.length)
        ? _wheelActions[picked]
        : null;
    if (action != null) HapticFeedback.mediumImpact();

    InoBottomNav.isMenuOpenNotifier.value = false;
    debugPrint('[FAB Menu] FAB hold-wheel closed (current tab: ${widget.index})');
    await _menu.reverse();
    _wheelEntry?.remove();
    _wheelEntry = null;
    _highlight.value = null;
    if (!mounted) return;
    setState(() {});
    if (action != null) widget.onQuickMenuAction?.call(action);
  }

  void _onHoldCancel() {
    if (!_wheelOpen) return;
    InoBottomNav.isMenuOpenNotifier.value = false;
    debugPrint('[FAB Menu] FAB hold-wheel cancelled (current tab: ${widget.index})');
    _menu.reverse().whenComplete(() {
      _wheelEntry?.remove();
      _wheelEntry = null;
      if (mounted) setState(() {});
    });
    _highlight.value = null;
  }

  /// Maps the finger's overlay position to the wheel slot under it (or null in
  /// the centre dead-zone), buzzing softly whenever the highlight moves.
  void _trackPointer(Offset globalPosition) {
    final local = _overlayBox?.globalToLocal(globalPosition) ?? globalPosition;
    final d = local - _wheelCenter;
    final r = d.distance;

    int? next;
    if (r >= 42 && _wheelActions.isNotEmpty) {
      final angles = arcAngles(_wheelActions.length);
      final deg = math.atan2(d.dy, d.dx) * 180 / math.pi;
      var best = 0;
      var bestDiff = double.infinity;
      for (var i = 0; i < angles.length; i++) {
        final diff = (deg - angles[i]).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = i;
        }
      }
      // Generous capture band: half the slot spacing plus a margin, so the
      // wheel feels forgiving rather than fiddly. A lone item accepts a wide
      // upward cone.
      final step = angles.length > 1 ? (angles[1] - angles[0]) : 120.0;
      if (bestDiff <= step / 2 + 14) next = best;
    }

    if (next != _highlight.value) {
      if (next != null) HapticFeedback.selectionClick();
      _highlight.value = next;
    }
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        // Dark: solid-enough base so icons stay readable over scrolling content
        // (Flutter web has no BackdropFilter). Light keeps the airy glass look.
        child: Material(
          color: dark
              ? palette.surface.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.96),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: dark ? 0.4 : 0.08),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: dark ? palette.border : AppColors.tealPale.withValues(alpha: 0.6),
                width: 1.0,
              ),
            ),
            child: SizedBox(
              height: context.horizontalCardHeight(66),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Mountain-shaped curved bump behind the active tab (WhatsApp style).
                    if (widget.index != 2)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final slot = constraints.maxWidth /
                                  InoBottomNav.tabs.length;
                              final mountainWidth = math.min(slot + 38, 110.0);
                              final mountainColor = dark
                                  ? AppColors.primaryGreen.withValues(alpha: 0.22)
                                  : (InoStyle.isAqua(context)
                                      ? AppColors.aquaMist.withValues(alpha: 0.85)
                                      : const Color(0xFFE0F2FE));
                              final mountainBorder = dark
                                  ? AppColors.primaryGreen.withValues(alpha: 0.28)
                                  : const Color(0xFFBAE6FD);

                              return Stack(
                                children: [
                                  AnimatedPositioned(
                                    key: const ValueKey('mountain_indicator'),
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeInOutCubic,
                                    left: slot * widget.index +
                                        (slot - mountainWidth) / 2,
                                    top: 0,
                                    bottom: 0,
                                    width: mountainWidth,
                                    child: CustomPaint(
                                      painter: MountainShapePainter(
                                        color: mountainColor,
                                        borderColor: mountainBorder,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        for (var i = 0; i < InoBottomNav.tabs.length; i++)
                          Expanded(
                            child: i == 2
                                ? Center(
                                    child: _ScanButton(
                                      key: widget.quickAddKey ?? _scanKey,
                                      progress: _menu,
                                      onTap: _toggleMenu,
                                      onHoldStart: _onHoldStart,
                                      onHoldMove: _onHoldMove,
                                      onHoldEnd: _onHoldEnd,
                                      onHoldCancel: _onHoldCancel,
                                    ),
                                  )
                                : _TabButton(
                                    key: _tabKeyFor(i),
                                    item: InoBottomNav.tabs[i],
                                    kind: _kindFor(i),
                                    selected: widget.index == i,
                                    onTap: () => widget.onSelect(i),
                                  ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static _TabKind _kindFor(int i) => switch (i) {
        0 => _TabKind.home,
        1 => _TabKind.wallet,
        3 => _TabKind.notifications,
        _ => _TabKind.profile,
      };

  Key? _tabKeyFor(int i) => switch (i) {
        0 => widget.homeTabKey,
        1 => widget.vaultTabKey,
        2 => widget.quickAddKey,
        3 => widget.alertsTabKey,
        4 => widget.profileTabKey,
        _ => null,
      };
}

/// Custom painter that draws a soft mountain-like curved bump (WhatsApp style).
class MountainShapePainter extends CustomPainter {
  const MountainShapePainter({
    required this.color,
    this.borderColor,
  });

  final Color color;
  final Color? borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final peakX = w / 2;
    const topY = 4.0;
    final bottomY = h;

    final path = Path();
    path.moveTo(0, bottomY);

    // Left flare: wide smooth horizontal entrance blending from baseline to flank
    path.cubicTo(
      w * 0.30, bottomY,
      peakX - 32, bottomY * 0.44,
      peakX - 22, bottomY * 0.24,
    );

    // Wide, rounded dome crest (WhatsApp style)
    path.cubicTo(
      peakX - 12, topY,
      peakX + 12, topY,
      peakX + 22, bottomY * 0.24,
    );

    // Right flare: wide smooth descent blending back to baseline
    path.cubicTo(
      peakX + 32, bottomY * 0.44,
      w * 0.70, bottomY,
      w, bottomY,
    );

    path.close();

    // Soft blended fill gradient
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color,
        color.withValues(alpha: color.a * 0.75),
      ],
    );

    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    if (borderColor != null) {
      final borderPaint = Paint()
        ..color = borderColor!.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      final strokePath = Path();
      strokePath.moveTo(0, bottomY);
      strokePath.cubicTo(
        w * 0.30, bottomY,
        peakX - 32, bottomY * 0.44,
        peakX - 22, bottomY * 0.24,
      );
      strokePath.cubicTo(
        peakX - 12, topY,
        peakX + 12, topY,
        peakX + 22, bottomY * 0.24,
      );
      strokePath.cubicTo(
        peakX + 32, bottomY * 0.44,
        w * 0.70, bottomY,
        w, bottomY,
      );
      canvas.drawPath(strokePath, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MountainShapePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}

/// The bespoke micro-interaction each side tab plays when it becomes active.
enum _TabKind { home, wallet, notifications, profile }

/// A single side tab: icon and label that fade grey⇄primary, pop
/// on selection, and layer their signature motion on top.
class _TabButton extends StatefulWidget {
  const _TabButton({
    super.key,
    required this.item,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final _TabKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void didUpdateWidget(covariant _TabButton old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(
        height: 56,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final icon = TweenAnimationBuilder<double>(
                tween: Tween(end: widget.selected ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                builder: (context, sel, _) {
                  final idle = palette.isDark
                      ? palette.textPrimary.withValues(alpha: 0.55)
                      : palette.textSecondary;
                  return Icon(
                    widget.selected
                        ? widget.item.active
                        : widget.item.inactive,
                    size: 24,
                    color: Color.lerp(idle, AppColors.primaryGreen, sel),
                  );
                },
              );

              final content = Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(height: 2),
                  Text(
                    widget.item.label(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      color: widget.selected
                          ? AppColors.primaryGreen
                          : (palette.isDark
                              ? palette.textPrimary.withValues(alpha: 0.6)
                              : palette.textSecondary),
                    ),
                  ),
                ],
              );

              return _decorate(content, t);
            },
          ),
        ),
      ),
    );
  }

  /// Applies the shared "pop" (1 → 1.15 → 1) plus this tab's signature motion.
  /// [t] runs 0→1 once on selection; every term is zero at both ends.
  Widget _decorate(Widget child, double t) {
    // Bell-shaped 0→1→0 envelope for the there-and-back pop.
    final env = math.sin(t * math.pi);
    final pop = 1 + env * 0.15; // 1 → 1.15 → 1

    switch (widget.kind) {
      case _TabKind.home:
        // Tiny upward bounce.
        return Transform.translate(
          offset: Offset(0, -env * 5),
          child: Transform.scale(scale: pop, child: child),
        );
      case _TabKind.wallet:
        // Slides upward ~4px and settles.
        return Transform.translate(
          offset: Offset(0, -env * 4),
          child: Transform.scale(scale: pop, child: child),
        );
      case _TabKind.notifications:
        // Bell wiggle: a quick damped rotation.
        final wiggle = math.sin(t * math.pi * 3) * (1 - t) * 0.28;
        return Transform.rotate(
          angle: wiggle,
          child: Transform.scale(scale: pop, child: child),
        );
      case _TabKind.profile:
        // Fade + scale.
        return Opacity(
          opacity: 1 - env * 0.35,
          child: Transform.scale(scale: pop, child: child),
        );
    }
  }
}

/// The centre "+" button: a filled primary circle with a soft shadow that
/// compresses on press and rotates 45° (+ → ×) as either quick-menu overlay
/// opens. Tap toggles the fan-out; press-and-hold drives the wheel via the
/// four long-press callbacks.
class _ScanButton extends StatefulWidget {
  const _ScanButton({
    super.key,
    required this.progress,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldMove,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  final Animation<double> progress;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails) onHoldStart;
  final void Function(LongPressMoveUpdateDetails) onHoldMove;
  final void Function(LongPressEndDetails) onHoldEnd;
  final VoidCallback onHoldCancel;

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // The hold-wheel gesture. The InkWell below owns plain taps; the arena
      // hands the pointer here once the long-press deadline passes.
      onLongPressStart: widget.onHoldStart,
      onLongPressMoveUpdate: widget.onHoldMove,
      onLongPressEnd: widget.onHoldEnd,
      onLongPressCancel: widget.onHoldCancel,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1, // Step 1 - slight compress
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.42),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            // Single tap source: the InkWell drives the ripple, the
            // press-compress (via onHighlightChanged) and the tap - so the
            // menu toggles once.
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withValues(alpha: 0.28), // ripple
              highlightColor: Colors.transparent,
              onHighlightChanged: _setPressed,
              onTap: widget.onTap,
              child: AnimatedBuilder(
                animation: widget.progress,
                builder: (context, _) {
                  final v = widget.progress.value;
                  // A single "+" that rotates 0° → 135° so it reads as an "×"
                  // once a quick menu is open.
                  return Transform.rotate(
                    angle: v * (3 * math.pi / 4),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tap fan-out menu (full-screen overlay)
// ---------------------------------------------------------------------------

/// Radius of the fan-out arc the tap menu lays its items on.
const double _kMenuRadius = 118;

/// Diameter of each quick-menu icon disc - used so arc maths pin the *disc*
/// centre (not the label) onto the arc.
const double _kMenuIconSize = 54;

class _ScanMenu extends StatelessWidget {
  const _ScanMenu({
    required this.animation,
    required this.center,
    required this.actions,
    required this.onDismiss,
    required this.onSelect,
    required this.onEdit,
  });

  final Animation<double> animation;
  final Offset center;
  final List<QuickMenuAction> actions;
  final VoidCallback onDismiss;
  final void Function(QuickMenuAction) onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
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
        final angles = _InoBottomNavState.arcAngles(actions.length);
        // Wrap in a transparent Material so the action labels inherit a proper
        // text style - without a Material ancestor an overlay's Text renders
        // with Flutter's debug yellow underline.
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // Dimmed + blurred backdrop (both fade in with the menu).
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: BackdropFilter(
                    // Bucketed + cached: building a fresh ImageFilter here made the
                    // engine recompile the blur shader on every frame of the
                    // menu animation.
                    filter: sharedBlurFilter(7 * v),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.15 * v),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < actions.length; i++)
                _positioned(
                  context,
                  actions[i],
                  _InoBottomNavState._onArc(angles[i], _kMenuRadius),
                  i,
                ),
              // The small Edit chip, floating above the arc's crown.
              _editChip(context),
            ],
          ),
        );
      },
    ),
  );
  }

  Widget _positioned(
    BuildContext context,
    QuickMenuAction action,
    Offset offset,
    int i,
  ) {
    // Stagger each child by ~50ms (≈0.13 of the 380ms controller).
    final start = (0.15 + i * 0.10).clamp(0.0, 0.85);
    final raw = ((animation.value - start) / (1 - start)).clamp(0.0, 1.0);
    final t = Curves.easeOutBack.transform(raw);
    final fade = Curves.easeOut.transform(raw);

    // Wide enough for the longest English label ("Expenses" / "Reminder")
    // without clipping; icon + label stay centred in this column.
    const box = 80.0;
    final cx = center.dx + offset.dx;
    final cy = center.dy + offset.dy;
    // 20px upward rise that eases to 0 as the item settles.
    final rise = 20 * (1 - fade);

    return Positioned(
      left: cx - box / 2,
      // Pin the icon disc centre onto the arc (labels hang below, centred).
      top: cy - (_kMenuIconSize / 2) + rise,
      width: box,
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: 0.8 + 0.2 * t, // 0.8 → 1
          alignment: Alignment.topCenter,
          child: _MenuButton(action: action, onTap: () => onSelect(action)),
        ),
      ),
    );
  }

  /// A compact tonal "Edit" pill above the arc - opens the quick-menu
  /// customiser. Enters last, after the feature items.
  ///
  /// Anchored on the "+" button centre (not the screen centre) so it sits
  /// directly above the crown item. Width is intrinsic so localized labels
  /// like Hindi "संपादित करें" never overflow the pill.
  Widget _editChip(BuildContext context) {
    final palette = AppPalette.of(context);
    final raw = ((animation.value - 0.55) / 0.45).clamp(0.0, 1.0);
    final t = Curves.easeOutBack.transform(raw);
    final fade = Curves.easeOut.transform(raw);
    const chipSlot = 200.0;

    return Positioned(
      left: center.dx - chipSlot / 2,
      width: chipSlot,
      top: center.dy - _kMenuRadius - 76,
      child: Center(
        child: Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.isDark ? palette.bgElevated : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: palette.isDark ? 0.4 : 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 15, color: AppColors.primaryGreen),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context).t('edit'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({required this.action, required this.onTap});

  final QuickMenuAction action;
  final VoidCallback onTap;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: _kMenuIconSize,
              height: _kMenuIconSize,
              decoration: BoxDecoration(
                color: palette.isDark
                    ? palette.bgElevated
                    : Color.alphaBlend(
                        AppColors.primaryGreen.withValues(alpha: 0.06),
                        Colors.white,
                      ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.22),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: palette.isDark ? 0.4 : 0.10,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.action.icon,
                color: AppColors.primaryGreen,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.action.label(AppLocalizations.of(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.1,
                shadows: palette.isDark
                    ? null
                    : const [
                        Shadow(color: Colors.white, blurRadius: 6),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Press-and-hold wheel (full-screen overlay)
// ---------------------------------------------------------------------------

/// The hold-wheel: the picked features arranged on a radial arc around the
/// "+" button. Purely visual - the finger never leaves the button's gesture,
/// so hit-testing happens in the nav state (`_trackPointer`) and this layer
/// just renders the [highlight].
class _QuickWheel extends StatelessWidget {
  const _QuickWheel({
    required this.animation,
    required this.center,
    required this.actions,
    required this.highlight,
    this.onDismiss,
  });

  final Animation<double> animation;
  final Offset center;
  final List<QuickMenuAction> actions;
  final ValueListenable<int?> highlight;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        onDismiss?.call();
      },
      child: AnimatedBuilder(
        animation: animation,
      builder: (context, _) {
        final v = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
        final angles = _InoBottomNavState.arcAngles(actions.length);
        return Material(
          type: MaterialType.transparency,
          child: IgnorePointer(
            // The wheel never takes pointers - the long-press that opened it
            // keeps them until release.
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: v,
                    child: BackdropFilter(
                      filter: sharedBlurFilter(7.0),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
                // Hint, tucked under the wheel's crown item.
                _hint(context, v),
                for (var i = 0; i < actions.length; i++)
                  _slot(
                    context,
                    actions[i],
                    _InoBottomNavState._onArc(
                        angles[i], _InoBottomNavState._wheelRadius),
                    i,
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  }

  Widget _hint(BuildContext context, double v) {
    const w = 220.0;
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - _InoBottomNavState._wheelRadius - 96,
      width: w,
      child: Opacity(
        opacity: (v * 1.2 - 0.2).clamp(0.0, 1.0) * 0.9,
        child: Text(
          AppLocalizations.of(context).t('slideToOpenHint'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
          ),
        ),
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    QuickMenuAction action,
    Offset offset,
    int i,
  ) {
    final palette = AppPalette.of(context);
    // Stagger the slots in like the tap menu, just a touch quicker.
    final start = (0.10 + i * 0.08).clamp(0.0, 0.85);
    final raw = ((animation.value - start) / (1 - start)).clamp(0.0, 1.0);
    final t = Curves.easeOutBack.transform(raw);
    final fade = Curves.easeOut.transform(raw);

    const box = 80.0;
    const iconSize = 56.0;
    final cx = center.dx + offset.dx;
    final cy = center.dy + offset.dy;
    final rise = 16 * (1 - fade);

    return Positioned(
      left: cx - box / 2,
      top: cy - (iconSize / 2) + rise,
      width: box,
      child: ValueListenableBuilder<int?>(
        valueListenable: highlight,
        builder: (context, hi, _) {
          final hot = hi == i;
          return Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: (0.8 + 0.2 * t) * (hot ? 1.18 : 1.0),
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (InoStyle.usesDivineGlass(context) && !hot)
                    LiquidGlass(
                      circle: true,
                      blur: 16,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: iconSize,
                        height: iconSize,
                        child: Icon(
                          action.icon,
                          color: AppColors.primaryGreen,
                          size: 26,
                        ),
                      ),
                    )
                  else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: iconSize,
                      height: iconSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hot
                            ? AppColors.primaryGreen
                            : (palette.isDark
                                ? palette.bgElevated
                                : Color.alphaBlend(
                                    AppColors.primaryGreen
                                        .withValues(alpha: 0.06),
                                    Colors.white,
                                  )),
                        shape: BoxShape.circle,
                        border: hot
                            ? null
                            : Border.all(
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.22),
                                width: 1.4,
                              ),
                        boxShadow: [
                          BoxShadow(
                            color: hot
                                ? AppColors.primaryGreen.withValues(alpha: 0.45)
                                : Colors.black.withValues(
                                    alpha: palette.isDark ? 0.4 : 0.10),
                            blurRadius: hot ? 20 : 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        action.icon,
                        color: hot ? Colors.white : AppColors.primaryGreen,
                        size: InoStyle.usesDivineGlass(context) ? 26 : 24,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    action.label(AppLocalizations.of(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hot && !palette.isDark
                          ? AppColors.primaryGreen
                          : palette.textPrimary,
                      fontSize: 11.5,
                      fontWeight: hot ? FontWeight.w800 : FontWeight.w700,
                      height: 1.1,
                      shadows: palette.isDark
                          ? null
                          : const [Shadow(color: Colors.white, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
