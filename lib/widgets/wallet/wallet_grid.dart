import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
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
  };
  final key = map[label];
  return key == null ? label : l10n.t(key);
}

/// The Wallet Hub launcher grid.
///
/// A soft, light-toned 2-column grid of all vaults. Each card wears its own
/// **light pastel accent** (a curated airy palette — no heavy saturated blocks),
/// with a bright icon chip, a gently drifting decorative blob and the wallet
/// name + item count. Cards are a fixed, compact height so the layout is steady
/// (no resizing/zooming) and all wallets fit on one screen. Cards stagger in and
/// squish on press; a single shared controller drifts the blobs so the grid
/// feels alive without a controller per card.
class WalletGrid extends StatefulWidget {
  const WalletGrid({super.key, required this.categories, this.onOpen});

  final List<WalletCategory> categories;
  final void Function(WalletCategory category)? onOpen;

  static const double _gap = 12;
  static const double _cardHeight = 122;

  /// Fallback accent for any wallet not in [_accents].
  static const Color uniformAccent = Color(0xFF5FCBBF);

  /// Each wallet wears its own light pastel accent. The accent drives the whole
  /// card — the soft fill wash, the border, the drifting blob and the icon —
  /// so a single colour per wallet keeps everything cohesive.
  ///
  /// Investment Wallet deliberately uses the Home page's "Reminders Today"
  /// coral (0xFFF5704A) — no pink.
  static const Map<String, Color> _accents = {
    'Identity Wallet': Color(0xFF2FB6A6), // teal
    'Document Wallet': Color(0xFF4383EA), // blue
    'Property Wallet': Color(0xFF9B6DE0), // purple (swapped with Health)
    'Insurance Wallet': Color(0xFFF5704A), // coral (swapped with Investment)
    'Health Wallet': Color(0xFF3CB59E), // teal-green (swapped with Property)
    'Investment Wallet': Color(0xFF37C08A), // green (swapped with Insurance)
    'Banking Wallet': Color(0xFF4E7FE0), // blue
    'Password Vault': Color(0xFFF2B33D), // amber
  };

  /// The pastel accent for a given wallet name (falls back to [uniformAccent]).
  static Color accentFor(String name) => _accents[name] ?? uniformAccent;

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
                    accent: WalletGrid.accentFor(widget.categories[i].name),
                    drift: _drift,
                    phase: i * 0.8,
                    onTap: () => widget.onOpen?.call(widget.categories[i]),
                  ),
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
  });

  final WalletCategory category;
  final Color accent;
  final Animation<double> drift;
  final double phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    // A soft, light wash of the card's own accent — premium and airy.
    final fill = Color.alphaBlend(
      accent.withValues(alpha: palette.isDark ? 0.18 : 0.10),
      palette.surface,
    );
    final badgeBg = palette.isDark
        ? accent.withValues(alpha: 0.24)
        : Colors.white;

    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative drifting blob — the "graphic" that gives each card
              // depth. Isolated in its own AnimatedBuilder so only it repaints.
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
                                color: accent,
                                size: 92,
                                opacity: 0.20,
                              ),
                            ),
                            Positioned(
                              bottom: -28 - t * 4,
                              left: -22,
                              child: _Blob(
                                color: accent,
                                size: 64,
                                opacity: 0.12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Card content.
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
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.22),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              category.icon,
                              color: accent,
                              size: 20,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_outward_rounded,
                            color: accent.withValues(alpha: 0.6),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
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
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
