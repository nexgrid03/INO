import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// One bottom-navigation destination.
class NavItem {
  const NavItem(this.label, this.active, this.inactive);
  final String label;
  final IconData active;
  final IconData inactive;
}

/// The quick-action surfaced by the centre button's expanding menu.
enum ScanAction { expenses, scan, notes }

/// The INO floating bottom navigation bar — a premium, minimal white pill.
///
/// Five slots: Home · Vault · **Scan** · Alerts · Profile. The four side tabs
/// each carry a bespoke micro-interaction (a bounce, a lift, a bell wiggle, a
/// fade+scale) plus a smoothly sliding active-indicator dot; the centre is a
/// filled circular Scan button that morphs into a close (X) and fans out an
/// arc of quick actions over a dimmed, blurred backdrop.
///
/// Shared verbatim between [MainShell] and pushed routes so navigation looks
/// and behaves identically everywhere.
class InoBottomNav extends StatefulWidget {
  const InoBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
    this.onScanAction,
  });

  /// The active tab (0 Home · 1 Vault · 3 Alerts · 4 Profile). Index 2 is the
  /// centre Scan button and is never a resting page.
  final int index;

  /// Fired for the four real destinations only (never for the centre button).
  final void Function(int) onSelect;

  /// Fired after the quick-action menu closes, with the chosen scan action.
  final void Function(ScanAction)? onScanAction;

  /// The five primary destinations — single source of truth for every surface.
  static const List<NavItem> tabs = [
    NavItem('Home', Icons.home_rounded, Icons.home_outlined),
    NavItem(
      'Vault',
      Icons.account_balance_wallet_rounded,
      Icons.account_balance_wallet_outlined,
    ),
    NavItem('Scan', Icons.document_scanner_rounded, Icons.document_scanner_rounded),
    NavItem(
      'Alerts',
      Icons.notifications_rounded,
      Icons.notifications_none_rounded,
    ),
    NavItem('Profile', Icons.person_rounded, Icons.person_outline_rounded),
  ];

  @override
  State<InoBottomNav> createState() => _InoBottomNavState();
}

class _InoBottomNavState extends State<InoBottomNav>
    with SingleTickerProviderStateMixin {
  /// Drives both the Scan-button morph (Scan ⇄ X) and the arc-menu open/close.
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 260),
  );

  final GlobalKey _scanKey = GlobalKey();
  OverlayEntry? _entry;

  bool get _open => _entry != null;

  @override
  void dispose() {
    _entry?.remove();
    _menu.dispose();
    super.dispose();
  }

  // ---- Quick-action menu ---------------------------------------------------

  void _toggleMenu() => _open ? _closeMenu() : _openMenu();

  void _openMenu() {
    if (_open) return;
    HapticFeedback.lightImpact();
    final box = _scanKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    // Centre of the Scan button in overlay-space (fallback: bottom-centre).
    Offset center;
    if (box != null && overlayBox != null) {
      center = box.localToGlobal(
        box.size.center(Offset.zero),
        ancestor: overlayBox,
      );
    } else {
      final size = MediaQuery.of(context).size;
      center = Offset(size.width / 2, size.height - 60);
    }

    _entry = OverlayEntry(
      builder: (_) => _ScanMenu(
        animation: _menu,
        center: center,
        onDismiss: _closeMenu,
        onSelect: _selectAction,
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {}); // repaint the morphing Scan button
    _menu.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (!_open) return;
    HapticFeedback.lightImpact();
    await _menu.reverse();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  Future<void> _selectAction(ScanAction action) async {
    HapticFeedback.selectionClick();
    await _closeMenu();
    if (!mounted) return;
    widget.onScanAction?.call(action);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = palette.isDark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // Pure white (elevated surface in dark) — no glass, no gradient.
            color: isDark ? palette.bgElevated : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // Soft ambient lift — deliberately gentle, never harsh.
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.07),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.035),
                blurRadius: 7,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The sliding active-indicator line, aligned under the live tab.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment(_dotX(widget.index), 1),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Container(
                        width: 22,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
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
                                key: _scanKey,
                                progress: _menu,
                                onTap: _toggleMenu,
                              ),
                            )
                          : _TabButton(
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
    );
  }

  /// Horizontal alignment (-1..1) of the indicator dot for a given tab, across
  /// the five equal slots. Index 2 (Scan) has no dot.
  static double _dotX(int index) => -1 + (2 * index + 1) / 5;

  static _TabKind _kindFor(int i) => switch (i) {
        0 => _TabKind.home,
        1 => _TabKind.wallet,
        3 => _TabKind.notifications,
        _ => _TabKind.profile,
      };
}

/// The bespoke micro-interaction each side tab plays when it becomes active.
enum _TabKind { home, wallet, notifications, profile }

/// A single side tab: constant 26px glyph that fades grey⇄primary, pops
/// (1 → 1.15 → 1) on selection, and layers its signature motion on top.
class _TabButton extends StatefulWidget {
  const _TabButton({
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
  // One-shot 250ms controller: fires each time the tab becomes active, then
  // rests — every transform below returns to zero at t=1 so nothing sticks.
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(
        height: 50,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              // Sustained colour fade lives in its own implicit tween so it
              // stays smooth independent of the one-shot motion controller.
              final icon = TweenAnimationBuilder<double>(
                tween: Tween(end: widget.selected ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                builder: (context, sel, _) => Icon(
                  widget.selected ? widget.item.active : widget.item.inactive,
                  size: 26,
                  color: Color.lerp(
                    palette.textFaint,
                    AppColors.primaryGreen,
                    sel,
                  ),
                ),
              );
              return _decorate(icon, t);
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

/// The centre Scan button: a filled primary circle with a soft shadow that
/// compresses on press, rotates 45° and morphs its glyph from scan → close as
/// the [progress] controller drives the quick-action menu open.
class _ScanButton extends StatefulWidget {
  const _ScanButton({
    super.key,
    required this.progress,
    required this.onTap,
  });

  final Animation<double> progress;
  final VoidCallback onTap;

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.95 : 1, // Step 1 — slight compress
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
          // Single tap source: the InkWell drives the ripple, the press-compress
          // (via onHighlightChanged) and the tap — so the menu toggles once.
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withValues(alpha: 0.28), // Step 2 ripple
            highlightColor: Colors.transparent,
            onHighlightChanged: _setPressed,
            onTap: widget.onTap,
            child: AnimatedBuilder(
                animation: widget.progress,
                builder: (context, _) {
                  final v = widget.progress.value;
                  // A single "+" that rotates 0° → 135° so it reads as an "×"
                  // once the quick-action menu is open.
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
    );
  }
}

// ---------------------------------------------------------------------------
// Expanding quick-action menu (full-screen overlay)
// ---------------------------------------------------------------------------

class _MenuSpec {
  const _MenuSpec(this.action, this.icon, this.label, this.offset);
  final ScanAction action;
  final IconData icon;
  final String label;

  /// Position of the item's circle centre, relative to the Scan button centre
  /// (y negative = upward). Together the four form a gentle upward arc.
  final Offset offset;
}

// Exactly three actions, in this order, forming a shallow upward arc. Edit
// this one list to add or remove an item.
const List<_MenuSpec> _kMenu = [
  _MenuSpec(ScanAction.expenses, Icons.account_balance_wallet_rounded,
      'Expenses', Offset(-78, -64)),
  _MenuSpec(
      ScanAction.scan, Icons.document_scanner_rounded, 'Scan', Offset(0, -104)),
  _MenuSpec(ScanAction.notes, Icons.edit_rounded, 'Notes', Offset(78, -64)),
];

class _ScanMenu extends StatelessWidget {
  const _ScanMenu({
    required this.animation,
    required this.center,
    required this.onDismiss,
    required this.onSelect,
  });

  final Animation<double> animation;
  final Offset center;
  final VoidCallback onDismiss;
  final void Function(ScanAction) onSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
        // Wrap in a transparent Material so the action labels inherit a proper
        // text style — without a Material ancestor an overlay's Text renders
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
                    filter: ImageFilter.blur(sigmaX: 7 * v, sigmaY: 7 * v),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.15 * v),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < _kMenu.length; i++)
                _positioned(context, _kMenu[i], i),
            ],
          ),
        );
      },
    );
  }

  Widget _positioned(BuildContext context, _MenuSpec spec, int i) {
    // Stagger each child by ~50ms (≈0.13 of the 380ms controller).
    final start = (0.15 + i * 0.13).clamp(0.0, 0.85);
    final raw = ((animation.value - start) / (1 - start)).clamp(0.0, 1.0);
    final t = Curves.easeOutBack.transform(raw);
    final fade = Curves.easeOut.transform(raw);

    const box = 74.0;
    final cx = center.dx + spec.offset.dx;
    final cy = center.dy + spec.offset.dy;
    // 20px upward rise that eases to 0 as the item settles.
    final rise = 20 * (1 - fade);

    return Positioned(
      left: cx - box / 2,
      top: cy - 27 + rise,
      width: box,
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: 0.8 + 0.2 * t, // 0.8 → 1
          alignment: Alignment.topCenter,
          child: _MenuButton(spec: spec, onTap: () => onSelect(spec.action)),
        ),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({required this.spec, required this.onTap});

  final _MenuSpec spec;
  final VoidCallback onTap;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
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
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: palette.isDark ? palette.bgElevated : Colors.white,
                shape: BoxShape.circle,
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
              child: Icon(
                widget.spec.icon,
                color: AppColors.primaryGreen,
                size: 24,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              widget.spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
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
