import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../common/shiny_border.dart';
import '../dashboard/fade_slide_in.dart';
import '../pressable_scale.dart';

/// Maps a wallet name to its localized display name (the underlying name stays
/// English so it keeps working as a data key).
String localizedWalletName(AppLocalizations l10n, String name) {
  const map = {
    'Identity Wallet': 'identityWallet',
    'Document Wallet': 'documentWallet',
    'Property Wallet': 'propertyWallet',
    'Insurance Wallet': 'insuranceWallet',
    'Health Wallet': 'healthWallet',
    'Investment Wallet': 'investmentWallet',
    'Banking Wallet': 'bankingWallet',
    'Password Vault': 'passwordVault',
  };
  final key = map[name];
  return key == null ? name : l10n.t(key);
}

/// Maps a wallet metric label (e.g. "documents") to its localized form.
String localizedMetricLabel(AppLocalizations l10n, String label) {
  const map = {
    'documents': 'metricDocuments',
    'files': 'metricFiles',
    'properties': 'metricProperties',
    'policies': 'metricPolicies',
    'records': 'metricRecords',
    'holdings': 'metricHoldings',
    'accounts': 'metricAccounts',
    'passwords': 'metricPasswords',
    'cards': 'metricCards',
  };
  final key = map[label];
  return key == null ? label : l10n.t(key);
}

/// The Wallet Hub launcher grid.
///
/// A soft, light-toned 2-column grid of all vaults. Each card wears its own
/// **light pastel accent** (a curated airy palette - no heavy saturated blocks),
/// with a bright icon chip, a gently drifting decorative blob and the wallet
/// name + item count. Cards are a fixed, compact height so the layout is steady
/// (no resizing/zooming) and all wallets fit on one screen. Cards stagger in and
/// squish on press; a single shared controller drifts the blobs so the grid
/// feels alive without a controller per card.
class WalletGrid extends StatefulWidget {
  const WalletGrid({
    super.key,
    required this.categories,
    this.onOpen,
    this.onAdd,
    this.onLongPress,
  });

  final List<WalletCategory> categories;
  final void Function(WalletCategory category)? onOpen;

  /// When set, a dashed "New Wallet" tile is appended after the last wallet.
  final VoidCallback? onAdd;

  /// Long-press on a wallet card. The hub uses it to offer "delete" on the
  /// user's own wallets (the grid itself doesn't know which those are).
  final void Function(WalletCategory category)? onLongPress;

  static const double _gap = 12;
  static const double _cardHeight = 122;

  /// Fallback accent for any wallet not in [_accents].
  static const Color uniformAccent = Color(0xFF0EA5E9);

  /// Each wallet wears its own light pastel accent. The accent drives the whole
  /// card - the soft fill wash, the border, the drifting blob and the icon -
  /// so a single colour per wallet keeps everything cohesive.
  ///
  /// Investment Wallet deliberately uses the Home page's "Reminders Today"
  /// coral (0xFFF5704A) - no pink.
  static const Map<String, Color> _accents = {
    'Identity Wallet': Color(0xFF0EA5E9), // brand sky blue
    'Document Wallet': Color(0xFF4383EA), // blue
    'Property Wallet': Color(0xFF9B6DE0), // purple (swapped with Health)
    'Insurance Wallet': Color(0xFFF5704A), // coral (swapped with Investment)
    'Health Wallet': Color(0xFF22C55E), // mint green (swapped with Property)
    'Investment Wallet': Color(0xFF10B981), // green (swapped with Insurance)
    'Banking Wallet': Color(0xFF4E7FE0), // blue
    'Password Vault': Color(0xFFF2B33D), // amber
  };

  /// The pastel accent for a built-in wallet name (falls back to
  /// [uniformAccent]). Custom wallets carry their own accent - use
  /// [accentForCategory].
  static Color accentFor(String name) => _accents[name] ?? uniformAccent;

  /// The accent a card should wear: the curated one for a built-in wallet, or
  /// the colour the user picked when they created their own.
  static Color accentForCategory(WalletCategory category) =>
      _accents[category.name] ??
      (category.gradient.isEmpty ? uniformAccent : category.gradient.first);

  @override
  State<WalletGrid> createState() => _WalletGridState();
}

class _WalletGridState extends State<WalletGrid>
    with SingleTickerProviderStateMixin {
  // One slow, shared loop drifts every card's decorative blob. Muted
  // automatically while the Wallet tab is off-stage in the shell's IndexedStack.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 640 ? 3 : 2;
        final cardW =
            (constraints.maxWidth - WalletGrid._gap * (cols - 1)) / cols;
        return Wrap(
          spacing: WalletGrid._gap,
          runSpacing: WalletGrid._gap,
          children: [
            for (var i = 0; i < widget.categories.length; i++)
              SizedBox(
                width: cardW,
                height: WalletGrid._cardHeight,
                child: FadeSlideIn(
                  delay: Duration(milliseconds: (i * 45).clamp(0, 360)),
                  offset: 14,
                  child: _WalletCard(
                    category: widget.categories[i],
                    accent:
                        WalletGrid.accentForCategory(widget.categories[i]),
                    drift: _drift,
                    phase: i * 0.8,
                    onTap: () => widget.onOpen?.call(widget.categories[i]),
                    onLongPress: widget.onLongPress == null
                        ? null
                        : () => widget.onLongPress!(widget.categories[i]),
                  ),
                ),
              ),
            // "New Wallet" - always the last tile, so adding a vault is exactly
            // as reachable as opening one.
            if (widget.onAdd != null)
              SizedBox(
                width: cardW,
                height: WalletGrid._cardHeight,
                child: FadeSlideIn(
                  delay: Duration(
                    milliseconds: (widget.categories.length * 45).clamp(0, 360),
                  ),
                  offset: 14,
                  child: _AddWalletCard(onTap: widget.onAdd!),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.category,
    required this.accent,
    required this.drift,
    required this.phase,
    required this.onTap,
    this.onLongPress,
  });

  final WalletCategory category;
  final Color accent;
  final Animation<double> drift;
  final double phase;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final themeStyle = InoStyle.of(context);
    final bold = themeStyle == ThemeStyle.bold;
    final soft = themeStyle == ThemeStyle.soft;

    // Frosted glass cards: accent lives on the icon chip and whisper blobs.
    // Bold keeps its flooded-card look.
    final fill = bold
        ? InoStyle.boldFill(accent)
        : (palette.isDark
              ? Color.alphaBlend(
                  accent.withValues(alpha: 0.10),
                  palette.surface,
                )
              : palette.surface);
    // Hairline glass edge in classic/soft; bold keeps its heavier accent edge.
    final edge = bold ? InoStyle.boldBorder(accent) : accent;
    final titleColor = bold ? Colors.white : palette.textPrimary;
    final metricColor = bold
        ? InoStyle.boldTextSecondary
        : palette.textSecondary;

    final content = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: drift,
                builder: (context, _) {
                  final t = math.sin(drift.value * math.pi * 2 + phase);
                  return Stack(
                    children: [
                      Positioned(
                        top: -24 + t * 5,
                        right: -20,
                        child: _Blob(
                          color: bold ? Colors.white : accent,
                          size: 92,
                          opacity: bold ? 0.20 : 0.10,
                        ),
                      ),
                      Positioned(
                        bottom: -28 - t * 4,
                        left: -22,
                        child: _Blob(
                          color: bold ? Colors.white : accent,
                          size: 64,
                          opacity: bold ? 0.12 : 0.06,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    bold
                        ? SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              category.icon,
                              color: Colors.white,
                              size: 30,
                            ),
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                alpha: palette.isDark ? 0.22 : 0.14,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Icon(
                              category.icon,
                              color: accent,
                              size: 22,
                            ),
                          ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_outward_rounded,
                      color: bold
                          ? Colors.white.withValues(alpha: 0.85)
                          : accent.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  localizedWalletName(l10n, category.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${category.metric} ${localizedMetricLabel(l10n, category.metricLabel)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: metricColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final surface = bold
        ? ShinyBorder(
            radius: 20,
            width: 2.5,
            enabled: soft,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: edge,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.24),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: content,
            ),
          )
        : LiquidGlass(
            borderRadius: BorderRadius.circular(20),
            blur: 16,
            frost: palette.isDark ? 1.1 : 0.72,
            padding: EdgeInsets.zero,
            child: SizedBox.expand(child: content),
          );

    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: surface,
      ),
    );
  }
}

/// The trailing "New Wallet" tile - same footprint as a wallet card but drawn
/// as an empty slot: a dashed brand edge over a faint wash, with a plus chip.
/// Reads as "there's room for one more" rather than as another vault.
class _AddWalletCard extends StatelessWidget {
  const _AddWalletCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final bold = InoStyle.of(context) == ThemeStyle.bold;
    const accent = AppColors.primaryGreen;
    final edge = bold ? InoStyle.boldBorder(accent) : accent;
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: edge.withValues(alpha: 0.75),
            radius: 20,
          ),
          child: LiquidGlass(
            borderRadius: BorderRadius.circular(20),
            blur: 14,
            frost: palette.isDark ? 1.05 : 0.65,
            shadow: false,
            tint: accent.withValues(alpha: 0.06),
            padding: EdgeInsets.zero,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.25,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: InoStyle.gradient(
                        context,
                        AppColors.brandGradient,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppShadows.glow(accent, opacity: 0.26),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.t('newWallet'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.t('addWalletHint'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
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

/// Draws the rounded dashed edge of the "New Wallet" slot.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(1),
      );
    const dash = 7.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end =
            distance + dash < metric.length ? distance + dash : metric.length;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// A soft radial-gradient circle used as decorative depth inside a card.
class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
