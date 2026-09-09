import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Service that downloads / saves media files (such as exported QR codes)
/// directly to the user's mobile device (Gallery / Photos on Android & iOS),
/// as well as writing a local cached file for instant viewing via OpenFilex.
class MediaSaverService {
  MediaSaverService._();
  static final MediaSaverService instance = MediaSaverService._();

  static const MethodChannel _channel = MethodChannel('ino/media_saver');

  /// Saves image [bytes] to the mobile device's media storage (Gallery/Photos)
  /// and caches a local copy.
  ///
  /// Returns the saved local [File] if successful, or null on error.
  Future<File?> saveImage({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'image/png',
  }) async {
    try {
      // 1. Write to local storage first so we always have a valid file to open/view.
      final dir = await getTemporaryDirectory();
      final localFile = File('${dir.path}/$fileName');
      await localFile.writeAsBytes(bytes, flush: true);

      // 2. On Android & iOS, save directly to device Gallery / Photos via native platform channel.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final success = await _channel.invokeMethod<bool>(
            'saveImageToGallery',
            {
              'bytes': bytes,
              'fileName': fileName,
              'mimeType': mimeType,
            },
          );
          developer.log(
            'saveImageToGallery result: $success for $fileName',
            name: 'media_saver',
          );
        } on MissingPluginException {
          developer.log(
            'ino/media_saver channel not available on this platform',
            name: 'media_saver',
          );
        } catch (e, st) {
          developer.log(
            'Native saveImageToGallery failed: $e',
            name: 'media_saver',
            error: e,
            stackTrace: st,
          );
        }
      }

      return localFile;
    } catch (e, st) {
      developer.log(
        'saveImage failed: $e',
        name: 'media_saver',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
