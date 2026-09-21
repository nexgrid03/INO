import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const srcPath = r'C:\Users\Lenovo\.gemini\antigravity-ide\brain\4fa6511a-b8e9-4f07-a2c1-2775c991f2c3\.user_uploaded\media_1789197375386.jpg';
  final file = File(srcPath);
  if (!file.existsSync()) {
    print('Source not found');
    return;
  }

  final image = img.decodeImage(file.readAsBytesSync())!;
  print('Original image: ${image.width}x${image.height}');

  // Resize to 1080x1920 or 1080x2400 (Google Play requires 9:16 aspect ratio or between 320px and 3840px)
  // Let's create a 1080x1920 version and 1080x2400 version
  final resized1920 = img.copyResize(image, width: 1080, height: 1920, interpolation: img.Interpolation.cubic);
  File('store_assets/screenshots/04_reminders.png').writeAsBytesSync(img.encodePng(resized1920));
  print('Successfully saved to store_assets/screenshots/04_reminders.png (1080x1920)');

  // Also save a 1080x2400 version as 04_reminders_2400.png
  final resized2400 = img.copyResize(image, width: 1080, height: 2400, interpolation: img.Interpolation.cubic);
  File('store_assets/screenshots/04_reminders_2400.png').writeAsBytesSync(img.encodePng(resized2400));
  print('Successfully saved to store_assets/screenshots/04_reminders_2400.png (1080x2400)');
}
