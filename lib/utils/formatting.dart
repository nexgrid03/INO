// Small, pure formatting helpers shared across the app.

import '../l10n/app_localizations.dart';

/// Human-readable byte size, e.g. `0 B`, `812 KB`, `1.2 GB`.
///
/// Uses binary units (1024) to match how Supabase Storage / device storage
/// report sizes. Keeps one decimal for MB/GB, none for B/KB.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final decimals = unit >= 2 ? 1 : 0; // B/KB → whole, MB+ → one decimal
  return '${size.toStringAsFixed(decimals)} ${units[unit]}';
}

/// A short "time ago" / date label for backups, device activity, etc., in the
/// active language.
String formatRelativeDate(AppLocalizations l10n, DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return l10n.t('justNow');
  if (diff.inMinutes < 60) return '${diff.inMinutes} ${l10n.t('minutesAgo')}';
  if (diff.inHours < 24) return '${diff.inHours} ${l10n.t('hoursAgo')}';
  if (diff.inDays == 1) return l10n.t('yesterday');
  if (diff.inDays < 7) return '${diff.inDays} ${l10n.t('daysAgo')}';
  final d = time;
  return '${d.day} ${l10n.monthShort(d.month)} ${d.year}';
}
