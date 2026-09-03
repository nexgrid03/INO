import 'dart:convert';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../core/storage/shared_prefs_cache.dart';
import '../repositories/document_repository.dart';
import '../utils/formatting.dart';

/// A snapshot of the signed-in user's real Storage usage.
class StorageUsage {
  const StorageUsage({
    required this.usedBytes,
    required this.fileCount,
    this.quotaBytes = defaultQuotaBytes,
  });

  /// 5 GB quota limit
  static const int defaultQuotaBytes = 5 * 1024 * 1024 * 1024; // 5 GB

  final int usedBytes;
  final int fileCount;
  final int quotaBytes;

  double get fraction =>
      quotaBytes == 0 ? 0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);

  String get usedLabel => formatBytes(usedBytes);
  String get quotaLabel => formatBytes(quotaBytes);
  int get percent => (fraction * 100).round();
  bool get isFull => usedBytes >= quotaBytes;

  /// High-accuracy percent label: never prematurely rounds down to 0% when files exist.
  String get percentFormatted {
    if (usedBytes <= 0) return '0%';
    final pct = fraction * 100;
    if (pct < 0.01) return '<0.01%';
    if (pct < 1.0) {
      final s = pct.toStringAsFixed(2);
      return s.endsWith('0') ? '${pct.toStringAsFixed(1)}%' : '$s%';
    }
    if (pct < 10.0) {
      final s = pct.toStringAsFixed(1);
      return s.endsWith('.0') ? '${pct.round()}%' : '$s%';
    }
    return '${pct.round()}%';
  }

  /// Minimum progress width so that small files (like 12.5 MB) show a visible indicator.
  double get displayFraction {
    if (usedBytes <= 0) return 0.0;
    return fraction < 0.03 ? 0.03 : fraction.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'usedBytes': usedBytes,
        'fileCount': fileCount,
        'quotaBytes': quotaBytes,
      };

  factory StorageUsage.fromJson(Map<String, dynamic> j) => StorageUsage(
        usedBytes: (j['usedBytes'] as num?)?.toInt() ?? 0,
        fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
        quotaBytes:
            (j['quotaBytes'] as num?)?.toInt() ?? defaultQuotaBytes,
      );

  static const StorageUsage empty = StorageUsage(usedBytes: 0, fileCount: 0);
}

/// Computes real storage usage by querying Supabase Storage RPC or summing
/// user Storage objects. Caches the latest snapshot in SharedPreferences so
/// the meter is instantaneous and functions offline.
class StorageStatsService {
  StorageStatsService._();
  static final StorageStatsService instance = StorageStatsService._();

  static const String _kStorageCacheKey = 'ino_storage_usage_snapshot';

  /// Returns the cached storage snapshot, or empty if never loaded.
  Future<StorageUsage> getCached() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final raw = p.getString(_kStorageCacheKey);
      if (raw != null && raw.isNotEmpty) {
        return StorageUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return StorageUsage.empty;
  }

  Future<void> _cacheUsage(StorageUsage usage) async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setString(_kStorageCacheKey, jsonEncode(usage.toJson()));
    } catch (_) {}
  }

  Future<StorageUsage> load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      return getCached();
    }

    // 1) Fast-path: query the database RPC function directly
    try {
      final res = await client
          .rpc('get_user_storage_usage')
          .timeout(NetGuard.query);
      if (res != null) {
        final Map<String, dynamic> data = res is String
            ? (jsonDecode(res) as Map<String, dynamic>)
            : (res as Map).cast<String, dynamic>();
        final used = (data['used_bytes'] as num?)?.toInt() ?? 0;
        final count = (data['file_count'] as num?)?.toInt() ?? 0;
        final usage = StorageUsage(usedBytes: used, fileCount: count);
        await _cacheUsage(usage);
        developer.log(
            'storage via RPC: $count file(s), ${formatBytes(used)} used',
            name: 'storage');
        return usage;
      }
    } catch (e) {
      developer.log('storage RPC failed, falling back to object listing: $e',
          name: 'storage');
    }

    // 2) Fallback: list user objects from Storage API
    try {
      final repo = DocumentRepository.instance;
      final List<FileObject> files = await repo.listUserObjects();
      List<FileObject> backups = const [];
      try {
        backups = await repo.listUserObjects(subFolder: 'backups');
      } catch (_) {}

      var used = 0;
      var count = 0;
      for (final o in [...files, ...backups]) {
        final meta = o.metadata;
        final size = (meta?['size'] as num?)?.toInt() ??
            (meta?['contentLength'] as num?)?.toInt() ??
            (meta?['content-length'] as num?)?.toInt() ??
            0;
        used += size;
        count++;
      }

      if (count > 0 || used > 0) {
        final usage = StorageUsage(usedBytes: used, fileCount: count);
        await _cacheUsage(usage);
        developer.log('storage via list: $count file(s), ${formatBytes(used)} used',
            name: 'storage');
        return usage;
      }
    } catch (e) {
      developer.log('storage list failed: $e', name: 'storage');
    }

    // 3) Offline or failure fallback: return cached snapshot
    return getCached();
  }
}
