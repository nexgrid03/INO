import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;

/// A user-friendly PDF import failure. The [message] is safe to show directly.
class PdfImportException implements Exception {
  const PdfImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The result of a successful PDF pick: the on-device file path plus the
/// original file name and size, so the caller can show it and upload it.
class PickedPdf {
  const PickedPdf({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final int sizeBytes;
}

/// Picks a PDF from device storage using the platform file picker (Storage
/// Access Framework on Android, the document picker on iOS) and validates it
/// before it ever enters the vault.
///
/// Validation covers the failure modes a real vault must handle:
///   • wrong type (not a `.pdf`),
///   • too large (over [maxBytes]),
///   • corrupted / not actually a PDF (missing the `%PDF-` signature),
///   • permission denied / picker unavailable.
///
/// On cancel it returns null; on any validation failure it throws a
/// [PdfImportException] with a message ready for the UI.
class PdfImportService {
  PdfImportService._();
  static final PdfImportService instance = PdfImportService._();

  /// 50 MB — generous for scans, small enough to keep uploads reliable.
  static const int maxBytes = 50 * 1024 * 1024;

  Future<PickedPdf?> pickPdf() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: false, // we stream the file from disk, not memory
        withReadStream: false,
      );
    } on PlatformException catch (e) {
      developer.log('file picker failed: $e', name: 'pdf');
      // The most common PlatformException here is a denied storage permission.
      final msg = e.message?.toLowerCase() ?? '';
      if (msg.contains('permission') || msg.contains('denied')) {
        throw const PdfImportException(
            'Storage permission is required to pick a PDF. Enable it in Settings.');
      }
      throw const PdfImportException(
          'Could not open the file picker. Please try again.');
    } catch (e) {
      developer.log('file picker error: $e', name: 'pdf');
      throw const PdfImportException(
          'Could not open the file picker. Please try again.');
    }

    if (result == null || result.files.isEmpty) {
      return null; // user cancelled
    }

    final picked = result.files.single;
    final path = picked.path;
    if (path == null || path.trim().isEmpty) {
      throw const PdfImportException(
          'Could not read the selected file. Please pick it again.');
    }

    // Type check (defensive — the picker is already filtered to .pdf).
    final ext = (picked.extension ?? path.split('.').last).toLowerCase();
    if (ext != 'pdf') {
      throw const PdfImportException('Please select a PDF file.');
    }

    final file = File(path);
    if (!file.existsSync()) {
      throw const PdfImportException(
          'The selected file is no longer available. Please pick it again.');
    }

    final size = picked.size > 0 ? picked.size : await file.length();
    if (size <= 0) {
      throw const PdfImportException('This PDF appears to be empty.');
    }
    if (size > maxBytes) {
      final mb = (size / (1024 * 1024)).toStringAsFixed(1);
      throw PdfImportException(
          'This PDF is too large to upload ($mb MB, max $_maxLabel).');
    }

    // Corruption check: a real PDF starts with the "%PDF-" signature.
    if (!await _looksLikePdf(file)) {
      throw const PdfImportException(
          'This file is not a valid PDF or may be corrupted.');
    }

    developer.log('picked PDF "${picked.name}" (${size}B) at $path',
        name: 'pdf');
    return PickedPdf(path: path, name: picked.name, sizeBytes: size);
  }

  static String get _maxLabel => '${(maxBytes / (1024 * 1024)).round()} MB';

  /// Reads the first bytes and checks for the `%PDF-` magic header.
  Future<bool> _looksLikePdf(File file) async {
    try {
      final head = await file.openRead(0, 5).first;
      if (head.length < 5) return false;
      // "%PDF-" == 0x25 0x50 0x44 0x46 0x2D
      return head[0] == 0x25 &&
          head[1] == 0x50 &&
          head[2] == 0x44 &&
          head[3] == 0x46 &&
          head[4] == 0x2D;
    } catch (_) {
      return false;
    }
  }
}
