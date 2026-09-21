import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final iconFile = File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png');
  if (!iconFile.existsSync()) {
    print('Error: Icon file not found');
    return;
  }

  final iconImage = img.decodeImage(iconFile.readAsBytesSync())!;
  final resizedIcon = img.copyResize(iconImage, width: 512, height: 512, interpolation: img.Interpolation.cubic);
  
  final storeDir = Directory('store_assets');
  if (!storeDir.existsSync()) {
    storeDir.createSync(recursive: true);
  }

  File('store_assets/app_icon_512x512.png').writeAsBytesSync(img.encodePng(resizedIcon));
  print('Successfully saved 512x512 icon to store_assets/app_icon_512x512.png');

  // Also create a 1024x500 Feature Graphic
  // Gradient background: from #0284C7 to #0F172A
  final fg = img.Image(width: 1024, height: 500, numChannels: 4);
  for (var y = 0; y < 500; y++) {
    for (var x = 0; x < 1024; x++) {
      final t = (x + y) / (1024 + 500);
      final r = (15 + (2 - 15) * (1 - t)).round().clamp(0, 255);
      final g = (23 + (132 - 23) * (1 - t)).round().clamp(0, 255);
      final b = (42 + (199 - 42) * (1 - t)).round().clamp(0, 255);
      fg.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Draw the icon onto the center/left of feature graphic
  final scaledLogo = img.copyResize(iconImage, width: 280, height: 280, interpolation: img.Interpolation.cubic);
  img.compositeImage(fg, scaledLogo, dstX: 372, dstY: 110);

  File('store_assets/feature_graphic_1024x500.png').writeAsBytesSync(img.encodePng(fg));
  print('Successfully saved Feature Graphic to store_assets/feature_graphic_1024x500.png');

  final ssDir = Directory('store_assets/screenshots');
  if (ssDir.existsSync()) {
    for (final file in ssDir.listSync().whereType<File>()) {
      final decoded = img.decodeImage(file.readAsBytesSync());
      if (decoded != null) {
        print('Screenshot ${file.uri.pathSegments.last}: ${decoded.width}x${decoded.height}');
      }
    }
  }
}
