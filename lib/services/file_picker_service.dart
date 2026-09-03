import 'package:file_picker/file_picker.dart';

/// Multi-file selection for the QR-share flow.
///
/// Wraps [FilePicker] with `allowMultiple: true` and a fixed allow-list
/// (PDF · images · common documents). The screen keeps the running selection in
/// a `List<PlatformFile>`; [mergeUnique] adds newly-picked files WITHOUT
/// dropping the ones already chosen.
class FilePickerService {
  FilePickerService._();
  static final FilePickerService instance = FilePickerService._();

  /// PDF, images and documents.
  static const List<String> allowedExtensions = [
    'pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic', 'doc', 'docx', 'txt',
  ];

  /// Opens the system picker allowing MULTIPLE selections. Returns the chosen
  /// files (empty if the user cancels). `withData: false` keeps large files as
  /// paths so bytes are only read later, off the UI thread, during upload.
  Future<List<PlatformFile>> pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    return result?.files ?? const <PlatformFile>[];
  }

  /// Merges [added] into [existing], de-duplicating by (name, size) so picking
  /// again appends rather than overwrites and never adds the same file twice.
  static List<PlatformFile> mergeUnique(
    List<PlatformFile> existing,
    List<PlatformFile> added,
  ) {
    final seen = {for (final f in existing) _key(f)};
    final merged = List<PlatformFile>.from(existing);
    for (final f in added) {
      if (seen.add(_key(f))) merged.add(f);
    }
    return merged;
  }

  static String _key(PlatformFile f) => '${f.name}:${f.size}';
}
