import 'package:flutter/material.dart';

import '../../models/wallet_detail_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_back_button.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';
import 'divine_glass.dart';

/// Frosted top app bar matching Figma Divine Glass
/// (`Header - Top App Bar`): opaque-enough frost, theme-aware title, glass
/// back. Safe for iOS notches and Android status bars — use via
/// [asPreferredSize] on [Scaffold.appBar] so body content never overlaps.
class DivineGlassAppBar extends StatelessWidget {
  const DivineGlassAppBar({
    super.key,
    required this.title,
    // Kept for API compatibility; headings are title-only.
    String? subtitle,
    this.onBack,
    this.trailing,
    this.centerTitle = true,
    this.includeStatusBar = false,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// Identity / wallet style centers the title; settings-style left-aligns
  /// next to the back control ([asPreferredSize] default).
  final bool centerTitle;

  /// When true, paints frost under the status bar.
  final bool includeStatusBar;

  static const double barHeight = 56;

  static double _contentHeight() => barHeight;

  /// Preferred-size wrapper for [Scaffold.appBar] — frost under status bar.
  static PreferredSizeWidget asPreferredSize(
    BuildContext context, {
    Key? key,
    required String title,
    // Kept for call-site compatibility; headings are title-only.
    String? subtitle,
    VoidCallback? onBack,
    Widget? trailing,
    List<Widget>? actions,
    bool centerTitle = false,
  }) {
    final top = MediaQuery.viewPaddingOf(context).top;
    Widget? trail = trailing;
    if (trail == null && actions != null && actions.isNotEmpty) {
      trail = actions.length == 1
          ? actions.first
          : Row(mainAxisSize: MainAxisSize.min, children: actions);
    }
    return PreferredSize(
      preferredSize: Size.fromHeight(_contentHeight() + top),
      child: DivineGlassAppBar(
        key: key,
        title: title,
        // Subtitles omitted — headings are title-only across the app.
        onBack: onBack,
        trailing: trail,
        centerTitle: centerTitle,
        includeStatusBar: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top =
        includeStatusBar ? MediaQuery.viewPaddingOf(context).top : 0.0;
    final canPop = Navigator.of(context).canPop();
    final showBack = onBack != null || canPop;
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    // Title-only — second-line subtitles are omitted across the app.
    const contentH = barHeight;

    // Title must stay readable on frost — never hardcode brand teal.
    final titleStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: centerTitle ? 18 : 17,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.35,
      height: 1.15,
    );

    final titleBlock = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centerTitle ? TextAlign.center : TextAlign.start,
      style: titleStyle,
    );

    return Material(
      // Solid base so scroll content never shows through the bar (overlap look).
      color: dark
          ? palette.surface.withValues(alpha: 0.94)
          : Colors.white.withValues(alpha: 0.88),
      elevation: 0,
      child: LiquidGlass(
        borderRadius: BorderRadius.zero,
        blur: 20,
        frost: dark ? 0.85 : 0.75,
        tint: dark ? palette.surface : Colors.white,
        shadow: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: top),
            Container(
              height: contentH,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.10)
                        : palette.border,
                    width: 1,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: showBack
                        ? InoBackButton(
                            size: 40,
                            onTap: onBack ??
                                () => Navigator.of(context).maybePop(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (!centerTitle) const SizedBox(width: 6),
                  Expanded(child: titleBlock),
                  SizedBox(
                    width: trailing == null ? 44 : null,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing ?? const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inset frosted header strip for screens that keep back + title in the body
/// (modules). Prefer [DivineGlassAppBar.asPreferredSize] on Scaffold when
/// possible so body never overlaps the bar.
class DivineGlassHeaderBar extends StatelessWidget {
  const DivineGlassHeaderBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    return Material(
      color: dark
          ? palette.surface.withValues(alpha: 0.94)
          : Colors.white.withValues(alpha: 0.88),
      elevation: 0,
      child: LiquidGlass(
        borderRadius: BorderRadius.zero,
        blur: 20,
        frost: dark ? 0.85 : 0.75,
        tint: dark ? palette.surface : Colors.white,
        shadow: false,
        padding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : palette.border,
                width: 1,
              ),
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Circular glass header action (filter / more).
class DivineGlassHeaderAction extends StatelessWidget {
  const DivineGlassHeaderAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = PressableScale(
      pressedScale: 0.92,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass(
          circle: true,
          blur: 12,
          frost: 0.9,
          shadow: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 18,
              color: AppPalette.of(context).textPrimary,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Status pill: VALID / EXPIRING SOON / EXPIRED / SHARED (Figma Identity).
class DivineGlassStatusChip extends StatelessWidget {
  const DivineGlassStatusChip({
    super.key,
    required this.status,
    this.label,
  });

  final DocumentStatus status;
  final String? label;

  factory DivineGlassStatusChip.fromStatus(DocumentStatus status) {
    return DivineGlassStatusChip(status: status);
  }

  String get _figmaLabel {
    switch (status) {
      case DocumentStatus.active:
        return 'VALID';
      case DocumentStatus.expiringSoon:
        return 'EXPIRING SOON';
      case DocumentStatus.expired:
        return 'EXPIRED';
      case DocumentStatus.shared:
        return 'SHARED';
      case DocumentStatus.archived:
        return 'ARCHIVED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (status) {
      case DocumentStatus.active:
        bg = const Color(0xFF22C55E).withValues(alpha: 0.1);
        fg = const Color(0xFF15803D);
      case DocumentStatus.expiringSoon:
        bg = const Color(0xFFEAB308).withValues(alpha: 0.1);
        fg = const Color(0xFFA16207);
      case DocumentStatus.expired:
        bg = AppColors.critical.withValues(alpha: 0.1);
        fg = AppColors.critical;
      case DocumentStatus.shared:
        bg = AppColors.lightBlue.withValues(alpha: 0.12);
        fg = AppColors.lightBlue;
      case DocumentStatus.archived:
        bg = const Color(0xFF94A3B8).withValues(alpha: 0.15);
        fg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? _figmaLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: fg,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Round icon disc used on Identity document cards.
class DivineGlassRoundIcon extends StatelessWidget {
  const DivineGlassRoundIcon({
    super.key,
    required this.icon,
    required this.accent,
    this.size = 48,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color accent;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: accent, size: iconSize),
    );
  }
}

/// Uppercase micro-label + value used in Identity card footers.
class DivineGlassMetaCell extends StatelessWidget {
  const DivineGlassMetaCell({
    super.key,
    required this.label,
    required this.value,
    this.alignEnd = false,
    this.valueColor,
    this.leading,
  });

  final String label;
  final String value;
  final bool alignEnd;
  final Color? valueColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label.toUpperCase(),
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: palette.textFaint,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                value,
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: valueColor ?? palette.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Figma Identity document card: glass surface, round icon, status chip, meta row.
class DivineGlassDocumentCard extends StatelessWidget {
  const DivineGlassDocumentCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.status,
    required this.leftMeta,
    required this.rightMeta,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final DocumentStatus status;
  final DivineGlassMetaCell leftMeta;
  final Widget rightMeta;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DivineGlassCard(
      radius: 16,
      blur: 10,
      padding: const EdgeInsets.all(17),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DivineGlassRoundIcon(icon: icon, accent: accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: palette.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else
                DivineGlassStatusChip.fromStatus(status),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftMeta),
              const SizedBox(width: 8),
              Expanded(child: rightMeta),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact glass list row (title · subtitle · chevron) for hubs / Family Vaults.
class DivineGlassListRow extends StatelessWidget {
  const DivineGlassListRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DivineGlassCard(
      radius: 16,
      blur: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          DivineGlassIconChip(icon: icon, accent: accent, size: 46, iconSize: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textFaint,
                size: 22,
              ),
        ],
      ),
    );
  }
}

/// Hero counts strip for wallet hubs under Launcher.
class DivineGlassHeroStrip extends StatelessWidget {
  const DivineGlassHeroStrip({
    super.key,
    required this.items,
  });

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DivineGlassCard(
      radius: 18,
      blur: 16,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 28,
                color: palette.border,
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    items[i].value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty-state glass panel (illustration + copy); actions stay outside.
class DivineGlassEmptyPanel extends StatelessWidget {
  const DivineGlassEmptyPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.folder_open_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DivineGlassCard(
      radius: 28,
      blur: 18,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Column(
        children: [
          DivineGlassRoundIcon(
            icon: icon,
            accent: AppColors.primaryGreen,
            size: 96,
            iconSize: 44,
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Square glass filter / tune button beside search (Figma Identity).
class DivineGlassFilterButton extends StatelessWidget {
  const DivineGlassFilterButton({
    super.key,
    required this.onTap,
    this.icon = Icons.tune_rounded,
  });

  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.94,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(12),
          blur: 6,
          frost: 1.05,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 18, color: AppColors.primaryGreen),
          ),
        ),
      ),
    );
  }
}

/// Section spacing helper for Divine Glass hubs.
class DivineGlassSection extends StatelessWidget {
  const DivineGlassSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screen,
      0,
      AppSpacing.screen,
      AppSpacing.md,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}
