import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/document.dart';
import '../models/user_profile.dart';
import '../repositories/document_repository.dart';
import 'app_settings.dart';
import 'biometric_service.dart';
import 'document_protection_store.dart';

/// A built account archive: the JSON bytes plus a file written to a temp dir,
/// ready to share, save or upload.
class AccountArchive {
  const AccountArchive({
    required this.file,
    required this.bytes,
    required this.documentCount,
  });

  final File file;
  final Uint8List bytes;
  final int documentCount;

  int get sizeBytes => bytes.length;
}

/// Builds a complete, human-readable JSON archive of the user's account:
/// profile, settings and all document metadata. Powers **Export Data**,
/// **Download Account Data** and the JSON payload for **Cloud Backup**.
///
/// It never fabricates data — everything comes from the live profile, the
/// `documents` table and the persisted settings. Progress is reported through an
/// optional callback so the UI can show a determinate indicator on big vaults.
class DataExportService {
  DataExportService._();
  static final DataExportService instance = DataExportService._();

  static const int _formatVersion = 1;

  /// Gathers everything and writes `ino-account-<timestamp>.json` to the temp
  /// directory. [onProgress] receives 0.0 → 1.0.
  Future<AccountArchive> build({
    required UserProfile profile,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);
    developer.log('export: gathering documents', name: 'export');

    List<Document> docs = const [];
    try {
      docs = await DocumentRepository.instance.listAll();
    } catch (e) {
      // Offline / signed out — still export the profile + settings we have.
      developer.log('export: document fetch failed: $e', name: 'export');
    }
    onProgress?.call(0.6);

    final settings = AppSettings.instance;
    final now = DateTime.now();

    final map = <String, dynamic>{
      'format_version': _formatVersion,
      'generated_at': now.toIso8601String(),
      'app': {'name': 'INO', 'platform': _platformName()},
      'account': {
        'id': profile.id,
        'auth_user_id': profile.authUserId,
        'full_name': profile.fullName,
        'email': profile.email,
        'phone': profile.phone,
        'preferred_language': profile.preferredLanguage,
        'biometric_enabled': profile.biometricEnabled,
        'created_at': profile.createdAt.toIso8601String(),
        'updated_at': profile.updatedAt.toIso8601String(),
      },
      'settings': {
        'notifications': settings.notifications.value,
        'auto_backup': settings.autoBackup.value,
        'two_factor': settings.twoFactor.value,
        'language': settings.language.value,
        'biometric_lock': BiometricService.instance.lockEnabled.value,
        'protected_document_count':
            DocumentProtectionStore.instance.protectedCount,
      },
      'documents': [
        for (final d in docs)
          {
            'id': d.id,
            'wallet': d.wallet,
            'name': d.name,
            'category': d.category,
            'record_number': d.recordNumber,
            'status': d.status,
            'tags': d.tags,
            'notes': d.notes,
            'is_favorite': d.isFavorite,
            'protected': DocumentProtectionStore.instance.isProtected(d.id),
            'expires_at': d.expiresAt?.toIso8601String(),
            'file_path': d.filePath,
            'created_at': d.createdAt.toIso8601String(),
            'updated_at': d.updatedAt.toIso8601String(),
          },
      ],
      'document_count': docs.length,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(map);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    onProgress?.call(0.85);

    final dir = await getTemporaryDirectory();
    final stamp = now.millisecondsSinceEpoch;
    final file = File('${dir.path}/ino-account-$stamp.json');
    await file.writeAsBytes(bytes, flush: true);
    onProgress?.call(1.0);

    developer.log(
      'export: wrote ${bytes.length}B (${docs.length} documents) → ${file.path}',
      name: 'export',
    );
    return AccountArchive(
      file: file,
      bytes: bytes,
      documentCount: docs.length,
    );
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
