import 'package:image_picker/image_picker.dart';

/// Picks an existing image from the device gallery to feed into the scan
/// pipeline. Thin wrapper over [image_picker] so the screen stays plugin-free.
class GalleryImportService {
  GalleryImportService._();
  static final GalleryImportService instance = GalleryImportService._();

  final ImagePicker _picker = ImagePicker();

  /// Opens the system gallery and returns the chosen image path, or `null` if
  /// the user dismissed the picker.
  Future<String?> pickImage() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    return file?.path;
  }

  /// Opens the device camera to capture a photo and returns its path, or `null`
  /// if the user backed out. Down-samples large captures a touch (quality 88,
  /// max 2600px) so the receipt scan stays fast without hurting legibility.
  Future<String?> captureFromCamera() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
      maxWidth: 2600,
      maxHeight: 2600,
    );
    return file?.path;
  }
}
