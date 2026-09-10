import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// The INO floating bottom navigation dock - an opaque capsule that hovers over
/// the page, lifted by a brand glow, a cool ambient shadow and a tight contact
/// edge.
///
/// Five slots: Home · Vault · **+** · Alerts · Profile, sized per device by
/// [_DockMetrics] rather than baked to one handset.
///
/// Three pieces of motion, and none of them is decoration:
///  * the active destination is marked by a soft mountain crest that
///    **travels** between slots and **flattens** while in flight, rising again
///    as it lands ([InoNavMountainPainter]) - retargeting from wherever it
///    currently is, so a tap mid-flight redirects it instead of teleporting it;
///  * every item **dips** under a finger and springs back ([_DockTapScale]),
///    which is what stops the bar feeling dead in the hand;
///  * each side tab keeps its bespoke arrival - a bounce, a lift, a bell
///    wiggle, a fade+scale - layered on the glyph only, never on the layout.
///
/// The surface is deliberately **opaque, not blurred**. A [BackdropFilter] on a
/// bar that is pinned above a scrolling list costs a full backdrop pass on
/// every frame of every scroll, which is the most expensive thing this widget
/// could possibly do; the capsule and the shadows carry the depth instead.
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
    NavItem(
      'scan',
      Icons.document_scanner_rounded,
      Icons.document_scanner_rounded,
    ),
    NavItem(
      'alerts',
      Icons.notifications_rounded,
      Icons.notifications_none_rounded,
    ),
    NavItem('profile', Icons.person_rounded, Icons.person_outline_rounded),
  ];

  /// The dock's full height on this device, system inset included.
  ///
  /// The Scaffold sets `extendBody: true` so page content scrolls *behind* the
  /// dock. That means every scrollable owes its last item this much bottom
  /// padding, or the final row sits under the bar and cannot be read or tapped.
  ///
  /// Screens used to hard-code that clearance — 56 on Home, 108 on one wallet,
  /// 110 on two others — none of which matched the dock on any particular
  /// device, and all of which went stale the moment its geometry changed. Ask
  /// the dock instead: it is the only thing that knows.
  ///
  /// Add your own breathing room on top; this is the bar, not the gap above it.
  static double heightOf(BuildContext context) {
    final m = _DockMetrics.of(context);
    return m.topGap + m.barHeight + m.bottomGap;
  }

  /// Global notifier indicating whether the FAB quick menu is currently open.
  static final ValueNotifier<bool> isMenuOpenNotifier = ValueNotifier<bool>(
    false,
  );

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
    if (state != null &&
        (state._open || state._wheelOpen || isMenuOpenNotifier.value)) {
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
    with TickerProviderStateMixin {
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

  /// Drives the selection capsule as it travels between destinations.
  ///
  /// Separate from [_menu] on purpose: the pill must be able to fly while the
  /// "+" is mid-morph, and the two have very different settle curves.
  late final AnimationController _pill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Fractional slot the capsule currently occupies (2.4 = mid-flight).
  late Animation<double> _pillSlot = AlwaysStoppedAnimation<double>(
    widget.index.toDouble(),
  );

  @override
  void initState() {
    super.initState();
    InoBottomNav._activeState = this;
  }

  @override
  void didUpdateWidget(covariant InoBottomNav old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    // The centre "+" is never a resting destination, so it owns no slot —
    // leave the capsule parked and let its opacity fade it out instead of
    // sliding it somewhere the user never navigated to.
    if (widget.index == _kScanSlot) return;
    // Retarget from the CURRENT animated position, not the old index, so a tap
    // mid-flight redirects the capsule smoothly instead of teleporting it.
    _pillSlot =
        Tween<double>(
          begin: _pillSlot.value,
          end: widget.index.toDouble(),
        ).animate(
          CurvedAnimation(
            parent: _pill,
            // Long, soft tail — a selection *settling*, not a mechanical ease.
            curve: const Cubic(0.22, 1.0, 0.32, 1.0),
          ),
        );
    _pill.forward(from: 0);
  }

  /// 0 at rest, peaking at 1 mid-flight — drives the capsule's liquid stretch.
  double get _travel {
    if (!_pill.isAnimating) return 0;
    final t = _pill.value;
    return 4 * t * (1 - t);
  }

  @override
  void dispose() {
    if (InoBottomNav._activeState == this) {
      InoBottomNav._activeState = null;
    }
    // Null the handles as they are removed: an in-flight _closeMenu() /
    // _onHoldCancel() resumes after this and would otherwise call remove() a
    // second time on an entry that is no longer in any Overlay.
    _entry?.remove();
    _entry = null;
    _wheelEntry?.remove();
    _wheelEntry = null;
    _highlight.dispose();
    _pill.dispose();
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
      return box.localToGlobal(
        box.size.center(Offset.zero),
        ancestor: overlayBox,
      );
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
    debugPrint(
      '[FAB Menu] FAB hold-wheel opened (current tab: ${widget.index})',
    );
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
    debugPrint(
      '[FAB Menu] FAB hold-wheel closed (current tab: ${widget.index})',
    );
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
    debugPrint(
      '[FAB Menu] FAB hold-wheel cancelled (current tab: ${widget.index})',
    );
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
    final m = _DockMetrics.of(context);
    final hasSlot = widget.index != _kScanSlot;

    // Resolved here rather than inside the painter: the Aqua/Sky brand switch
    // is an InheritedWidget lookup, and a CustomPainter has no context.
    final crestFill = dark
        ? AppColors.primaryGreen.withValues(alpha: 0.22)
        : (InoStyle.isAqua(context)
              ? AppColors.aquaMist.withValues(alpha: 0.85)
              : const Color(0xFFE0F2FE));
    final crestBorder = dark
        ? AppColors.primaryGreen.withValues(alpha: 0.28)
        : const Color(0xFFBAE6FD);

    // Text scaling is clamped here and ONLY here: a phone set to the largest
    // font would otherwise blow five labels out of a 66px capsule. The rest of
    // the app honours the user's setting in full - this is chrome, and the
    // icons carry the meaning.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      // The dock repaints on every pill frame; the boundary keeps that off the
      // page scrolling behind it.
      child: RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            m.sideMargin,
            m.topGap,
            m.sideMargin,
            m.bottomGap,
          ),
          // Golden rule: the shadows live on the OUTER box. The clip on the
          // Container below would eat them.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(m.radius),
              boxShadow: [
                // Wide, faint brand glow - the premium lift.
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.16),
                  blurRadius: 40,
                  spreadRadius: -8,
                  offset: const Offset(0, 14),
                ),
                // Cool ambient elevation, deepened in dark so the dock still
                // lifts off the charcoal canvas.
                BoxShadow(
                  color: const Color(
                    0xFF0B1220,
                  ).withValues(alpha: dark ? 0.44 : 0.20),
                  blurRadius: 28,
                  spreadRadius: -10,
                  offset: const Offset(0, 12),
                ),
                // Tight contact edge that cuts the shape out of the background.
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.30 : 0.12),
                  blurRadius: 8,
                  spreadRadius: -4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            // Opaque surface rather than a translucent blur: it reads cleaner
            // over scrolling content, and it costs no BackdropFilter pass -
            // which is the single most expensive thing a bar pinned above a
            // scrolling list can do, on every frame of every scroll.
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: dark ? palette.surface : Colors.white,
                borderRadius: BorderRadius.circular(m.radius),
                border: Border.all(
                  color: dark
                      ? palette.border
                      : AppColors.primaryGreen.withValues(alpha: 0.10),
                ),
              ),
              child: SizedBox(
                height: m.barHeight,
                child: Stack(
                  // expand, so the item Row is handed the full bar height and
                  // its columns centre against the capsule instead of hugging
                  // the top.
                  fit: StackFit.expand,
                  children: [
                    // The travelling crest, painted UNDER the items.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: hasSlot ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          child: AnimatedBuilder(
                            animation: _pill,
                            builder: (context, _) => CustomPaint(
                              painter: InoNavMountainPainter(
                                slot: _pillSlot.value,
                                slotCount: InoBottomNav.tabs.length,
                                travel: _travel,
                                color: crestFill,
                                borderColor: crestBorder,
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
                            child: i == _kScanSlot
                                // Two keys, both needed. [_scanKey] on a
                                // wrapper is how _buttonCenter() finds where to
                                // anchor the quick menu; it used to sit on the
                                // button itself and lose to `quickAddKey`
                                // whenever the shell passed one — which is
                                // always — so the fan-out and the hold-wheel
                                // silently fell back to a guessed
                                // bottom-of-screen centre instead of the "+".
                                ? KeyedSubtree(
                                    key: _scanKey,
                                    child: _ScanButton(
                                      key: widget.quickAddKey,
                                      metrics: m,
                                      label: InoBottomNav.tabs[i].label(
                                        AppLocalizations.of(context),
                                      ),
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
                                    metrics: m,
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

/// The row slot the centre "+" occupies. It is never a resting destination.
const int _kScanSlot = 2;

/// Dock geometry, resolved per device instead of baked to one handset.
///
/// Two things break a bottom bar on hardware other than the one it was drawn
/// on: a fixed bar height plus a fixed margin stacked on the *whole* system
/// inset eats a chunk of a short screen, and fixed-size labels inside fixed
/// fifths clip on narrow ones (the Hindi and Telugu strings are the first to
/// go). Everything here scales off the real viewport, and the gap under the
/// bar distinguishes a gesture pill from an opaque 3-button nav bar -
/// mistaking the two is what makes a dock look sliced in half.
class _DockMetrics {
  const _DockMetrics({
    required this.barHeight,
    required this.sideMargin,
    required this.topGap,
    required this.bottomGap,
    required this.iconZone,
    required this.iconSize,
    required this.labelSize,
  });

  final double barHeight;
  final double sideMargin;
  final double topGap;
  final double bottomGap;

  /// Fixed icon band every item shares - the flat icons and the "+" gem alike -
  /// so every label sits on one baseline.
  final double iconZone;
  final double iconSize;
  final double labelSize;

  /// The dock is a capsule, so the radius is simply half the height.
  double get radius => barHeight / 2;

  factory _DockMetrics.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final inset = mq.padding.bottom;
    // 390 = the iPhone 14 / Pixel 8 class this was drawn on. 360dp Galaxy
    // A-series and 320dp compacts scale down; big phones barely move.
    final s = (size.width / 390).clamp(0.84, 1.05);
    // Short screens lose the most to a tall dock, so they get the compact bar.
    final short = size.height < 700;

    return _DockMetrics(
      barHeight: ((short ? 66.0 : 72.0) * s).clamp(64.0, 76.0),
      sideMargin: (size.width * 0.04).clamp(12.0, 18.0),
      topGap: short ? 4.0 : 6.0,
      bottomGap: inset >= 40
          ? inset + 4
          : (inset > 0 ? (inset * 0.55).clamp(8.0, 18.0) : 10.0),
      iconZone: ((short ? 36.0 : 40.0) * s).clamp(34.0, 42.0),
      iconSize: (23.0 * s).clamp(21.0, 25.0),
      labelSize: (11.0 * s).clamp(10.0, 12.0),
    );
  }
}

/// The soft mountain crest (WhatsApp style) that marks the active destination.
///
/// The shape itself is unchanged - a wide, rounded dome with long flares
/// blending back into the bar's baseline. What it gained is motion, and neither
/// half of it is decoration:
///
///   * it **travels** between slots rather than cutting, driven by a fractional
///     [slot] so a tap mid-flight redirects it instead of teleporting it, and
///   * its crest **flattens** while in flight and rises again as it lands - the
///     "liquid under weight" settle. That is what makes a crest read as one
///     body of liquid flowing across the bar instead of a shape being moved.
///
/// Drawn as a painter rather than an [AnimatedPositioned] so the whole thing is
/// a single cheap repaint per frame, with nothing relaying out underneath it.
class InoNavMountainPainter extends CustomPainter {
  const InoNavMountainPainter({
    required this.slot,
    required this.slotCount,
    required this.travel,
    required this.color,
    this.borderColor,
  });

  /// Fractional slot index the crest sits at (2.4 = mid-flight).
  final double slot;
  final int slotCount;

  /// 0 at rest, peaking at 1 mid-flight. Drives the flatten.
  final double travel;

  final Color color;
  final Color? borderColor;

  /// Traces the crest into [w] x [h], with the dome peaking at [topY].
  Path _crest(double w, double h, double topY) {
    final peakX = w / 2;
    final bottomY = h;
    return Path()
      ..moveTo(0, bottomY)
      // Left flare: a wide smooth entrance blending from baseline to flank.
      ..cubicTo(
        w * 0.30, bottomY,
        peakX - 32, bottomY * 0.44,
        peakX - 22, bottomY * 0.24,
      )
      // Wide, rounded dome crest.
      ..cubicTo(
        peakX - 12, topY,
        peakX + 12, topY,
        peakX + 22, bottomY * 0.24,
      )
      // Right flare: a wide smooth descent back to the baseline.
      ..cubicTo(
        peakX + 32, bottomY * 0.44,
        w * 0.70, bottomY,
        w, bottomY,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final itemWidth = size.width / slotCount;
    // The band is wider than its slot so the flares have room to blend out
    // before the neighbouring icons, and capped so a tablet's wide slots don't
    // stretch the dome into a plateau.
    final bandWidth = math.min(itemWidth + 38, 110.0);
    final cx = (slot + 0.5) * itemWidth;
    final h = size.height;

    // The crest sinks while travelling and rises back as it settles. Only the
    // dome moves: the flares stay pinned to the baseline, so the shape stays
    // seated on the bar instead of detaching from it.
    final topY = 4.0 + travel * h * 0.16;

    canvas.save();
    canvas.translate(cx - bandWidth / 2, 0);

    final path = _crest(bandWidth, h, topY);
    canvas.drawPath(
      Path.from(path)..close(),
      Paint()
        ..style = PaintingStyle.fill
        // Soft blended fill, so the crest fades into the bar rather than
        // stopping at a hard edge along its base.
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: color.a * 0.75)],
        ).createShader(Rect.fromLTWH(0, 0, bandWidth, h)),
    );

    if (borderColor != null) {
      // Stroked from the OPEN path: closing it would draw a line straight
      // across the base, which is the bar's own surface and must stay unmarked.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = borderColor!.withValues(alpha: 0.35),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(InoNavMountainPainter old) =>
      old.slot != slot ||
      old.travel != travel ||
      old.slotCount != slotCount ||
      old.color != color ||
      old.borderColor != borderColor;
}

/// The dip a dock item gives under a finger.
///
/// Tab items compress slightly on touch-down and spring back on release;
/// without it the bar looks right in a screenshot and feels dead in the hand.
/// [HitTestBehavior.opaque] so the whole column is the target, not just the
/// glyph.
class _DockTapScale extends StatefulWidget {
  const _DockTapScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_DockTapScale> createState() => _DockTapScaleState();
}

class _DockTapScaleState extends State<_DockTapScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// A dock label that shrinks rather than clips.
///
/// One fifth of a 320dp screen is ~57px, and the Hindi/Telugu strings do not
/// fit that at full size - an ellipsis there is exactly the half-cut text
/// narrow devices used to show. Scaling down inside the slot keeps every label
/// whole and centred at any width.
class _DockLabel extends StatelessWidget {
  const _DockLabel({
    required this.label,
    required this.color,
    required this.metrics,
    required this.selected,
  });

  final String label;
  final Color color;
  final _DockMetrics metrics;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps neighbouring labels from touching once they scale up to the slot.
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: metrics.labelSize,
            height: 1.15,
            letterSpacing: -0.1,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
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
    required this.metrics,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final _TabKind kind;
  final _DockMetrics metrics;
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
    final m = widget.metrics;

    final idle = palette.isDark
        ? palette.textPrimary.withValues(alpha: 0.62)
        : palette.textSecondary;
    final color = widget.selected ? AppColors.primaryGreen : idle;

    return _DockTapScale(
      onTap: widget.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // One shared icon zone (sized per device) so every item - the "+"
          // gem included - hangs off the same baseline and the labels never
          // drift. Icon and label together sit INSIDE the selection capsule at
          // every size this resolves to.
          SizedBox(
            height: m.iconZone,
            child: Center(
              // The signature motion rides on top of the steady state, so it
              // only ever animates the glyph - never the layout.
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => _decorate(child!, _c.value),
                child: AnimatedScale(
                  scale: widget.selected ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.selected ? 1.0 : 0.0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    builder: (context, sel, _) => Icon(
                      widget.selected
                          ? widget.item.active
                          : widget.item.inactive,
                      size: m.iconSize,
                      color: Color.lerp(idle, AppColors.primaryGreen, sel),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          _DockLabel(
            label: widget.item.label(l10n),
            color: color,
            metrics: m,
            selected: widget.selected,
          ),
        ],
      ),
    );
  }

  /// Applies the shared "pop" (1 -> 1.15 -> 1) plus this tab's signature
  /// motion. [t] runs 0->1 once on selection; every term is zero at both ends,
  /// so the glyph always lands exactly where the static layout put it.
  Widget _decorate(Widget child, double t) {
    if (t == 0 || t == 1) return child;
    // Bell-shaped 0->1->0 envelope for the there-and-back pop.
    final env = math.sin(t * math.pi);
    final pop = 1 + env * 0.15;

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

/// The centre "+": a CONTAINED brand gem - a gradient circle that fills the
/// shared icon zone, so it sits flush with the flat icons on every device
/// instead of being raised above the bar. Label and baseline match the other
/// items exactly.
///
/// It compresses on press and rotates 0 -> 135 degrees (+ becomes x) as either
/// quick-menu overlay opens. Tap toggles the fan-out; press-and-hold drives the
/// wheel via the four long-press callbacks.
class _ScanButton extends StatefulWidget {
  const _ScanButton({
    super.key,
    required this.metrics,
    required this.label,
    required this.progress,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldMove,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  final _DockMetrics metrics;
  final String label;
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
    final m = widget.metrics;
    final palette = AppPalette.of(context);
    // The gem fills the shared icon zone exactly, so it stays flush with the
    // flat icons at every size instead of out-growing the capsule.
    final gem = m.iconZone;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The hold-wheel gesture. The tap handlers below own plain taps; the
      // arena hands the pointer here once the long-press deadline passes.
      onLongPressStart: widget.onHoldStart,
      onLongPressMoveUpdate: widget.onHoldMove,
      onLongPressEnd: widget.onHoldEnd,
      onLongPressCancel: widget.onHoldCancel,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        // Deeper than a flat tab's dip: this is the dock's primary action.
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: m.iconZone,
              child: Center(
                child: Container(
                  width: gem,
                  height: gem,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primaryGreen,
                        AppColors.primaryGreen.withValues(alpha: 0.82),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                    // Tight brand glow, kept inside the bar so the gem never
                    // reads as "popping above" the dock.
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.38),
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: widget.progress,
                      builder: (context, child) => Transform.rotate(
                        // A single "+" that rotates 0 -> 135 degrees so it
                        // reads as an "x" once a quick menu is open.
                        angle: widget.progress.value * (3 * math.pi / 4),
                        child: child,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: m.iconSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            _DockLabel(
              label: widget.label,
              color: palette.isDark
                  ? palette.textPrimary.withValues(alpha: 0.62)
                  : palette.textSecondary,
              metrics: m,
              selected: false,
            ),
          ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: palette.isDark ? palette.bgElevated : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: palette.isDark ? 0.4 : 0.10,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 15,
                      color: AppColors.primaryGreen,
                    ),
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
                    : const [Shadow(color: Colors.white, blurRadius: 6)],
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
                        angles[i],
                        _InoBottomNavState._wheelRadius,
                      ),
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
                                      AppColors.primaryGreen.withValues(
                                        alpha: 0.06,
                                      ),
                                      Colors.white,
                                    )),
                        shape: BoxShape.circle,
                        border: hot
                            ? null
                            : Border.all(
                                color: AppColors.primaryGreen.withValues(
                                  alpha: 0.22,
                                ),
                                width: 1.4,
                              ),
                        boxShadow: [
                          BoxShadow(
                            color: hot
                                ? AppColors.primaryGreen.withValues(alpha: 0.45)
                                : Colors.black.withValues(
                                    alpha: palette.isDark ? 0.4 : 0.10,
                                  ),
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
