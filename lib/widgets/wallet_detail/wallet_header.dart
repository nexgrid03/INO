import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 1 — the compact Wallet header.
///
/// Deliberately *not* a large app bar: a single 44dp row holding Back, the
/// wallet title, and Search / Filter actions. All the chrome the user needs to
/// orient and act, none of the vertical weight — the document list starts as
/// high on the screen as possible.
class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.title,
    required this.onBack,
    required this.onSearch,
    required this.onFilter,
    this.onManageShares,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onFilter;

  /// Optional — opens the "Shared Links" manager. Shown as a QR action when set.
  final VoidCallback? onManageShares;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        _HeaderIcon(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: palette.textPrimary,
            ),
          ),
        ),
        _HeaderIcon(
          icon: Icons.search_rounded,
          tooltip: 'Search',
          onTap: onSearch,
        ),
        const SizedBox(width: 8),
        if (onManageShares != null) ...[
          _HeaderIcon(
            icon: Icons.qr_code_2_rounded,
            tooltip: 'Shared links',
            onTap: onManageShares!,
          ),
          const SizedBox(width: 8),
        ],
        _HeaderIcon(
          icon: Icons.tune_rounded,
          tooltip: 'Sort & filter',
          onTap: onFilter,
        ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 21, color: palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
