import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/document_share.dart';
import '../repositories/share_repository.dart';
import '../services/file_picker_service.dart';
import '../services/share_codec_service.dart';

/// Where the share flow is: choosing files, working (upload + QR raster), done,
/// or failed.
enum ShareStage { selecting, uploading, generating, ready, error }

/// Drives the QR-share screen. Holds the running multi-file selection and,
/// on generate, uploads the files, records the share, and rasterises the QR
/// off the main isolate — surfacing a [stage] the UI turns into a spinner so
/// the thread never blocks.
class ShareController extends ChangeNotifier {
  ShareController(this._repo);
  ShareController._default() : _repo = ShareRepository.instance;
  static final ShareController instance = ShareController._default();

  final ShareRepository _repo;

  final List<PlatformFile> _selected = [];
  List<PlatformFile> get selected => List.unmodifiable(_selected);

  ShareStage _stage = ShareStage.selecting;
  ShareStage get stage => _stage;

  String? _error;
  String? get error => _error;

  DocumentShare? _share;
  DocumentShare? get share => _share;

  Uint8List? _qrPng;
  Uint8List? get qrPng => _qrPng;

  bool get canGenerate =>
      _selected.isNotEmpty && _stage != ShareStage.uploading &&
      _stage != ShareStage.generating;

  int get totalBytes => _selected.fold(0, (sum, f) => sum + f.size);

  /// Opens the multi-select picker and APPENDS the result (no overwrite).
  Future<void> addFiles() async {
    final picked = await FilePickerService.instance.pickDocuments();
    if (picked.isEmpty) return;
    final before = _selected.length;
    final merged = FilePickerService.mergeUnique(_selected, picked);
    _selected
      ..clear()
      ..addAll(merged);
    if (_selected.length != before) {
      _stage = ShareStage.selecting;
      notifyListeners();
    }
  }

  void removeAt(int index) {
    if (index < 0 || index >= _selected.length) return;
    _selected.removeAt(index);
    notifyListeners();
  }

  void reset() {
    _selected.clear();
    _share = null;
    _qrPng = null;
    _error = null;
    _stage = ShareStage.selecting;
    notifyListeners();
  }

  /// Uploads the selection, records the share, and builds the QR — each heavy
  /// step off the UI thread (network I/O is async; the QR raster runs in an
  /// isolate). Safe to call only when [canGenerate].
  Future<void> generate({required String title}) async {
    if (_selected.isEmpty) return;
    _error = null;
    _setStage(ShareStage.uploading);
    try {
      final share = await _repo.createShare(
        title: title,
        files: List<PlatformFile>.from(_selected),
      );
      _share = share;

      _setStage(ShareStage.generating);
      _qrPng = await ShareCodecService.generateQrPng(
        ShareCodecService.buildShareUri(share.token),
      );

      _setStage(ShareStage.ready);
    } catch (e) {
      _error = 'Could not create the share. $e';
      _setStage(ShareStage.error);
    }
  }

  void _setStage(ShareStage stage) {
    _stage = stage;
    notifyListeners();
  }
}
