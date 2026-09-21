import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const width = 1080;
  const height = 1920;
  final canvas = img.Image(width: width, height: height, numChannels: 4);

  // Soft aqua mist gradient matching app splash
  for (var y = 0; y < height; y++) {
    final t = y / (height - 1);
    final r = (t < 0.5 ? 248 + (234 - 248) * (t * 2) : 234 + (223 - 234) * ((t - 0.5) * 2)).round();
    final g = (t < 0.5 ? 255 + (249 - 255) * (t * 2) : 249 + (248 - 249) * ((t - 0.5) * 2)).round();
    final b = (t < 0.5 ? 255 + (249 - 255) * (t * 2) : 249 + (248 - 249) * ((t - 0.5) * 2)).round();
    for (var x = 0; x < width; x++) {
      canvas.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Load the shield artwork
  final shieldFile = File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png');
  if (shieldFile.existsSync()) {
    final shield = img.decodeImage(shieldFile.readAsBytesSync())!;
    final scaled = img.copyResize(shield, width: 440, height: 440, interpolation: img.Interpolation.cubic);
    final dstX = (width - 440) ~/ 2;
    final dstY = (height - 440) ~/ 2 - 80;
    img.compositeImage(canvas, scaled, dstX: dstX, dstY: dstY);
  }

  final outDir = Directory('store_assets/screenshots');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  File('store_assets/screenshots/00_splash_shield.png').writeAsBytesSync(img.encodePng(canvas));
  print('Successfully generated store_assets/screenshots/00_splash_shield.png (1080x1920)');
}
