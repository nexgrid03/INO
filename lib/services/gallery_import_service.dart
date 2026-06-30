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
}
