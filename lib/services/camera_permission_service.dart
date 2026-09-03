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

  /// Gallery import no longer needs a media permission, so this always reports
  /// [CameraAccess.granted] and never shows a prompt.
  ///
  /// Why: [GalleryImportService] picks images through `image_picker`, which on
  /// Android 13+ uses the system Photo Picker and on older versions uses
  /// ACTION_GET_CONTENT. Both hand back a content URI the user chose
  /// explicitly, so neither needs READ_MEDIA_IMAGES or READ_EXTERNAL_STORAGE.
  ///
  /// Declaring READ_MEDIA_IMAGES for a one-off import is also a Google Play
  /// policy problem: the Photo and Video Permissions policy requires apps with
  /// occasional access needs to use the Photo Picker and NOT declare the broad
  /// permission. It has been removed from AndroidManifest.xml (along with the
  /// READ_MEDIA_VIDEO / READ_MEDIA_AUDIO entries the open_filex plugin used to
  /// merge in), so requesting it here would now return "denied" and would
  /// wrongly block the picker from ever opening.
  ///
  /// On iOS the picker likewise runs out-of-process and needs no entitlement.
  /// Kept as a method rather than deleted so the call sites keep their shape;
  /// their denial branches are now unreachable.
  Future<CameraAccess> requestPhotos() async => CameraAccess.granted;

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
