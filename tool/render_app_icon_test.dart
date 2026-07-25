// One-shot renderer for the launcher icon assets - run explicitly with:
//
//   flutter test tool/render_app_icon_test.dart
//   dart run flutter_launcher_icons
//
// Renders the login screen's InoLogo mark (white badge, brand-gradient shield,
// INO monogram) into assets/icon/*.png at 1024px. Lives under tool/ so a
// normal `flutter test` run never executes it (it writes into assets/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/theme/app_theme.dart';

const _canvas = 512.0; // logical; exported at pixelRatio 2 → 1024px

Future<void> _loadRealFonts() async {
  // MaterialIcons ships in the test asset bundle.
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();

  // Roboto lives in the Flutter SDK cache - load the weights the mark uses so
  // "INO" renders as real glyphs instead of the test-placeholder boxes.
  // (File names are lowercase: roboto-bold.ttf …)
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      // flutter test's dart lives at <root>/bin/cache/dart-sdk/bin/dart.exe.
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) {
    fail('material_fonts not found under $root - cannot render INO glyphs');
  }
  final roboto = FontLoader('Roboto');
  var found = 0;
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last.toLowerCase();
    if (name.startsWith('roboto-') && name.endsWith('.ttf')) {
      found++;
      roboto.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  expect(found, greaterThan(0), reason: 'no roboto-*.ttf in $dir');
  await roboto.load();
}

/// The InoLogo mark, re-composed for export: [scale] sizes the shield+text
/// relative to the canvas, [bg] fills the square (null = transparent).
Widget _mark({required double scale, Color? bg}) {
  final shield = _canvas * 0.74 * scale;
  return Container(
    width: _canvas,
    height: _canvas,
    color: bg,
    child: Stack(
      alignment: Alignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) =>
              AppColors.brandGradient.createShader(bounds),
          child: Icon(Icons.shield_rounded, size: shield, color: Colors.white),
        ),
        Text(
          'INO',
          style: TextStyle(
            fontFamily: 'Roboto',
            color: Colors.white,
            fontSize: _canvas * 0.17 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5 * (_canvas / 130) * scale,
          ),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('render launcher icon PNGs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(_canvas, _canvas));
    await tester.runAsync(_loadRealFonts);

    Future<void> render(Widget child, String path) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(_canvas, _canvas)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(key: key, child: child),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0); // → 1024px
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // Full icon: the login mark full-bleed on its white badge (the OS applies
    // the platform mask/corners itself). Scaled up so the shield nearly fills
    // the tile - at the mark's native 74% it read too small at launcher sizes.
    await render(
      _mark(scale: 1.35, bg: Colors.white),
      'assets/icon/ino_icon.png',
    );
    // Android adaptive pair: plain white background…
    await render(
      Container(width: _canvas, height: _canvas, color: Colors.white),
      'assets/icon/ino_icon_bg.png',
    );
    // …and the mark shrunk into the adaptive safe zone on transparency.
    // 0.88 × 0.74 ≈ 65% of the canvas - right at the ~66% safe circle; any
    // bigger and round-mask launchers start clipping the shield's shoulders.
    await render(_mark(scale: 0.88), 'assets/icon/ino_icon_fg.png');
  });
}
