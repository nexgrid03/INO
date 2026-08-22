import 'package:flutter/widgets.dart';

/// Decode-size helpers for images that are painted much smaller than they are
/// stored.
///
/// **Why this exists.** `Image.file` / `Image.network` decode at the source
/// resolution unless told otherwise. A 12MP camera photo — which is exactly
/// what the scanner and the property picker produce — decodes to roughly
/// `4000 × 3000 × 4 bytes ≈ 48 MB` of RGBA, even when it is only ever painted
/// into a 48×48 avatar or list thumbnail.
///
/// Two things go wrong, and both of them read to the user as scroll jank:
///
///  * **The decode itself** is long enough to blow a frame, and it happens as
///    the tile scrolls into view.
///  * **The image cache thrashes.** Flutter's [ImageCache] holds ~100 MB, so
///    two or three full-resolution photos evict everything else — including
///    the images just above the fold. Scrolling back up re-decodes them, so
///    the stutter repeats every time the list moves.
///
/// Passing `cacheWidth` / `cacheHeight` makes the engine downsample *during*
/// decode, so the expensive full-size bitmap is never materialised at all.
/// A 48×48 thumbnail at 3x DPR costs ~83 KB instead of ~48 MB.
extension InoImageDecode on BuildContext {
  /// The physical pixel width to decode at, for something painted
  /// [logicalWidth] logical pixels wide in this context.
  ///
  /// Multiplying by the device pixel ratio keeps the image pin-sharp on
  /// high-DPI screens — this trades memory for nothing visible, not quality
  /// for memory. The ratio is clamped so a hypothetical 4x panel cannot ask
  /// for an unreasonable decode.
  int decodeWidthFor(double logicalWidth) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(this)?.clamp(1.0, 3.0) ?? 3.0;
    return (logicalWidth * dpr).ceil();
  }
}

/// Decode width for a square target of [logicalSize], usable where there is no
/// [BuildContext] handy. Assumes a 3x panel, which is the safe (sharpest)
/// end of the range for phones.
int decodeSizeFor(double logicalSize) => (logicalSize * 3).ceil();
