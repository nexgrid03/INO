import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder_models.dart';
import 'app_settings.dart';
import 'push_service.dart';

/// Rings each reminder on THIS device at the exact moment it is due.
///
/// The server push (`send-reminder-push`, once a minute) is the backup; this
/// is the primary path because it needs no network at the due moment, fires
/// to the second, and works with the app killed. Both use the same
/// notification id ([idFor]) so a server push that arrives for a reminder the
/// device already rang REPLACES that banner instead of stacking a duplicate.
///
/// Never throws: scheduling is an enhancement to the reminder, not a
/// precondition for saving it.
class ReminderScheduler {
  ReminderScheduler._();
  static final ReminderScheduler instance = ReminderScheduler._();

  // The plugin is a process-wide singleton behind this factory, so this shares
  // the initialisation + tap handler PushService registers.
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _tzReady = false;
  bool _exactChecked = false;
  bool _exactAllowed = false;

  /// Scheduling only exists on the mobile platforms; on web/desktop and in
  /// tests every call is a silent no-op.
  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Stable, non-negative notification id for a reminder id. Must agree with
  /// `PushService.reminderNotificationId` so a server push and the local
  /// schedule for the same reminder share one banner.
  static int idFor(String reminderId) => reminderId.hashCode & 0x7fffffff;

  void _ensureTz() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    _tzReady = true;
  }

  /// Android 12+ gates exact alarms behind a user-granted permission. Asks once
  /// (this opens the system settings page), and remembers the answer. Called
  /// from the create sheet, where the user has just chosen a time and the
  /// prompt makes sense; never from app start.
  Future<bool> ensureExactPermission() async {
    if (!_supported || !Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      var ok = await android.canScheduleExactNotifications() ?? false;
      if (!ok) {
        ok = await android.requestExactAlarmsPermission() ?? false;
      }
      _exactChecked = true;
      _exactAllowed = ok;
      return ok;
    } catch (e) {
      developer.log('exact-alarm permission check failed: $e', name: 'sched');
      return false;
    }
  }

  Future<AndroidScheduleMode> _mode() async {
    if (!Platform.isAndroid) return AndroidScheduleMode.exactAllowWhileIdle;
    if (!_exactChecked) {
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        _exactAllowed =
            await android?.canScheduleExactNotifications() ?? false;
      } catch (_) {
        _exactAllowed = false;
      }
      _exactChecked = true;
    }
    return _exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Arms (or re-arms) the notification for [r]. Past or completed reminders
  /// are skipped; an existing schedule for the same id is replaced.
  Future<void> schedule(Reminder r) async {
    if (!_supported) return;
    if (!AppSettings.instance.notifications.value ||
        r.completed ||
        !r.date.isAfter(DateTime.now())) {
      await cancel(r.id);
      return;
    }
    try {
      await PushService.instance.localReady;
      _ensureTz();
      // TZDateTime.from converts the absolute instant; using UTC as the
      // location sidesteps needing the device's IANA zone name entirely.
      final when = tz.TZDateTime.from(r.date.toUtc(), tz.UTC);
      final mode = await _mode();
      try {
        await _zoned(r, when, mode);
      } on PlatformException catch (e) {
        // Permission revoked between the check and the call: degrade to an
        // inexact alarm rather than dropping the reminder.
        if (mode == AndroidScheduleMode.exactAllowWhileIdle &&
            e.code == 'exact_alarms_not_permitted') {
          _exactAllowed = false;
          await _zoned(r, when, AndroidScheduleMode.inexactAllowWhileIdle);
        } else {
          rethrow;
        }
      }
      developer.log('scheduled ${r.id} at ${r.date} ($mode)', name: 'sched');
    } catch (e) {
      developer.log('schedule failed for ${r.id}: $e', name: 'sched');
    }
  }

  Future<void> _zoned(
    Reminder r,
    tz.TZDateTime when,
    AndroidScheduleMode mode,
  ) =>
      _plugin.zonedSchedule(
        id: idFor(r.id),
        scheduledDate: when,
        notificationDetails: PushService.reminderDetails,
        androidScheduleMode: mode,
        title: r.title,
        body: _body(r),
        payload: jsonEncode({'reminder_id': r.id}),
      );

  static String _body(Reminder r) {
    final when = reminderDateTimeLabel(r.date);
    return r.subtitle.isEmpty ? when : '$when · ${r.subtitle}';
  }

  Future<void> cancel(String reminderId) async {
    if (!_supported) return;
    try {
      await PushService.instance.localReady;
      await _plugin.cancel(id: idFor(reminderId));
    } catch (e) {
      developer.log('cancel failed for $reminderId: $e', name: 'sched');
    }
  }

  /// Drops every pending reminder notification (sign-out).
  Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await PushService.instance.localReady;
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      developer.log('cancelAll failed: $e', name: 'sched');
    }
  }

  /// Makes the device's pending schedule match [active] exactly: everything
  /// still in the future is (re)armed, anything no longer active is dropped.
  Future<void> sync(List<Reminder> active) async {
    if (!_supported) return;
    try {
      await PushService.instance.localReady;
      if (!AppSettings.instance.notifications.value) {
        await cancelAll();
        return;
      }
      final wanted = {for (final r in active) idFor(r.id)};
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (!wanted.contains(p.id)) await _plugin.cancel(id: p.id);
      }
      for (final r in active) {
        await schedule(r);
      }
      developer.log('synced ${active.length} reminder(s)', name: 'sched');
    } catch (e) {
      developer.log('sync failed: $e', name: 'sched');
    }
  }
}
