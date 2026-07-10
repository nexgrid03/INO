import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/share_origin.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException, AuthException;

import '../../data/wallet_detail_repository.dart';
import '../../models/wallet_detail_models.dart';
import '../../repositories/document_repository.dart';
import '../../services/auth_service.dart';
import '../../services/document_file_service.dart';
import '../../services/document_protection_store.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// What changed while viewing a document, returned to the wallet list on pop.
class DocumentViewerResult {
  const DocumentViewerResult({this.updated, this.removed = false});

  /// The document with its latest fields (favorite / name / status).
  final DocumentRecord? updated;

  /// True if the document left this wallet (deleted or moved).
  final bool removed;
}

enum _FileKind { image, pdf, text, other }

/// Every distinct failure mode when resolving a document's file — each mapped to
/// its own icon/title/message so the user (and the logs) know exactly what went
/// wrong, instead of a blanket "network" error.
enum _LoadError {
  none,
  invalidPath,
  missing,
  bucketMissing,
  permission,
  signedUrlFailed,
  network,
  timeout,
  authExpired,
  plugin,
  unknown,
}

/// A production document viewer.
///
/// Resolves the *real* stored file from Supabase Storage. Images load via a
/// **signed URL** (`createSignedUrl`) + `Image.network` — the correct path for a
/// private bucket, with no dependency on local file plugins — and the URL is
/// auto-regenerated once if it fails/expires. PDFs / office files are cached
/// locally and opened with the system app. Every step is logged (under the
/// `viewer` log name) and, in debug builds, the exact exception is shown on the
/// error screen so failures are diagnosable rather than generic.
///
/// Security: only ever pushed *after* biometric unlock for protected documents,
/// and the file is fetched in [initState] — never before authentication.
class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.record,
    required this.walletName,
    required this.accent,
    this.protected = false,
  });

  final DocumentRecord record;
  final String walletName;
  final List<Color> accent;
  final bool protected;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final TransformationController _tc = TransformationController();
  TapDownDetails? _doubleTapDetails;

  late DocumentRecord _record = widget.record;
  late bool _protected = widget.protected;

  bool _loading = true;
  _LoadError _error = _LoadError.none;
  String? _debugDetail; // exact exception, shown in debug builds

  _FileKind _kind = _FileKind.other;
  String? _storagePath; // the normalised path actually used against Storage
  String? _imageUrl; // signed URL for images
  int _imageAttempt = 0; // auto-regen counter
  File? _file; // local cache (non-images + share/download)
  int _fileSize = 0;
  String? _textContent;
  int _rotation = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  bool get _isImageView =>
      _kind == _FileKind.image && _imageUrl != null && _error == _LoadError.none;

  // ---- File resolution ------------------------------------------------------

  static _FileKind _kindOf(String path) {
    final ext = DocumentFileService.extensionOf(path);
    // Formats Flutter's image codec can render inline.
    if (const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext)) {
      return _FileKind.image;
    }
    if (ext == 'pdf') return _FileKind.pdf;
    if (const ['txt', 'md', 'csv', 'json', 'log', 'xml'].contains(ext)) {
      return _FileKind.text;
    }
    // HEIC/HEIF etc. — real images Flutter can't decode inline → open with the
    // device's photo viewer instead of silently failing in Image.network.
    return _FileKind.other;
  }

  Future<void> _resolve() async {
    final rawPath = _record.filePath;
    final uid = AuthService.instance.currentUser?.id;

    // Step 1–2: the record we read from the DB, and its stored file_path.
    developer.log(
      '── OPEN DOCUMENT ──\n'
      'documentId = ${_record.id}\n'
      'fileName   = ${_record.name}\n'
      'file_path  = $rawPath   (from DB)\n'
      'bucket     = documents\n'
      'authUserId = $uid',
      name: 'viewer',
    );

    if (rawPath == null || rawPath.trim().isEmpty) {
      _fail(
        _LoadError.invalidPath,
        'file_path is null/empty for document ${_record.id}. The upload row was '
        'saved without a storage path.',
      );
      return;
    }

    // Step 3–4: normalise to the EXACT storage object path, repairing a bare
    // filename (missing "<uid>/" folder), a leading slash, or a stray bucket
    // prefix — the exact "wrong file_path" cases.
    final storagePath = _normalizeStoragePath(rawPath, uid);
    final folder = storagePath.contains('/') ? storagePath.split('/').first : '(none)';
    developer.log(
      'storagePath = $storagePath   (used for createSignedUrl)\n'
      'pathFolder  = $folder\n'
      'includesFolder = ${storagePath.contains('/')}\n'
      'folderMatchesUser = ${folder == uid}',
      name: 'viewer',
    );
    if (storagePath != rawPath) {
      developer.log(
        'file_path REPAIRED: "$rawPath" -> "$storagePath" — migrating the row.',
        name: 'viewer',
      );
      // Step 7: auto-migrate the incorrect record so it's permanently fixed.
      unawaited(_persistPathFix(storagePath));
    }

    setState(() {
      _storagePath = storagePath;
      _loading = true;
      _error = _LoadError.none;
      _debugDetail = null;
      _imageUrl = null;
      _imageAttempt = 0;
    });

    final kind = _kindOf(storagePath);
    try {
      if (kind == _FileKind.image) {
        // Private bucket → createSignedUrl with the EXACT stored path.
        final url =
            await _retry(() => DocumentRepository.instance.signedUrl(storagePath));
        developer.log('signedUrl = $url', name: 'viewer');
        // Step 6: log the real HTTP status of that URL (debug only).
        if (kDebugMode) unawaited(_probeUrl(url));
        if (!mounted) return;
        setState(() {
          _kind = kind;
          _imageUrl = url;
          _loading = false;
        });
        // Best-effort: cache bytes for size/offline/share, without blocking (or
        // breaking) the image display.
        unawaited(_warmLocalFile(storagePath));
      } else {
        final file = await _retry(
            () => DocumentFileService.instance.ensureLocal(storagePath));
        final size = await file.length();
        final text = kind == _FileKind.text ? await file.readAsString() : null;
        developer.log('cached file ready (${size}B) for $storagePath',
            name: 'viewer');
        if (!mounted) return;
        setState(() {
          _kind = kind;
          _file = file;
          _fileSize = size;
          _textContent = text;
          _loading = false;
        });
      }
    } catch (e, st) {
      // Step 5/7/8: the EXACT Supabase Storage exception.
      developer.log('DOCUMENT LOAD FAILED for $storagePath: $e',
          name: 'viewer', error: e, stackTrace: st);
      _fail(_classify(e), e.toString());
    }
  }

  /// Repairs a stored `file_path` to the exact Storage object path:
  ///   • strips a leading "/",
  ///   • strips a stray "documents/" bucket prefix,
  ///   • prepends `<uid>/` when the value is a bare filename (no folder).
  /// Full, correct paths (already `<uid>/<file>`) pass through untouched.
  String _normalizeStoragePath(String path, String? uid) {
    var p = path.trim();
    if (p.startsWith('/')) p = p.substring(1);
    if (p.startsWith('documents/')) p = p.substring('documents/'.length);
    if (!p.contains('/') && uid != null && uid.isNotEmpty) {
      p = '$uid/$p';
    }
    return p;
  }

  Future<void> _persistPathFix(String fixed) async {
    try {
      await DocumentRepository.instance.update(_record.id, {'file_path': fixed});
      developer.log('migrated file_path for ${_record.id} -> $fixed',
          name: 'viewer');
    } catch (e) {
      developer.log('file_path migration failed (non-fatal): $e', name: 'viewer');
    }
  }

  /// Fetches the signed URL once to log its real HTTP status/content-type — the
  /// definitive "does the URL return 200?" check. Debug-only (avoids a second
  /// download in release).
  Future<void> _probeUrl(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      developer.log(
        'signed URL HTTP status = ${response.statusCode}  '
        'contentType = ${response.headers.contentType}',
        name: 'viewer',
      );
      await response.drain<void>();
    } catch (e) {
      developer.log('signed URL probe failed: $e', name: 'viewer');
    } finally {
      client?.close(force: true);
    }
  }

  /// Runs [action], retrying once automatically on failure (per the brief's
  /// "retry once before showing an error").
  Future<T> _retry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      developer.log('first attempt failed ($e) — retrying once', name: 'viewer');
      return await action();
    }
  }

  void _fail(_LoadError error, String detail) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
      _debugDetail = detail;
    });
  }

  /// Downloads + caches the bytes in the background so File-based actions
  /// (share / download / size) work — failures here are non-fatal (the image is
  /// already showing via the signed URL).
  Future<void> _warmLocalFile(String path) async {
    try {
      final file = await DocumentFileService.instance.ensureLocal(path);
      final size = await file.length();
      if (!mounted) return;
      setState(() {
        _file = file;
        _fileSize = size;
      });
    } catch (e) {
      developer.log('background cache warm failed (non-fatal): $e', name: 'viewer');
    }
  }

  _LoadError _classify(Object e) {
    if (e is AuthException) return _LoadError.authExpired;
    if (e is MissingPluginException) return _LoadError.plugin;
    if (e is TimeoutException) return _LoadError.timeout;
    if (e is SocketException) return _LoadError.network;
    if (e is StorageException) {
      final msg = e.message.toLowerCase();
      final code = (e.statusCode ?? '').toString();
      if (code == '404' ||
          msg.contains('not found') ||
          msg.contains('does not exist') ||
          msg.contains('not_found')) {
        return _LoadError.missing;
      }
      if (code == '403' ||
          msg.contains('permission') ||
          msg.contains('denied') ||
          msg.contains('unauthor') ||
          msg.contains('row-level') ||
          msg.contains('violates') ||
          msg.contains('policy')) {
        return _LoadError.permission;
      }
      if (msg.contains('bucket not found') || msg.contains('bucket')) {
        return _LoadError.bucketMissing;
      }
      return _LoadError.signedUrlFailed;
    }
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') ||
        s.contains('socketexception') ||
        s.contains('connection')) {
      return _LoadError.network;
    }
    if (s.contains('timeout')) return _LoadError.timeout;
    if (s.contains('missingplugin') || s.contains('no implementation found')) {
      return _LoadError.plugin;
    }
    if (s.contains('not found') || s.contains('does not exist')) {
      return _LoadError.missing;
    }
    if (s.contains('permission') ||
        s.contains('denied') ||
        s.contains('row-level') ||
        s.contains('policy') ||
        s.contains('unauthor')) {
      return _LoadError.permission;
    }
    return _LoadError.unknown;
  }

  /// Auto-recovery: regenerate the signed URL once when the image fails to load
  /// (e.g. an expired URL).
  Future<void> _regenerateImageUrl(Object renderError) async {
    developer.log('image render failed ($renderError) — regenerating signed URL',
        name: 'viewer');
    final path = _storagePath ?? _record.filePath;
    if (path == null || !mounted) return;
    try {
      final url = await DocumentRepository.instance.signedUrl(path);
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _imageAttempt += 1;
      });
    } catch (e) {
      _fail(_classify(e), e.toString());
    }
  }

  /// Ensures a local copy exists (for share / download / open), fetching on
  /// demand if the background warm hasn't finished.
  Future<File?> _localFile() async {
    if (_file != null) return _file;
    final path = _storagePath ?? _record.filePath;
    if (path == null) return null;
    try {
      final file = await DocumentFileService.instance.ensureLocal(path);
      if (mounted) setState(() => _file = file);
      return file;
    } catch (e) {
      developer.log('on-demand file fetch failed: $e', name: 'viewer');
      return null;
    }
  }

  // ---- Result plumbing ------------------------------------------------------

  void _popUpdated() =>
      Navigator.of(context).pop(DocumentViewerResult(updated: _record));

  void _popRemoved() =>
      Navigator.of(context).pop(const DocumentViewerResult(removed: true));

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
          content: Text(message),
        ),
      );
  }

  // ---- Actions --------------------------------------------------------------

  void _toggleFavorite() {
    setState(() => _record = _record.copyWith(isFavorite: !_record.isFavorite));
    WalletDetailRepository.instance.updateRecord(widget.walletName, _record);
    HapticFeedback.selectionClick();
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final origin = shareOrigin(context);
    try {
      final file = await _localFile();
      final path = _record.filePath;
      if (file == null || path == null) {
        _snack('Nothing to share — the file could not be loaded.', error: true);
        return;
      }
      final named =
          await DocumentFileService.instance.namedCopy(file, _record.name, path);
      await Share.shareXFiles(
        [XFile(named.path)],
        subject: _record.name,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      _snack('Could not share this document.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _localFile();
      final path = _record.filePath;
      if (file == null || path == null) {
        _snack('Nothing to download — the file could not be loaded.',
            error: true);
        return;
      }
      final named =
          await DocumentFileService.instance.namedCopy(file, _record.name, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primaryGreen,
            content: const Text('Saved a copy to the app'),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => OpenFilex.open(named.path),
            ),
          ),
        );
    } catch (_) {
      _snack('Download failed. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openExternally() async {
    final file = await _localFile();
    if (file == null) {
      _snack('Could not load this file.', error: true);
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && mounted) {
      _snack('No app on this device can open this file.', error: true);
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _record.name);
    final palette = AppPalette.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Document name'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _record.name) return;
    setState(() => _record = _record.copyWith(name: newName));
    try {
      await DocumentRepository.instance.rename(_record.id, newName);
      WalletDetailRepository.instance.updateRecord(widget.walletName, _record);
      _snack('Renamed to “$newName”');
    } catch (_) {
      _snack('Rename failed. Please try again.', error: true);
    }
  }

  Future<void> _move() async {
    const wallets = [
      'Identity Wallet',
      'Document Wallet',
      'Property Wallet',
      'Insurance Wallet',
      'Health Wallet',
      'Investment Wallet',
      'Banking Wallet',
      'Password Vault',
    ];
    final palette = AppPalette.of(context);
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Move to',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            for (final w in wallets.where((w) => w != widget.walletName))
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.primaryGreen),
                title: Text(w, style: TextStyle(color: palette.textPrimary)),
                onTap: () => Navigator.of(context).pop(w),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await DocumentRepository.instance.move(_record.id, target);
      WalletDetailRepository.instance
          .deleteRecordLocal(widget.walletName, _record.id);
      _snack('Moved to $target');
      if (mounted) _popRemoved();
    } catch (_) {
      _snack('Move failed. Please try again.', error: true);
    }
  }

  Future<void> _archive() async {
    setState(() => _record = _record.copyWith(status: DocumentStatus.archived));
    WalletDetailRepository.instance.updateRecord(widget.walletName, _record);
    _snack('${_record.name} archived');
  }

  Future<void> _delete() async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Delete document?'),
        content: Text(
          'This permanently deletes “${_record.name}” and its file. This cannot be undone.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.critical)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    WalletDetailRepository.instance.deleteRecord(widget.walletName, _record.id);
    if (mounted) _popRemoved();
  }

  Future<void> _removeProtection() async {
    final ok = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: 'Authenticate to remove protection from this document.',
      title: 'Verify your identity',
    );
    if (!ok || !mounted) return;
    await DocumentProtectionStore.instance.setProtected(_record.id, false);
    if (!mounted) return;
    setState(() => _protected = false);
    _snack('${_record.name} is no longer protected');
  }

  void _showInfo() {
    final palette = AppPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
              AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Document information',
                  style: AppText.title.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              _InfoRow(label: 'File name', value: _record.name),
              _InfoRow(label: 'Category', value: _record.category),
              _InfoRow(
                  label: 'Upload date',
                  value: inoFormatDate(_record.uploadedAt)),
              _InfoRow(
                  label: 'File size',
                  value: _fileSize > 0 ? _formatBytes(_fileSize) : '—'),
              _InfoRow(
                  label: 'Protection',
                  value: _protected ? 'Biometric protected' : 'Not protected'),
              _InfoRow(
                  label: 'Favorite', value: _record.isFavorite ? 'Yes' : 'No'),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = _isImageView;
    final fg = dark ? Colors.white : palette.textPrimary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _popUpdated();
      },
      child: Scaffold(
        backgroundColor: dark ? Colors.black : palette.bg,
        extendBodyBehindAppBar: dark,
        appBar: AppBar(
          backgroundColor:
              dark ? Colors.black.withValues(alpha: 0.35) : palette.bg,
          foregroundColor: fg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _popUpdated,
          ),
          title: Text(
            _record.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: fg, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          actions: [
            IconButton(
              tooltip: _record.isFavorite ? 'Unfavorite' : 'Favorite',
              icon: Icon(
                _record.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: _record.isFavorite ? AppColors.warning : fg,
              ),
              onPressed: _toggleFavorite,
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: _share,
            ),
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded),
              onPressed: _download,
            ),
            _moreMenu(fg),
          ],
        ),
        body: _body(palette),
      ),
    );
  }

  Widget _moreMenu(Color fg) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: fg),
      onSelected: (value) {
        switch (value) {
          case 'rename':
            _rename();
          case 'move':
            _move();
          case 'archive':
            _archive();
          case 'delete':
            _delete();
          case 'unprotect':
            _removeProtection();
          case 'info':
            _showInfo();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'move', child: Text('Move')),
        const PopupMenuItem(value: 'archive', child: Text('Archive')),
        if (_protected)
          const PopupMenuItem(
              value: 'unprotect', child: Text('Remove protection')),
        const PopupMenuItem(value: 'info', child: Text('Document information')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.critical)),
        ),
      ],
    );
  }

  Widget _body(AppPalette palette) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2.6, color: AppColors.primaryGreen),
      );
    }
    if (_error != _LoadError.none) {
      return _errorView();
    }
    switch (_kind) {
      case _FileKind.image:
        return _imageBody();
      case _FileKind.text:
        return _textBody(palette);
      case _FileKind.pdf:
      case _FileKind.other:
        return _launchBody(palette);
    }
  }

  Widget _errorView() {
    final spec = _specFor(_error);
    return _ErrorView(
      icon: spec.icon,
      title: spec.title,
      message: spec.message,
      debugDetail: _debugDetail,
      onRetry: spec.retryable ? _resolve : null,
    );
  }

  ({IconData icon, String title, String message, bool retryable}) _specFor(
      _LoadError e) {
    switch (e) {
      case _LoadError.invalidPath:
        return (
          icon: Icons.link_off_rounded,
          title: 'No file attached',
          message: 'This document has no stored file to open.',
          retryable: false,
        );
      case _LoadError.missing:
        return (
          icon: Icons.broken_image_rounded,
          title: 'This document is no longer available.',
          message: 'The file could not be found in your secure storage.',
          retryable: false,
        );
      case _LoadError.bucketMissing:
        return (
          icon: Icons.folder_off_rounded,
          title: 'Storage not configured',
          message:
              'The "documents" storage bucket is missing. Create it in Supabase → Storage.',
          retryable: true,
        );
      case _LoadError.permission:
        return (
          icon: Icons.lock_outline_rounded,
          title: 'Access denied',
          message:
              "You don't have permission to open this file. Check the Storage RLS policies for the documents bucket.",
          retryable: true,
        );
      case _LoadError.signedUrlFailed:
        return (
          icon: Icons.link_off_rounded,
          title: "Couldn't prepare the file",
          message: 'The secure link could not be generated. Please try again.',
          retryable: true,
        );
      case _LoadError.timeout:
        return (
          icon: Icons.timer_off_rounded,
          title: 'Loading timed out',
          message: 'The file took too long to load. Please try again.',
          retryable: true,
        );
      case _LoadError.authExpired:
        return (
          icon: Icons.logout_rounded,
          title: 'Session expired',
          message: 'Please sign in again to open this document.',
          retryable: true,
        );
      case _LoadError.plugin:
        return (
          icon: Icons.extension_off_rounded,
          title: 'Restart required',
          message:
              "A required module isn't loaded. Fully close and reopen the app (a hot reload isn't enough after adding plugins).",
          retryable: true,
        );
      case _LoadError.network:
        return (
          icon: Icons.wifi_off_rounded,
          title: "Couldn't load this document",
          message: 'Check your connection and try again.',
          retryable: true,
        );
      case _LoadError.unknown:
      case _LoadError.none:
        return (
          icon: Icons.error_outline_rounded,
          title: "Couldn't open this document",
          message: 'An unexpected error occurred. Please try again.',
          retryable: true,
        );
    }
  }

  Widget _imageBody() {
    final url = _imageUrl!;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTapDown: (d) => _doubleTapDetails = d,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: RotatedBox(
                quarterTurns: _rotation,
                child: Hero(
                  tag: 'doc-${_record.id}',
                  child: Image.network(
                    url,
                    key: ValueKey('img-$_imageAttempt'),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: AppColors.primaryGreen,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stack) {
                      // Auto-recover once (expired / transient), then surface a
                      // real, classified error.
                      if (_imageAttempt < 1) {
                        WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _regenerateImageUrl(error));
                      } else {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _error == _LoadError.none) {
                            _fail(_classify(error), error.toString());
                          }
                        });
                      }
                      return const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2.6, color: AppColors.primaryGreen),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _imageInfoBar()),
      ],
    );
  }

  void _handleDoubleTap() {
    if (_tc.value != Matrix4.identity()) {
      _tc.value = Matrix4.identity();
    } else {
      final pos = _doubleTapDetails?.localPosition;
      if (pos == null) return;
      const scale = 2.6;
      _tc.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * (scale - 1), -pos.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
    }
  }

  Widget _imageInfoBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
              _RoundIconButton(
                icon: Icons.rotate_90_degrees_ccw_rounded,
                onTap: () => setState(() => _rotation = (_rotation + 1) % 4),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: _record.category, icon: Icons.folder_rounded),
              _MetaChip(
                  label: inoFormatDate(_record.uploadedAt),
                  icon: Icons.event_rounded),
              if (_fileSize > 0)
                _MetaChip(
                    label: _formatBytes(_fileSize),
                    icon: Icons.sd_storage_rounded),
              if (_protected)
                const _MetaChip(
                    label: 'Protected',
                    icon: Icons.lock_rounded,
                    accent: AppColors.primaryGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textBody(AppPalette palette) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SelectableText(
        _textContent ?? '',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 14,
          height: 1.55,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _launchBody(AppPalette palette) {
    final isPdf = _kind == _FileKind.pdf;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.accent),
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Icon(
                isPdf
                    ? Icons.picture_as_pdf_rounded
                    : Icons.insert_drive_file_rounded,
                color: Colors.white,
                size: 46,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(_record.name,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: 6),
            Text(
              _fileSize > 0
                  ? '${_record.category} · ${_formatBytes(_fileSize)}'
                  : _record.category,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _openExternally,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(isPdf ? 'Open PDF' : 'Open file'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Opens with your device’s ${isPdf ? 'PDF' : 'default'} app.',
              style: AppText.caption.copyWith(color: palette.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.icon, this.accent});

  final String label;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (accent ?? Colors.white)
            .withValues(alpha: accent != null ? 0.20 : 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label,
                style: AppText.caption.copyWith(color: palette.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppText.body.copyWith(
                  color: palette.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.icon,
    required this.title,
    required this.message,
    this.debugDetail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? debugDetail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: palette.textFaint),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary)),
            // In debug builds, surface the exact exception so failures are
            // diagnosable instead of generic.
            if (kDebugMode && debugDetail != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.critical.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                      color: AppColors.critical.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  debugDetail!,
                  style: const TextStyle(
                    color: AppColors.critical,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
