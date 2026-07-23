import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 1 — the compact Wallet header.
///
/// A single row: a circular Back button, a brand-gradient icon chip that
/// identifies the wallet, the wallet title (auto-shrinks to fit — never
/// ellipsised) and the wallet's contextual actions on the right. Search and
/// sort/filter no longer live here — they scroll with the page — so the header
/// stays light and the title always reads in full.
class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.icon,
    this.onManageShares,
    this.onAreaConverter,
  });

  final String title;
  final VoidCallback onBack;

  /// The wallet's glyph, shown in a small brand-gradient chip beside the title.
  final IconData? icon;

  /// Optional — opens the "Shared Links" manager (the QR / scan action).
  final VoidCallback? onManageShares;

  /// Optional — opens the Property Area Converter (only the Property wallet).
  final VoidCallback? onAreaConverter;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        _CircleIcon(
          icon: Icons.arrow_back_rounded,
          tooltip: l10n.t('back'),
          onTap: onBack,
        ),
        const SizedBox(width: 12),
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(13),
              boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.28),
            ),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          // FittedBox → the title scales down a hair if a localised name is long,
          // so it always fits on one line with no trailing dots.
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
        const SizedBox(width: 8),
        if (onAreaConverter != null) ...[
          _CircleIcon(
            icon: Icons.straighten_rounded,
            tooltip: l10n.t('areaConverter'),
            onTap: onAreaConverter!,
          ),
          const SizedBox(width: 8),
        ],
        if (onManageShares != null)
          _CircleIcon(
            icon: Icons.qr_code_scanner_rounded,
            tooltip: l10n.t('sharedLinks'),
            onTap: onManageShares!,
            highlighted: true,
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: highlighted
              ? AppColors.primaryGreen.withValues(alpha: 0.12)
              : palette.surface,
          shape: CircleBorder(
            side: BorderSide(
              color: highlighted
                  ? AppColors.primaryGreen.withValues(alpha: 0.35)
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
                color: highlighted
                    ? AppColors.primaryGreen
                    : palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
