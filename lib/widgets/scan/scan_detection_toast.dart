import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/scan/scan_theme.dart';

/// A small, premium success toast shown *transiently* the moment a document is
/// first detected — a green checkmark + "Document Detected" on a floating green
/// card. It's mounted only briefly (the scanner fades it out after ~1.5s) and
/// sits near the top of the viewport so it never blocks the document itself.
///
/// The card is intentionally compact and self-contained; the caller controls
/// its lifetime and fade via an [AnimatedSwitcher].
class ScanSuccessToast extends StatelessWidget {
  const ScanSuccessToast({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: ScanColors.green,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: ScanColors.green.withValues(alpha: 0.40),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context).t('documentDetected'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A subtle, glassy guidance chip shown at the bottom of the viewport — "Hold
/// steady to capture" once a document locks in, or a quiet "Searching…" while
/// framing. Tints green when [positive] so the user always knows the state.
/// Purely informational; never intercepts touches.
class ScanHintPill extends StatelessWidget {
  const ScanHintPill({
    super.key,
    required this.icon,
    required this.label,
    this.positive = false,
  });

  final IconData icon;
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final accent = positive ? ScanColors.green : Colors.white;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: positive
              ? ScanColors.green.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: positive
                ? ScanColors.green
                : Colors.white.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
