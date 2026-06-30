import 'package:permission_handler/permission_handler.dart';

/// Normalised camera-permission outcome the scanner UI can switch on.
enum CameraAccess { granted, denied, permanentlyDenied, restricted }

/// Thin wrapper around [permission_handler] for the scanner's camera +
/// photo-library needs. Keeps the plugin out of the widget layer so the screen
/// reasons about a small, testable enum instead of raw [PermissionStatus].
class CameraPermissionService {
  CameraPermissionService._();
  static final CameraPermissionService instance = CameraPermissionService._();

  /// Requests camera access at runtime, returning the resulting access level.
  Future<CameraAccess> requestCamera() async =>
      _map(await Permission.camera.request());

  /// Reads the current camera access without prompting (used on resume).
  Future<CameraAccess> cameraStatus() async =>
      _map(await Permission.camera.status);

  /// Requests photo-library access (gallery import). On Android 13+ this maps to
  /// READ_MEDIA_IMAGES, on older versions to storage.
  Future<CameraAccess> requestPhotos() async =>
      _map(await Permission.photos.request());

  /// Opens the OS app-settings page so the user can re-grant a permission that
  /// was permanently denied. Recheck [cameraStatus] after returning.
  Future<bool> openSettings() => openAppSettings();

  CameraAccess _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return CameraAccess.granted;
    if (s.isPermanentlyDenied) return CameraAccess.permanentlyDenied;
    if (s.isRestricted) return CameraAccess.restricted;
    return CameraAccess.denied;
  }
}
