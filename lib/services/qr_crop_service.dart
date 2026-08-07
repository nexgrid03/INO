import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;

/// The result of pulling a QR out of a photo the user picked.
class CroppedQr {
  const CroppedQr({
    required this.bytes,
    required this.width,
    required this.height,
    this.payload,
  });

  /// PNG bytes of the crop. PNG, not JPEG: a QR is hard-edged black and white,
  /// exactly the case where JPEG ringing hurts and lossless costs little.
  final Uint8List bytes;

  final int width;
  final int height;

  /// What the code decoded to, or null when no code could be read and the image
  /// was returned uncropped.
  final String? payload;

  /// True when a QR was actually found and the image is a real crop rather than
  /// the original passed through.
  bool get isCropped => payload != null;
}

/// Finds the QR inside a photo and crops the photo down to it.
///
/// People photograph or screenshot their payment QR with a lot around it - the
/// app's chrome, a table, half a phone. Storing that is wasteful and it renders
/// as a tiny code in a big frame. ML Kit already reports a `boundingBox` for
/// every barcode it reads, so the crop is free: detect, expand the box by a
/// quiet-zone margin, cut.
///
/// Reuses the barcode scanner already in the build for QR scanning - no new
/// dependency.
///
/// **Never throws and never returns null for a real image.** If no QR can be
/// found the original image is returned re-encoded, because a user whose photo
/// didn't decode still expects their upload to appear.
class QrCropService {
  QrCropService._();
  static final QrCropService instance = QrCropService._();

  /// Extra margin around the detected code, as a fraction of the box's larger
  /// side. QR readers need a quiet zone; cropping flush to the modules makes a
  /// code noticeably harder for another phone to scan back off the screen.
  static const double _quietZone = 0.12;

  /// Cap on the stored crop's larger side. A QR carries a fixed, small amount
  /// of data - beyond this, pixels add file size and no scannability.
  static const int _maxSide = 900;

  /// Reads [path], crops to the QR if one is found, and returns PNG bytes.
  Future<CroppedQr?> cropFromFile(String path) async {
    Uint8List original;
    try {
      original = await File(path).readAsBytes();
    } catch (_) {
      return null;
    }

    // Decode the QR (and get its bounding box) off the file directly - ML Kit
    // handles orientation/EXIF itself on this path.
    Barcode? code;
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final codes = await scanner.processImage(InputImage.fromFilePath(path));
      if (codes.isNotEmpty) {
        // Largest box wins: a screenshot of a payment app can contain small
        // decorative codes besides the real one.
        codes.sort((a, b) => _area(b.boundingBox).compareTo(_area(a.boundingBox)));
        code = codes.first;
      }
    } catch (_) {
      // Detection failed - fall through and keep the original image.
    } finally {
      await scanner.close();
    }

    // The pixel work is pure CPU on a potentially large bitmap; keep it off the
    // UI isolate so the picker sheet doesn't hitch on dismissal.
    final box = code?.boundingBox;
    return compute(
      _cropWorker,
      _CropRequest(
        bytes: original,
        // Plain doubles, not the dart:ui Rect: only values guaranteed to be
        // sendable cross the isolate boundary.
        left: box?.left,
        top: box?.top,
        right: box?.right,
        bottom: box?.bottom,
        payload: code?.rawValue,
      ),
    );
  }

  static double _area(Rect r) => r.width * r.height;
}

class _CropRequest {
  const _CropRequest({
    required this.bytes,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.payload,
  });

  final Uint8List bytes;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final String? payload;

  bool get hasBox =>
      left != null && top != null && right != null && bottom != null;
}

/// Runs on a background isolate. Must be a top-level function.
CroppedQr? _cropWorker(_CropRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) return null;

  var out = decoded;
  var payload = req.payload;

  final boxW = req.hasBox ? req.right! - req.left! : 0.0;
  final boxH = req.hasBox ? req.bottom! - req.top! : 0.0;

  if (req.hasBox && boxW > 0 && boxH > 0) {
    final longest = boxW > boxH ? boxW : boxH;
    final margin = (longest * QrCropService._quietZone).round();

    // Clamp to the image; ML Kit can report a box that runs slightly past an
    // edge when the code is cut off, and copyCrop would throw on that.
    var left = (req.left!.round() - margin).clamp(0, decoded.width - 1);
    var top = (req.top!.round() - margin).clamp(0, decoded.height - 1);
    var right = (req.right!.round() + margin).clamp(left + 1, decoded.width);
    var bottom = (req.bottom!.round() + margin).clamp(top + 1, decoded.height);

    // Square it off around the centre so the stored QR isn't subtly stretched
    // by a non-square detection box.
    final side = (right - left) > (bottom - top) ? right - left : bottom - top;
    final cx = (left + right) ~/ 2;
    final cy = (top + bottom) ~/ 2;
    left = (cx - side ~/ 2).clamp(0, decoded.width - 1);
    top = (cy - side ~/ 2).clamp(0, decoded.height - 1);
    final w = side.clamp(1, decoded.width - left);
    final h = side.clamp(1, decoded.height - top);

    out = img.copyCrop(decoded, x: left, y: top, width: w, height: h);
  } else {
    // Nothing detected: keep the whole image so the upload still shows up.
    payload = null;
  }

  if (out.width > QrCropService._maxSide || out.height > QrCropService._maxSide) {
    final landscape = out.width >= out.height;
    out = img.copyResize(
      out,
      width: landscape ? QrCropService._maxSide : null,
      height: landscape ? null : QrCropService._maxSide,
      interpolation: img.Interpolation.average,
    );
  }

  return CroppedQr(
    bytes: Uint8List.fromList(img.encodePng(out)),
    width: out.width,
    height: out.height,
    payload: payload,
  );
}
