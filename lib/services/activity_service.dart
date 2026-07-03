import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../data/reminder_store.dart';
import '../models/dashboard_models.dart';
import '../models/document.dart';
import '../models/reminder_models.dart';
import '../repositories/document_repository.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import 'app_settings.dart';

/// Builds the Recent Activity feed from **real** app events: documents the user
/// uploaded (from the `documents` table), reminders they created, and the last
/// cloud backup. Everything is timestamped and sorted newest-first.
///
/// If nothing real exists yet (fresh account / offline), it returns an empty
/// list so the UI can show a proper empty state — it never invents fake rows.
class ActivityService {
  ActivityService._();
  static final ActivityService instance = ActivityService._();

  /// Loads the most recent activity across sources.
  Future<List<ActivityItem>> load({int limit = 40}) async {
    final items = <ActivityItem>[];

    // 1. Documents (real).
    try {
      final docs = await DocumentRepository.instance.listAll();
      for (final d in docs) {
        items.add(_fromDocument(d));
      }
    } catch (e) {
      developer.log('activity: documents unavailable: $e', name: 'activity');
    }

    // 2. Reminders (real, from the shared store).
    try {
      await ReminderStore.instance.ensureLoaded();
      for (final r in ReminderStore.instance.active) {
        items.add(ActivityItem(
          title: 'Reminder · ${r.title}',
          subtitle: r.subtitle.isEmpty ? r.category.label : r.subtitle,
          icon: Icons.alarm_rounded,
          color: r.category.color,
          at: r.date,
          time: formatRelativeDate(r.date),
          kind: ActivityKind.reminder,
        ));
      }
    } catch (e) {
      developer.log('activity: reminders unavailable: $e', name: 'activity');
    }

    // 3. Last cloud backup (real, from settings).
    final lastBackup = AppSettings.instance.lastBackupAt.value;
    if (lastBackup != null) {
      items.add(ActivityItem(
        title: 'Cloud backup completed',
        subtitle: 'Your vault was backed up',
        icon: Icons.cloud_done_rounded,
        color: AppColors.lightBlue,
        at: lastBackup,
        time: formatRelativeDate(lastBackup),
        kind: ActivityKind.backup,
      ));
    }

    // Sort newest-first; items without a timestamp sink to the bottom.
    items.sort((a, b) {
      final at = a.at, bt = b.at;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    developer.log('activity: ${items.length} items', name: 'activity');
    return items.take(limit).toList();
  }

  ActivityItem _fromDocument(Document d) {
    final category = d.category ?? 'Document';
    return ActivityItem(
      title: '${d.name} uploaded',
      subtitle: '$category · ${d.wallet}',
      icon: _iconFor(category),
      color: _colorFor(category),
      at: d.createdAt,
      time: formatRelativeDate(d.createdAt),
      kind: ActivityKind.document,
    );
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'Identity':
        return Icons.badge_rounded;
      case 'Financial':
        return Icons.account_balance_rounded;
      case 'Legal':
        return Icons.gavel_rounded;
      case 'Medical':
        return Icons.favorite_rounded;
      case 'Property':
        return Icons.home_work_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  Color _colorFor(String category) {
    switch (category) {
      case 'Identity':
        return AppColors.primaryGreen;
      case 'Financial':
        return AppColors.secondaryGreen;
      case 'Legal':
        return const Color(0xFF8B6CEF);
      case 'Medical':
        return const Color(0xFFEC6A8C);
      case 'Property':
        return AppColors.lightBlue;
      default:
        return AppColors.primaryGreen;
    }
  }
}
