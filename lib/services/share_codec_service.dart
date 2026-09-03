import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// Encodes/decodes the share deep link and, crucially, rasterises the QR code
/// on a BACKGROUND ISOLATE.
///
/// Why an isolate: building the QR matrix and painting it to a PNG is pure CPU
/// work. Doing it on the UI thread is exactly what produced "Skipped frames" /
/// "Davey!" jank and the follow-on ANR. [generateQrPng] runs entirely inside
/// [Isolate.run], so the main thread stays free and the UI can show a spinner.
class ShareCodecService {
  ShareCodecService._();

  static const String scheme = 'ino';
  static const String host = 'share';

  static final Random _rng = Random.secure();

  /// A URL-safe, unguessable share token (192 bits of entropy).
  static String generateToken() {
    final bytes = List<int>.generate(24, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// The deep link embedded in the QR, e.g. `ino://share/<token>`.
  static String buildShareUri(String token) => '$scheme://$host/$token';

  /// Extracts a token from a scanned string. Accepts the full `ino://share/…`
  /// deep link or a bare token, and rejects anything else.
  static String? parseToken(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == scheme && uri.host == host) {
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
        return uri.pathSegments.first;
      }
    }
    if (RegExp(r'^[A-Za-z0-9_-]{16,}$').hasMatch(value)) return value;
    return null;
  }

  /// Renders [data] to a PNG QR code on a background isolate.
  static Future<Uint8List> generateQrPng(
    String data, {
    int moduleSize = 12,
    int quietZone = 4,
  }) {
    return Isolate.run(() => _renderQrPng(data, moduleSize, quietZone));
  }

  /// Pure, isolate-safe rasteriser (no `dart:ui`) — only the `qr` and `image`
  /// packages, both pure Dart.
  static Uint8List _renderQrPng(String data, int moduleSize, int quietZone) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(code);
    final count = qrImage.moduleCount;
    final dimension = (count + quietZone * 2) * moduleSize;

    final canvas = img.Image(width: dimension, height: dimension);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    final black = img.ColorRgb8(0, 0, 0);

    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (qrImage.isDark(row, col)) {
          final x = (col + quietZone) * moduleSize;
          final y = (row + quietZone) * moduleSize;
          img.fillRect(
            canvas,
            x1: x,
            y1: y,
            x2: x + moduleSize - 1,
            y2: y + moduleSize - 1,
            color: black,
          );
        }
      }
    }
    return Uint8List.fromList(img.encodePng(canvas));
  }
}
