import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../models/reminder_models.dart';
import 'reminder_repository.dart';

/// A single, notify-on-change source of truth shared across the Reminders
/// screens (main list, All Reminders, Calendar, Completed).
///
/// Holding the reminders here — rather than in each screen's [State] — means a
/// create/complete/delete on any surface is reflected everywhere immediately.
/// It hydrates once from [ReminderRepository] (sample data today) and can be
/// swapped for a Supabase-backed repository without touching a widget.
class ReminderStore extends ChangeNotifier {
  ReminderStore._();

  static final ReminderStore instance = ReminderStore._();

  bool _loading = false;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  DateTime _today = dateOnly(DateTime.now());
  DateTime get today => _today;

  final List<Reminder> _active = [];
  final List<Reminder> _completed = [];

  /// Active (not-yet-done) reminders, ascending by date.
  List<Reminder> get active => List.unmodifiable(_active);

  /// Completed reminders, most-recently-completed first.
  List<Reminder> get completed => List.unmodifiable(_completed);

  bool get isEmpty => _active.isEmpty && _completed.isEmpty;

  /// Loads the data once. Safe to call from every screen's `initState`.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    final data = await ReminderRepository.instance.load();
    _today = data.today;
    _active
      ..clear()
      ..addAll(data.reminders);
    _completed
      ..clear()
      ..addAll(data.completed);
    _sort();
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  /// Pull-to-refresh: re-hydrate from the repository.
  Future<void> reload() async {
    _loaded = false;
    _loading = false;
    await ensureLoaded();
  }

  void _sort() => _active.sort((a, b) => a.date.compareTo(b.date));

  int _days(Reminder r) => r.daysFrom(_today);

  // ---- Derived reads --------------------------------------------------------

  /// Active reminders matching [filter], ascending by date.
  List<Reminder> activeMatching(ReminderFilterKind filter) =>
      _active.where(filter.matches).toList();

  /// The "needs attention this week" set (overdue → 7 days out), capped.
  List<Reminder> priorities(ReminderFilterKind filter, {int limit = 4}) {
    final list = _active.where((r) => filter.matches(r) && _days(r) <= 7).toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.priority.index.compareTo(b.priority.index);
      });
    return list.take(limit).toList();
  }

  /// Reminders due within [scope], grouped into time buckets.
  List<Reminder> inScope(RemindersScope scope) {
    switch (scope) {
      case RemindersScope.all:
        return _active;
      case RemindersScope.today:
        return _active.where((r) => _days(r) <= 0).toList();
      case RemindersScope.week:
        return _active.where((r) => _days(r) >= 0 && _days(r) <= 7).toList();
      case RemindersScope.expiring:
        return _active
            .where((r) =>
                r.category.isExpiryKind && _days(r) >= 0 && _days(r) <= 30)
            .toList();
    }
  }

  ReminderSummary get summary => ReminderSummary(
        dueToday: _active.where((r) => _days(r) == 0).length,
        upcomingThisWeek:
            _active.where((r) => _days(r) >= 0 && _days(r) <= 7).length,
        expiringSoon: _active
            .where((r) =>
                r.category.isExpiryKind && _days(r) >= 0 && _days(r) <= 30)
            .length,
        completedThisMonth: _completed.length,
      );

  Set<int> markedDaysIn(DateTime month, ReminderFilterKind filter) => _active
      .where((r) =>
          filter.matches(r) &&
          r.date.year == month.year &&
          r.date.month == month.month)
      .map((r) => r.date.day)
      .toSet();

  List<Reminder> onDay(DateTime day, ReminderFilterKind filter) => _active
      .where((r) =>
          filter.matches(r) &&
          r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day)
      .toList();

  // ---- Mutations ------------------------------------------------------------

  void complete(Reminder r) {
    final i = _active.indexWhere((e) => e.id == r.id);
    if (i == -1) return;
    _active.removeAt(i);
    _completed.insert(
        0, r.copyWith(completed: true, completedLabel: 'Just now'));
    notifyListeners();
    // Persist (fire-and-forget; UI already updated optimistically).
    unawaited(ReminderRepository.instance.setCompleted(r.id, true).catchError(
        (Object e) {
      debugPrint('Reminder complete failed: $e');
    }));
  }

  void restore(Reminder r) {
    _completed.removeWhere((e) => e.id == r.id);
    _active.add(r.copyWith(completed: false, completedLabel: null));
    _sort();
    notifyListeners();
    unawaited(ReminderRepository.instance.setCompleted(r.id, false).catchError(
        (Object e) {
      debugPrint('Reminder restore failed: $e');
    }));
  }

  void add(Reminder r) {
    // Optimistically show it, then insert to Supabase and swap in the real id.
    _active.add(r);
    _sort();
    notifyListeners();
    unawaited(ReminderRepository.instance.add(r).then((saved) {
      final i = _active.indexWhere((e) => e.id == r.id);
      if (i != -1) {
        _active[i] = saved;
        _sort();
        notifyListeners();
      }
      debugPrint('Reminder saved: ${saved.id}');
    }).catchError((Object e) {
      debugPrint('Reminder save failed: $e');
    }));
  }

  void remove(Reminder r) {
    _active.removeWhere((e) => e.id == r.id);
    _completed.removeWhere((e) => e.id == r.id);
    notifyListeners();
    unawaited(ReminderRepository.instance.remove(r.id).catchError((Object e) {
      debugPrint('Reminder delete failed: $e');
    }));
  }

  /// Drops all in-memory reminders and the load flags, so the next
  /// [ensureLoaded] re-hydrates from scratch for whoever is signed in now.
  ///
  /// MUST be called on sign-out (see [SessionReset]). Without it this
  /// process-wide singleton keeps the previous user's reminders and the
  /// `_loaded` guard makes the next user's [ensureLoaded] a no-op — i.e. the
  /// next account would see the previous account's reminders.
  void clear() {
    _active.clear();
    _completed.clear();
    _loaded = false;
    _loading = false;
    _today = dateOnly(DateTime.now());
    notifyListeners();
  }

  /// Test hook: clears all state so each test hydrates fresh.
  @visibleForTesting
  void reset() => clear();
}

/// Which slice of active reminders a full-list screen shows. Summary cards and
/// the notifications bell deep-link into these.
enum RemindersScope { all, today, week, expiring }

extension RemindersScopeX on RemindersScope {
  String get title {
    switch (this) {
      case RemindersScope.all:
        return 'All Reminders';
      case RemindersScope.today:
        return 'Due Now';
      case RemindersScope.week:
        return 'This Week';
      case RemindersScope.expiring:
        return 'Expiring Soon';
    }
  }

  /// Localized [title].
  String localizedTitle(AppLocalizations l10n) {
    switch (this) {
      case RemindersScope.all:
        return l10n.t('allReminders');
      case RemindersScope.today:
        return l10n.t('dueNow');
      case RemindersScope.week:
        return l10n.t('thisWeek');
      case RemindersScope.expiring:
        return l10n.t('expiringSoon');
    }
  }
}
