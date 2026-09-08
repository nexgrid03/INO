import 'dart:io' show File;

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

/// The largest single dimension a decoded image may have, in physical pixels.
///
/// **This is not a memory budget — it is a hard GPU limit, and exceeding it
/// fails silently.** An image wider or taller than the device's maximum texture
/// size cannot be uploaded to the GPU, so Flutter paints *nothing*: no
/// exception, no `errorBuilder`, no log. The viewer shows its chrome over an
/// empty black canvas and looks, to the user, like a document that did not
/// load.
///
/// That is exactly what a gallery photo does here. A 50MP phone camera produces
/// an 8160×6120 JPEG; every Android GPU still in the field caps a single
/// texture at 4096 or 8192, and 4096 is the floor. Decoding within that bound
/// is what makes a full-resolution photo displayable at all.
const int kMaxTextureDimension = 4096;

/// Decode bounds for a full-screen, zoomable image viewer.
///
/// Wide enough to stay sharp when the user pinches in (roughly 2x the screen's
/// physical width), and never past [kMaxTextureDimension] — which is the part
/// that decides whether the image appears at all.
///
/// Use it as a bounding box with `ResizeImagePolicy.fit`, not as an exact size:
/// passing a width and height to the codec independently stretches the image
/// to those literal dimensions.
int zoomableDecodeCap(BuildContext context) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context)?.clamp(1.0, 3.0) ?? 3.0;
  final widthPx = MediaQuery.sizeOf(context).width * dpr;
  final target = (widthPx * 2).ceil();
  return target < kMaxTextureDimension ? target : kMaxTextureDimension;
}

/// A network image decoded within [zoomableDecodeCap], aspect ratio preserved.
///
/// `ResizeImagePolicy.fit` is load-bearing: with the default policy the width
/// and height are treated as the exact output size and a portrait photo comes
/// out stretched. `allowUpscaling: false` keeps a small image at its own
/// resolution instead of blowing it up to the cap.
ImageProvider zoomableNetworkImage(BuildContext context, String url) {
  final cap = zoomableDecodeCap(context);
  return ResizeImage(
    NetworkImage(url),
    width: cap,
    height: cap,
    policy: ResizeImagePolicy.fit,
    allowUpscaling: false,
  );
}

/// [zoomableNetworkImage] for a file already on disk.
ImageProvider zoomableFileImage(BuildContext context, File file) {
  final cap = zoomableDecodeCap(context);
  return ResizeImage(
    FileImage(file),
    width: cap,
    height: cap,
    policy: ResizeImagePolicy.fit,
    allowUpscaling: false,
  );
}
