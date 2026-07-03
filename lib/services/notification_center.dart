import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reminder_store.dart';
import '../repositories/document_repository.dart';
import 'app_settings.dart';
import 'biometric_service.dart';

/// The category a notification belongs to (drives its icon / colour / filter).
enum NotificationCategory { reminder, security, backup, asset, document, system }

/// One notification shown in the Notifications page and counted on the bell.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.at,
    this.read = false,
  });

  final String id; // stable across refreshes so read/dismissed state persists
  final String title;
  final String body;
  final NotificationCategory category;
  final DateTime at;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        category: category,
        at: at,
        read: read ?? this.read,
      );
}

/// Generates and manages notifications from **real app state** — due reminders,
/// expiring documents, security posture (biometric / 2FA) and cloud-backup
/// health — and persists which ones the user has read or dismissed.
///
/// Notifications are derived (not stored server-side), so [refresh] rebuilds
/// them from current state and re-applies the persisted read/dismissed sets by
/// their stable ids. Exposed as a [ChangeNotifier] so the bell badge and the
/// list stay in sync everywhere.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  static const _kRead = 'notif_read_ids';
  static const _kDismissed = 'notif_dismissed_ids';

  final Set<String> _read = {};
  final Set<String> _dismissed = {};
  List<AppNotification> _all = [];
  bool _loaded = false;

  /// Visible (non-dismissed) notifications, newest first.
  List<AppNotification> get notifications => _all
      .where((n) => !_dismissed.contains(n.id))
      .map((n) => n.copyWith(read: _read.contains(n.id)))
      .toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  int get unreadCount => notifications.where((n) => !n.read).length;
  bool get isLoaded => _loaded;

  /// Loads persisted read/dismissed state, then generates from current state.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _read
        ..clear()
        ..addAll(p.getStringList(_kRead) ?? const []);
      _dismissed
        ..clear()
        ..addAll(p.getStringList(_kDismissed) ?? const []);
    } catch (_) {
      // No plugin (tests) — start empty.
    }
    await refresh();
  }

  /// Rebuilds the notification list from live app state.
  Future<void> refresh() async {
    final items = <AppNotification>[];
    final now = DateTime.now();

    // Reminders due soon / overdue.
    try {
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      for (final r in ReminderStore.instance.active) {
        final days = r.daysFrom(today);
        if (days <= 7) {
          items.add(AppNotification(
            id: 'rem-${r.id}',
            title: r.title,
            body: r.dueLabel(today),
            category: NotificationCategory.reminder,
            at: days < 0 ? now : r.date,
          ));
        }
      }
    } catch (e) {
      developer.log('notif: reminders unavailable: $e', name: 'notif');
    }

    // Documents: expiring within 30 days.
    try {
      final docs = await DocumentRepository.instance.listAll();
      for (final d in docs) {
        final exp = d.expiresAt;
        if (exp == null) continue;
        final days = exp.difference(now).inDays;
        if (days >= 0 && days <= 30) {
          items.add(AppNotification(
            id: 'doc-exp-${d.id}',
            title: '${d.name} expires soon',
            body: days == 0 ? 'Expires today' : 'Expires in $days days',
            category: NotificationCategory.document,
            at: now,
          ));
        }
      }
    } catch (e) {
      developer.log('notif: documents unavailable: $e', name: 'notif');
    }

    // Security posture.
    if (!BiometricService.instance.lockEnabled.value) {
      items.add(AppNotification(
        id: 'sec-biometric',
        title: 'Add a biometric lock',
        body: 'Protect your vault with Face ID or fingerprint.',
        category: NotificationCategory.security,
        at: now.subtract(const Duration(minutes: 30)),
      ));
    }
    if (!AppSettings.instance.twoFactor.value) {
      items.add(AppNotification(
        id: 'sec-2fa',
        title: 'Enable two-factor authentication',
        body: 'Add a second layer of security to your account.',
        category: NotificationCategory.security,
        at: now.subtract(const Duration(hours: 1)),
      ));
    }

    // Backup health.
    final lastBackup = AppSettings.instance.lastBackupAt.value;
    if (lastBackup == null) {
      items.add(AppNotification(
        id: 'backup-none',
        title: 'Set up cloud backup',
        body: 'Back up your documents so you never lose them.',
        category: NotificationCategory.backup,
        at: now.subtract(const Duration(hours: 2)),
      ));
    } else if (now.difference(lastBackup).inDays >= 7) {
      items.add(AppNotification(
        id: 'backup-stale',
        title: 'Backup is out of date',
        body: 'Your last backup was ${now.difference(lastBackup).inDays} days ago.',
        category: NotificationCategory.backup,
        at: now.subtract(const Duration(hours: 2)),
      ));
    }

    _all = items;
    _loaded = true;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    if (_read.add(id)) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> markAllRead() async {
    _read.addAll(_all.map((n) => n.id));
    notifyListeners();
    await _persist();
  }

  Future<void> dismiss(String id) async {
    if (_dismissed.add(id)) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kRead, _read.toList());
      await p.setStringList(_kDismissed, _dismissed.toList());
    } catch (_) {
      // Best-effort.
    }
  }
}
