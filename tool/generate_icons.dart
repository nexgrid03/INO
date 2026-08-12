// Builds launcher icons that match the splash: soft mist gradient + the
// existing INO shield wordmark (assets/icon/ino_icon.png artwork).
//
// Run:  dart run tool/generate_icons.dart
// Then: dart run flutter_launcher_icons

import 'dart:io';

import 'package:image/image.dart' as img;

const int _size = 1024;

// Splash-matched mist gradient (top → mid → bottom).
const _gradTop = (0xF8, 0xFF, 0xFF);
const _gradMid = (0xEA, 0xF9, 0xF9);
const _gradBottom = (0xDF, 0xF8, 0xF8);

(int, int, int) _gradientAt(int y) {
  final t = y / (_size - 1);
  (int, int, int) lerp((int, int, int) a, (int, int, int) b, double f) => (
        (a.$1 + (b.$1 - a.$1) * f).round(),
        (a.$2 + (b.$2 - a.$2) * f).round(),
        (a.$3 + (b.$3 - a.$3) * f).round(),
      );
  return t < 0.5
      ? lerp(_gradTop, _gradMid, t * 2)
      : lerp(_gradMid, _gradBottom, (t - 0.5) * 2);
}

img.Image _mistBg() {
  final image = img.Image(width: _size, height: _size, numChannels: 4);
  for (var y = 0; y < _size; y++) {
    final (r, g, b) = _gradientAt(y);
    for (var x = 0; x < _size; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}

/// Finds the opaque / non-white content bbox so we can lift the shield off a
/// white or transparent canvas.
({int minX, int minY, int maxX, int maxY}) _contentBBox(img.Image src) {
  var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final a = p.a.toInt();
      if (a < 12) continue;
      // Skip near-white background pixels from the legacy flat icon.
      final nearWhite = p.r.toInt() > 245 && p.g.toInt() > 245 && p.b.toInt() > 245;
      if (nearWhite) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) {
    stderr.writeln('No shield content found in source icon.');
    exit(1);
  }
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

img.Image _extractShield(img.Image src) {
  final box = _contentBBox(src);
  final w = box.maxX - box.minX + 1;
  final h = box.maxY - box.minY + 1;
  final side = w > h ? w : h;
  final out = img.Image(width: side, height: side, numChannels: 4);
  // Clear transparent.
  for (final p in out) {
    p.r = 0;
    p.g = 0;
    p.b = 0;
    p.a = 0;
  }
  final ox = (side - w) ~/ 2;
  final oy = (side - h) ~/ 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(box.minX + x, box.minY + y);
      final a = p.a.toInt();
      final nearWhite =
          p.r.toInt() > 245 && p.g.toInt() > 245 && p.b.toInt() > 245;
      if (a < 12 || nearWhite) continue;
      out.setPixelRgba(
        ox + x,
        oy + y,
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        a,
      );
    }
  }
  return out;
}

void _compositeCentered(img.Image dst, img.Image shield, {required int side}) {
  final resized = img.copyResize(
    shield,
    width: side,
    height: side,
    interpolation: img.Interpolation.average,
  );
  final ox = (_size - side) ~/ 2;
  final oy = (_size - side) ~/ 2;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final sp = resized.getPixel(x, y);
      final a = sp.a.toInt() / 255.0;
      if (a <= 0.01) continue;
      final dx = ox + x;
      final dy = oy + y;
      if (dx < 0 || dy < 0 || dx >= _size || dy >= _size) continue;
      final dp = dst.getPixel(dx, dy);
      final r = (dp.r.toInt() * (1 - a) + sp.r.toInt() * a).round();
      final g = (dp.g.toInt() * (1 - a) + sp.g.toInt() * a).round();
      final b = (dp.b.toInt() * (1 - a) + sp.b.toInt() * a).round();
      final outA = (dp.a.toInt() + ((255 - dp.a.toInt()) * a)).round();
      dst.setPixelRgba(dx, dy, r, g, b, outA);
    }
  }
}

void main() {
  // Prefer a dedicated source so re-runs don't eat their own output.
  final candidates = [
    'tool/ino_icon_source.png',
    'assets/icon/ino_icon.png',
  ];
  File? srcFile;
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      srcFile = f;
      break;
    }
  }
  if (srcFile == null) {
    stderr.writeln('No shield source found.');
    exit(1);
  }

  final decoded = img.decodePng(srcFile.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode ${srcFile.path}');
    exit(1);
  }

  // Cache a clean transparent shield once so later runs stay stable.
  final shield = _extractShield(decoded);
  final sourcePath = 'tool/ino_icon_source.png';
  if (!File(sourcePath).existsSync()) {
    File(sourcePath).writeAsBytesSync(img.encodePng(shield));
    stdout.writeln('cached $sourcePath');
  }

  void save(String name, img.Image image) {
    final path = 'assets/icon/$name';
    File(path).writeAsBytesSync(img.encodePng(image));
    stdout.writeln('wrote $path');
  }

  // Full icon: mist + shield (splash-like).
  final full = _mistBg();
  _compositeCentered(full, shield, side: 780);
  save('ino_icon.png', full);

  // Adaptive background: mist only.
  save('ino_icon_bg.png', _mistBg());

  // Adaptive foreground: shield on transparent, inside safe zone.
  final fg = img.Image(width: _size, height: _size, numChannels: 4);
  for (final p in fg) {
    p.r = 0;
    p.g = 0;
    p.b = 0;
    p.a = 0;
  }
  _compositeCentered(fg, shield, side: 680);
  save('ino_icon_fg.png', fg);

  stdout.writeln('done - now run: dart run flutter_launcher_icons');
}
