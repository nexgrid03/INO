import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/ino_back_button.dart';
import '../common/shiny_icon.dart';
import '../divine_glass/divine_glass.dart';
import '../pressable_scale.dart';

/// Section 1 - the compact Wallet header.
///
/// A single row: a circular Back button, a brand-gradient icon chip that
/// identifies the wallet, the wallet title (auto-shrinks to fit - never
/// ellipsised) and the wallet's contextual actions on the right. Search and
/// sort/filter no longer live here - they scroll with the page - so the header
/// stays light and the title always reads in full.
///
/// Under Launcher (Divine Glass), matches Figma Identity: centered teal title,
/// back left, more right — no icon chip beside the title.
class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.icon,
    this.accent,
    this.onManageShares,
    this.onAreaConverter,
    this.onEditName,
  });

  final String title;
  final VoidCallback onBack;

  /// The wallet's glyph, shown in a small brand-gradient chip beside the title.
  final IconData? icon;

  /// Wallet accent from Home My Vaults — keeps header chrome colour-matched.
  final Color? accent;

  /// Optional - opens the "Shared Links" manager (the QR / scan action).
  final VoidCallback? onManageShares;

  /// Optional - opens the Property Area Converter (only the Property wallet).
  final VoidCallback? onAreaConverter;

  /// Optional - edit the wallet name (custom wallets only).
  final VoidCallback? onEditName;

  @override
  Widget build(BuildContext context) {
    if (divineGlassEnabled(context)) {
      return _launcherHeader(context);
    }
    return _classicHeader(context);
  }

  Widget _launcherHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <Widget>[];
    if (onEditName != null) {
      actions.add(
        DivineGlassHeaderAction(
          icon: Icons.edit_outlined,
          tooltip: l10n.t('rename'),
          onTap: onEditName!,
        ),
      );
    }
    if (onAreaConverter != null) {
      actions.add(
        DivineGlassHeaderAction(
          icon: Icons.straighten_rounded,
          tooltip: l10n.t('areaConverter'),
          onTap: onAreaConverter!,
        ),
      );
    }
    if (onManageShares != null) {
      actions.add(
        DivineGlassHeaderAction(
          icon: Icons.qr_code_scanner_rounded,
          tooltip: l10n.t('sharedLinks'),
          onTap: onManageShares!,
        ),
      );
    }
    // Full-bleed frosted Top App Bar (Figma Identity Wallet), under status bar.
    return DivineGlassAppBar(
      title: title,
      onBack: onBack,
      actions: actions.isEmpty ? null : actions,
      centerTitle: false,
      includeStatusBar: true,
    );
  }

  Widget _classicHeader(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final chip = accent ?? AppColors.primaryGreen;
    return Row(
      children: [
        InoBackButton(size: 42, onTap: onBack),
        const SizedBox(width: 12),
        if (icon != null) ...[
          ShinyIcon(
            icon: icon!,
            color: chip,
            size: 40,
            iconSize: 21,
            radius: 13,
            style: ShinyIconStyle.filled,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
              if (onEditName != null) ...[
                const SizedBox(width: 8),
                PressableScale(
                  pressedScale: 0.88,
                  child: Tooltip(
                    message: l10n.t('rename'),
                    child: InkWell(
                      onTap: onEditName,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onAreaConverter != null) ...[
          _CircleIcon(
            icon: Icons.straighten_rounded,
            tooltip: l10n.t('areaConverter'),
            onTap: onAreaConverter!,
            accent: AppColors.primaryGreen,
          ),
          const SizedBox(width: 8),
        ],
        if (onManageShares != null)
          _CircleIcon(
            icon: Icons.qr_code_scanner_rounded,
            tooltip: l10n.t('sharedLinks'),
            onTap: onManageShares!,
            highlighted: true,
            accent: AppColors.primaryGreen,
          ),
      ],
    );
  }
}

/// A circular header control. [highlighted] gives it the teal-tinted primary
/// treatment (used for the scan/QR action so it stands out).
class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.highlighted = false,
    this.accent,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool highlighted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tint = accent ?? AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: highlighted
              ? tint.withValues(alpha: 0.12)
              : palette.surface,
          shape: CircleBorder(
            side: BorderSide(
              color: highlighted
                  ? tint.withValues(alpha: 0.35)
                  : palette.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                icon,
                size: 21,
                color: highlighted ? tint : palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
