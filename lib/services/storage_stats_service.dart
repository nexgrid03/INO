import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart' show FileObject;

import '../repositories/document_repository.dart';
import '../utils/formatting.dart';

/// A snapshot of the signed-in user's real Storage usage.
class StorageUsage {
  const StorageUsage({
    required this.usedBytes,
    required this.fileCount,
    this.quotaBytes = defaultQuotaBytes,
  });

  /// A conservative free-tier style quota so the meter has a denominator.
  static const int defaultQuotaBytes = 5 * 1024 * 1024 * 1024; // 5 GB

  final int usedBytes;
  final int fileCount;
  final int quotaBytes;

  double get fraction =>
      quotaBytes == 0 ? 0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);

  String get usedLabel => formatBytes(usedBytes);
  String get quotaLabel => formatBytes(quotaBytes);
  int get percent => (fraction * 100).round();

  static const StorageUsage empty = StorageUsage(usedBytes: 0, fileCount: 0);
}

/// Computes real storage usage by summing the sizes of the user's Storage
/// objects (documents + cloud backups). Falls back to [StorageUsage.empty] when
/// signed out or offline, so the meter never shows fake data.
class StorageStatsService {
  StorageStatsService._();
  static final StorageStatsService instance = StorageStatsService._();

  Future<StorageUsage> load() async {
    try {
      final repo = DocumentRepository.instance;
      // Top-level document objects…
      final List<FileObject> files = await repo.listUserObjects();
      // …plus anything stored under the backups sub-folder.
      List<FileObject> backups = const [];
      try {
        backups = await repo.listUserObjects(subFolder: 'backups');
      } catch (_) {
        // No backups folder yet — that's fine.
      }

      var used = 0;
      var count = 0;
      for (final o in [...files, ...backups]) {
        final size = (o.metadata?['size'] as num?)?.toInt() ?? 0;
        used += size;
        count++;
      }

      developer.log('storage: $count file(s), ${formatBytes(used)} used',
          name: 'storage');
      return StorageUsage(usedBytes: used, fileCount: count);
    } catch (e) {
      developer.log('storage load failed: $e', name: 'storage');
      return StorageUsage.empty;
    }
  }
}
