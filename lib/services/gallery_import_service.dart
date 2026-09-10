import 'package:image_picker/image_picker.dart';

/// Picks an existing image from the device gallery to feed into the scan
/// pipeline. Thin wrapper over [image_picker] so the screen stays plugin-free.
///
/// Gallery images are down-sampled to 2000px max dimension at quality 85 —
/// full-resolution gallery photos (8-20 MB) OOM on mid-range devices when
/// the scan pipeline decodes them on the UI isolate.
class GalleryImportService {
  GalleryImportService._();
  static final GalleryImportService instance = GalleryImportService._();

  final ImagePicker _picker = ImagePicker();

  /// Opens the system gallery and returns the chosen image path, or `null` if
  /// the user dismissed the picker.
  Future<String?> pickImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      return file?.path;
    } on Object catch (_) {
      return null;
    }
  }

  /// Opens the gallery for a MULTI-selection and returns the chosen images'
  /// paths in pick order, or an empty list if the user dismissed it.
  ///
  /// Same bounds as [pickImage]: a document is a handful of pages, and a
  /// selection of full-resolution gallery photos decoded at source size is what
  /// OOMs a mid-range phone before the pages are ever assembled.
  Future<List<String>> pickImages() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      return [for (final f in files) f.path];
    } on Object catch (_) {
      return const [];
    }
  }

  /// Opens the device camera to capture a photo and returns its path, or `null`
  /// if the user backed out. Down-samples large captures (quality 88,
  /// max 2600px) so the receipt scan stays fast without hurting legibility.
  Future<String?> captureFromCamera() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2600,
        maxHeight: 2600,
      );
      return file?.path;
    } on Object catch (_) {
      return null;
    }
  }
}
