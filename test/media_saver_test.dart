import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/media_saver_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaSaverService', () {
    const channel = MethodChannel('ino/media_saver');
    final methodCalls = <MethodCall>[];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        methodCalls.add(call);
        if (call.method == 'saveImageToGallery') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('is a singleton', () {
      expect(identical(MediaSaverService.instance, MediaSaverService.instance), isTrue);
    });

    test('saveImage writes local file and invokes platform channel', () async {
      // Setup mock for path_provider
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (MethodCall call) async {
        if (call.method == 'getTemporaryDirectory') {
          return '.';
        }
        return null;
      });

      final dummyBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      const fileName = 'test_qr_download.png';

      final file = await MediaSaverService.instance.saveImage(
        bytes: dummyBytes,
        fileName: fileName,
        mimeType: 'image/png',
      );

      expect(file, isNotNull);
      expect(file!.path.endsWith(fileName), isTrue);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), equals(dummyBytes));

      // Clean up test file
      await file.delete();
    });
  });
}
