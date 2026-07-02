import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../repositories/document_repository.dart';
import 'app_settings.dart';
import 'data_export_service.dart';

/// One cloud backup object stored under `<uid>/backups/`.
class CloudBackup {
  const CloudBackup({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.updatedAt,
  });

  final String name;
  final String path; // full object path (<uid>/backups/<name>)
  final int sizeBytes;
  final DateTime? updatedAt;
}

/// Cloud Backup: uploads a JSON account archive to Supabase Storage and lists /
/// restores previous backups.
///
/// A "backup" is the same archive produced by [DataExportService], uploaded to a
/// private `backups` sub-folder. Real network calls, real objects — the last
/// backup time is persisted in [AppSettings] so the Cloud Backup page shows it
/// immediately.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Builds and uploads a fresh backup. Returns the created [CloudBackup].
  Future<CloudBackup> backupNow({
    required UserProfile profile,
    void Function(double progress)? onProgress,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to back up.');
    }

    final archive = await DataExportService.instance.build(
      profile: profile,
      onProgress: (p) => onProgress?.call(p * 0.7),
    );

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final name = 'backup-$stamp.json';
    final path = '$uid/backups/$name';
    developer.log('backupNow: uploading → $path', name: 'backup');

    await DocumentRepository.instance.uploadBytes(
      path,
      archive.bytes,
      contentType: 'application/json',
    );
    onProgress?.call(1.0);

    await AppSettings.instance.markBackedUpNow();
    developer.log('backupNow: complete (${archive.sizeBytes}B)', name: 'backup');
    return CloudBackup(
      name: name,
      path: path,
      sizeBytes: archive.sizeBytes,
      updatedAt: DateTime.now(),
    );
  }

  /// Lists existing backups, newest first.
  Future<List<CloudBackup>> listBackups() async {
    final uid = _uid;
    if (uid == null) return const [];
    final objects =
        await DocumentRepository.instance.listUserObjects(subFolder: 'backups');
    final backups = <CloudBackup>[
      for (final o in objects)
        CloudBackup(
          name: o.name,
          path: '$uid/backups/${o.name}',
          sizeBytes: (o.metadata?['size'] as num?)?.toInt() ?? 0,
          updatedAt:
              o.updatedAt == null ? null : DateTime.tryParse(o.updatedAt!),
        ),
    ]..sort((a, b) => b.name.compareTo(a.name));
    developer.log('listBackups: ${backups.length} found', name: 'backup');
    return backups;
  }

  /// Downloads a backup to a temp file so it can be shared / re-imported.
  Future<File> download(CloudBackup backup) async {
    developer.log('download: ${backup.path}', name: 'backup');
    final Uint8List bytes =
        await DocumentRepository.instance.download(backup.path);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${backup.name}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
