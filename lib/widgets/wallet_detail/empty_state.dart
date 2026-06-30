import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          // Gradient illustration badge.
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.32),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Icon(Icons.folder_open_rounded,
                color: Colors.white, size: 52),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
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
          const SizedBox(height: 24),
          // Primary action.
          PressableScale(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.document_scanner_rounded, size: 19),
                label: const Text('Scan Document',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                  label: 'Upload',
                  onTap: onUpload,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Create',
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
    return PressableScale(
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
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
          ),
        ),
      ),
    );
  }
}
