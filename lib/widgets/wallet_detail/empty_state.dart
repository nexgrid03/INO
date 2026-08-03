import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../common/shiny_icon.dart';
import '../divine_glass/divine_glass.dart';
import '../pressable_scale.dart';

/// Empty state shown when a wallet (or the active filter/search) yields no
/// records. Premium gradient illustration + a clear call to start the vault.
class WalletEmptyState extends StatelessWidget {
  const WalletEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onScan,
    required this.onUpload,
    required this.onCreate,
  });

  final String title;
  final String subtitle;
  final VoidCallback onScan;
  final VoidCallback onUpload;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final launcher = divineGlassEnabled(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          if (launcher)
            DivineGlassEmptyPanel(title: title, subtitle: subtitle)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              decoration: BoxDecoration(
                gradient: palette.cardGradient,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: palette.border),
                boxShadow: palette.cardShadow,
              ),
              child: Column(
                children: [
                   ShinyIcon(
                    icon: Icons.folder_open_rounded,
                    color: AppColors.primaryGreen,
                    size: 110,
                    iconSize: 52,
                    radius: 32,
                    style: ShinyIconStyle.filled,
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
            ),
          const SizedBox(height: 24),
          PressableScale(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.document_scanner_rounded, size: 19),
                label: Text(l10n.t('scanDocument'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.upload_file_rounded,
                  label: l10n.t('upload'),
                  onTap: onUpload,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: l10n.t('create'),
                  onTap: onCreate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = divineGlassEnabled(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
    if (launcher) {
      return PressableScale(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: LiquidGlass(
            borderRadius: BorderRadius.circular(999),
            blur: 10,
            frost: 0.95,
            padding: EdgeInsets.zero,
            child: child,
          ),
        ),
      );
    }
    return PressableScale(
      child: Material(
        color: palette.surface,
        shape:  StadiumBorder(
          side: BorderSide(color: AppColors.tealPale, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}
