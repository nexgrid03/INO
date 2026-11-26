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
      return ok;
    } catch (e) {
      developer.log('exact-alarm permission check failed: $e', name: 'sched');
      return false;
    }
  }

  Future<bool> canExact() async {
    if (!_supported || !Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<AndroidScheduleMode> _mode() async {
    if (!Platform.isAndroid) return AndroidScheduleMode.exactAllowWhileIdle;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await android?.canScheduleExactNotifications() ?? true;
      // Use alarmClock when exact-alarm permission is not yet toggled on by
      // the user: Doze batches `inexactAllowWhileIdle` by 2–5 minutes, while
      // `alarmClock` wakes the device at the exact due minute when allowed.
      return canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.alarmClock;
    } catch (_) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
  }

  /// Arms (or re-arms) the notification for [r]. Past or completed reminders
  /// are skipped; an existing schedule for the same id is replaced.
  ///
  /// [allowCatchUp] is true only when explicitly saving/restoring a reminder
  /// whose picked minute just ticked past; periodic [sync] passes `false` so
  /// reloading or returning to the app never re-rings an already-fired alert.
  Future<void> schedule(Reminder r, {bool allowCatchUp = true}) async {
    if (!_supported) return;
    if (!AppSettings.instance.notifications.value || r.completed) {
      await cancel(r.id);
      return;
    }

    final now = DateTime.now();
    if (r.date.isBefore(now)) {
      if (allowCatchUp && now.difference(r.date) <= const Duration(minutes: 2)) {
        await PushService.instance.showReminderNow(r);
      } else if (!allowCatchUp &&
          now.difference(r.date) > const Duration(minutes: 5)) {
        await cancel(r.id);
      }
      return;
    }

    try {
      await PushService.instance.localReady;
      _ensureTz();
      // TZDateTime.from converts the absolute instant; using UTC as the
      // location sidesteps needing the device's IANA zone name entirely.
      final when = tz.TZDateTime.from(r.date.toUtc(), tz.UTC);
      final mode = await _mode();
      var usedExact = mode == AndroidScheduleMode.exactAllowWhileIdle ||
          mode == AndroidScheduleMode.alarmClock;
      try {
        await _zoned(r, when, mode);
      } on PlatformException catch (e) {
        if (e.code == 'exact_alarms_not_permitted') {
          if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
            try {
              await _zoned(r, when, AndroidScheduleMode.alarmClock);
              usedExact = true;
            } on PlatformException {
              await _zoned(r, when, AndroidScheduleMode.inexactAllowWhileIdle);
              usedExact = false;
            }
          } else if (mode == AndroidScheduleMode.alarmClock) {
            await _zoned(r, when, AndroidScheduleMode.inexactAllowWhileIdle);
            usedExact = false;
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      if (usedExact) {
        await PushService.markReminderExactArmed(r.id, r.date);
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
      await PushService.unmarkReminderScheduled(reminderId);
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
      await PushService.clearReminderTracking();
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
        await schedule(r, allowCatchUp: false);
      }
      developer.log('synced ${active.length} reminder(s)', name: 'sched');
    } catch (e) {
      developer.log('sync failed: $e', name: 'sched');
    }
  }
}
