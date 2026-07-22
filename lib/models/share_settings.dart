import 'package:flutter/material.dart';

import 'document_share.dart' show ShareDuration;

export 'document_share.dart' show ShareDuration, ShareDurationX;

/// How the shared copy is rendered.
enum ShareColorMode { original, blackWhite, grayscale, compressedPdf }

extension ShareColorModeX on ShareColorMode {
  String get label {
    switch (this) {
      case ShareColorMode.original:
        return 'Original Color';
      case ShareColorMode.blackWhite:
        return 'Black & White';
      case ShareColorMode.grayscale:
        return 'Grayscale';
      case ShareColorMode.compressedPdf:
        return 'Compressed PDF';
    }
  }

  IconData get icon {
    switch (this) {
      case ShareColorMode.original:
        return Icons.palette_rounded;
      case ShareColorMode.blackWhite:
        return Icons.contrast_rounded;
      case ShareColorMode.grayscale:
        return Icons.gradient_rounded;
      case ShareColorMode.compressedPdf:
        return Icons.picture_as_pdf_rounded;
    }
  }
}

/// The options chosen on the "Share Settings" screen before a share copy is
/// produced: just the copy style and how long the link stays valid. UI-agnostic
/// value object.
class ShareSettings {
  const ShareSettings({
    this.colorMode = ShareColorMode.original,
    this.duration = ShareDuration.twentyFourHours,
  });

  final ShareColorMode colorMode;
  final ShareDuration duration;

  /// True when the source image pixels must be transformed at all (i.e. anything
  /// other than the original) — so a processed copy is required rather than a
  /// plain copy of the original.
  bool get requiresImageProcessing => colorMode != ShareColorMode.original;

  bool get wrapsInPdf => colorMode == ShareColorMode.compressedPdf;

  ShareSettings copyWith({
    ShareColorMode? colorMode,
    ShareDuration? duration,
  }) {
    return ShareSettings(
      colorMode: colorMode ?? this.colorMode,
      duration: duration ?? this.duration,
    );
  }
}
