// Generates the INO launcher icons: the lowercase "ino" wordmark in brand
// Rama Blue (#30ACB3) on the soft teal-mist gradient used by the splash.
//
// Outputs (1024×1024, consumed by the flutter_launcher_icons config):
//   assets/icon/ino_icon.png     — full icon (gradient + wordmark)
//   assets/icon/ino_icon_bg.png  — adaptive background (gradient only)
//   assets/icon/ino_icon_fg.png  — adaptive foreground (wordmark, transparent)
//
// Run:  dart run tool/generate_icons.dart
// Then: dart run flutter_launcher_icons
//
// The wordmark is rasterised from the same 182×110 design space as the splash
// painter (lib/screens/splash/splash_screen.dart) via signed-distance fields,
// so the icon and the animated splash mark are pixel-for-pixel the same brand.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int _size = 1024;

// Brand teal #30ACB3.
const int _tealR = 0x30, _tealG = 0xAC, _tealB = 0xB3;

// Rama Blue gradient stops (top → mid → bottom).
const _gradTop = (0xF8, 0xFF, 0xFF);
const _gradMid = (0xEA, 0xF9, 0xF9);
const _gradBottom = (0xDF, 0xF8, 0xF8);

// --- Wordmark geometry (identical to the splash painter design space) -------
const double _halfW = 6.5; // stroke width 13
// i
const double _iX = 16, _iStemTopY = 42, _baseY = 88;
const double _iDotY = 24, _iDotR = 7;
// n
const double _nLeftX = 46, _nRightX = 88, _nTopY = 59, _nArchR = 21;
const double _nArchCX = 67;
// o
const double _oCX = 143, _oCY = 63, _oR = 25;

// Wordmark bounding box in design units (ink extents incl. stroke).
const double _bbMinX = _iX - _halfW; // 9.5
const double _bbMaxX = _oCX + _oR + _halfW; // 174.5
const double _bbMinY = _iDotY - _iDotR; // 17
const double _bbMaxY = _baseY + _halfW; // 94.5

double _sdSegment(double px, double py, double ax, double ay, double bx,
    double by) {
  final abx = bx - ax, aby = by - ay;
  final apx = px - ax, apy = py - ay;
  final t = ((apx * abx + apy * aby) / (abx * abx + aby * aby)).clamp(0.0, 1.0);
  final cx = ax + abx * t, cy = ay + aby * t;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

double _dist(double px, double py, double cx, double cy) =>
    math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));

/// Signed distance (design units) from a point to the OUTSIDE of the "ino"
/// ink: <= 0 means inside a stroke.
double _wordmarkDistance(double x, double y) {
  var d = double.infinity;

  // i stem + dot
  d = math.min(d, _sdSegment(x, y, _iX, _baseY, _iX, _iStemTopY) - _halfW);
  d = math.min(d, _dist(x, y, _iX, _iDotY) - _iDotR);

  // n: two stems + upper arch ring
  d = math.min(d, _sdSegment(x, y, _nLeftX, _baseY, _nLeftX, _nTopY) - _halfW);
  d = math.min(
      d, _sdSegment(x, y, _nRightX, _baseY, _nRightX, _nTopY) - _halfW);
  if (y <= _nTopY) {
    d = math.min(d, (_dist(x, y, _nArchCX, _nTopY) - _nArchR).abs() - _halfW);
  }

  // o: full ring
  d = math.min(d, (_dist(x, y, _oCX, _oCY) - _oR).abs() - _halfW);

  return d;
}

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

img.Image _render({required bool background, required double wordmarkWidth}) {
  final image = img.Image(width: _size, height: _size, numChannels: 4);

  // Scale + centring so the wordmark bbox sits centred at [wordmarkWidth] px.
  final s = wordmarkWidth / (_bbMaxX - _bbMinX);
  final offX = (_size - (_bbMaxX - _bbMinX) * s) / 2 - _bbMinX * s;
  final offY = (_size - (_bbMaxY - _bbMinY) * s) / 2 - _bbMinY * s;

  for (var y = 0; y < _size; y++) {
    final (bgR, bgG, bgB) = _gradientAt(y);
    for (var x = 0; x < _size; x++) {
      // Wordmark coverage with ~1px anti-aliasing (distance scaled to px).
      var coverage = 0.0;
      if (wordmarkWidth > 0) {
        final dPx = _wordmarkDistance((x - offX) / s, (y - offY) / s) * s;
        coverage = (0.5 - dPx).clamp(0.0, 1.0);
      }

      if (background) {
        final r = (bgR + (_tealR - bgR) * coverage).round();
        final g = (bgG + (_tealG - bgG) * coverage).round();
        final b = (bgB + (_tealB - bgB) * coverage).round();
        image.setPixelRgba(x, y, r, g, b, 255);
      } else {
        image.setPixelRgba(
            x, y, _tealR, _tealG, _tealB, (coverage * 255).round());
      }
    }
  }
  return image;
}

void main() {
  final outDir = Directory('assets/icon');
  if (!outDir.existsSync()) {
    stderr.writeln('Run from the project root (assets/icon not found).');
    exit(1);
  }

  void save(String name, img.Image image) {
    final path = 'assets/icon/$name';
    File(path).writeAsBytesSync(img.encodePng(image));
    stdout.writeln('wrote $path');
  }

  // Full icon: gradient + wordmark at 72% width.
  save('ino_icon.png', _render(background: true, wordmarkWidth: 740));
  // Adaptive background: gradient only.
  save('ino_icon_bg.png', _render(background: true, wordmarkWidth: 0));
  // Adaptive foreground: wordmark only, ~53% width (inside the 66% safe zone).
  save('ino_icon_fg.png', _render(background: false, wordmarkWidth: 540));

  stdout.writeln('done — now run: dart run flutter_launcher_icons');
}
