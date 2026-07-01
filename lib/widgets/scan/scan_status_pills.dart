import 'package:flutter/material.dart';

import '../../screens/scan/scan_theme.dart';

/// The stacked confirmation pills shown over the live preview once a document is
/// actually framed: a solid green "Document Detected" chip, with a light "Ready
/// to Scan" chip that grows in beneath it only once the document is held stable
/// ([showReady]). They mirror the trustworthy language of Adobe Scan / Microsoft
/// Lens. Purely informational; it never intercepts touches.
///
/// These pills are only ever mounted by the scanner in the [documentDetected] /
/// [readyToScan] states — never by default.
class ScanStatusPills extends StatelessWidget {
  const ScanStatusPills({super.key, this.showReady = false});

  /// Reveals the secondary "Ready to Scan" pill (document confirmed stable).
  final bool showReady;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Pill(label: 'Document Detected', filled: true),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: showReady
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: _Pill(label: 'Ready to Scan', filled: false),
                  )
                : const SizedBox(width: 0, height: 0),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.filled});

  /// Solid green (primary confirmation) vs. light surface (secondary status).
  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color bg = filled ? ScanColors.green : ScanColors.surface;
    final Color fg = filled ? Colors.white : ScanColors.textPrimary;
    final Color iconColor = filled ? Colors.white : ScanColors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: (filled ? ScanColors.green : Colors.black)
                .withValues(alpha: filled ? 0.35 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
