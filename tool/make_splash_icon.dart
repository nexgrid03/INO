// Derives the splash-screen mark from the adaptive-icon foreground:
//
//   assets/icon/ino_icon_fg.png  (transparent, big safe-zone padding)
//     → assets/icon/ino_icon_splash.png  (transparent, tightly cropped)
//
// The launcher icon (ino_icon.png) has an opaque background baked in, so it
// can't sit on the splash's gradient without showing a white box. The fg
// variant is transparent but padded for the Android adaptive-icon safe zone -
// this script crops it to the artwork's alpha bounding box (kept square,
// plus a small margin) so the splash can size it predictably.
//
// Run from the project root:  dart run tool/make_splash_icon.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  const srcPath = 'assets/icon/ino_icon_fg.png';
  const outPath = 'assets/icon/ino_icon_splash.png';

  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('Run from the project root ($srcPath not found).');
    exit(1);
  }

  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $srcPath');
    exit(1);
  }

  // Alpha bounding box of the artwork.
  var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
  for (final p in src) {
    if (p.a > 0) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  if (maxX < 0) {
    stderr.writeln('$srcPath is fully transparent - nothing to crop.');
    exit(1);
  }

  // Keep the crop square (centred on the artwork) so the splash box scales
  // the mark predictably, and add a 4% margin so anti-aliased edges and the
  // glow never clip.
  final w = maxX - minX + 1, h = maxY - minY + 1;
  final side = math.max(w, h);
  final margin = (side * 0.04).round();
  final full = side + 2 * margin;
  final cx = (minX + maxX) ~/ 2, cy = (minY + maxY) ~/ 2;
  final x0 = (cx - full ~/ 2).clamp(0, src.width - 1);
  final y0 = (cy - full ~/ 2).clamp(0, src.height - 1);
  final cw = math.min(full, src.width - x0);
  final ch = math.min(full, src.height - y0);

  final out = img.copyCrop(src, x: x0, y: y0, width: cw, height: ch);
  File(outPath).writeAsBytesSync(img.encodePng(out));
  stdout.writeln(
      'wrote $outPath (${out.width}x${out.height}, from alpha bbox ${w}x$h)');
}
