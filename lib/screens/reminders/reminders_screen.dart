import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/reminder_repository.dart';
import '../../models/dashboard_models.dart' show QuickAction;
import '../../models/reminder_models.dart';
import '../../models/user_profile.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/expandable_fab.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/dashboard/section_header.dart';
import '../../widgets/reminders/completed_reminder_tile.dart';
import '../../widgets/reminders/month_calendar.dart';
import '../../widgets/reminders/reminder_card.dart';
import '../../widgets/reminders/reminder_filter_chips.dart';
import '../../widgets/reminders/reminder_quick_actions.dart';
import '../../widgets/reminders/reminder_summary_card.dart';
import '../../widgets/reminders/reminders_empty_state.dart';
import '../../widgets/reminders/reminders_header.dart';
import '../../widgets/reminders/upcoming_event_tile.dart';

/// The Reminders Dashboard — INO's Life Events & Due Dates command center.
///
/// Answers, at a glance: what's due today, what's coming this week, what's
/// expiring, and which family events are near. Structure: header → 4 summary
/// cards → category filters → today's priorities → upcoming timeline → month
/// calendar → quick actions → recently completed, with an expandable "create"
/// FAB. Data is fully driven by [ReminderRepository].
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late Future<ReminderData> _future;

  DateTime _today = dateOnly(DateTime.now());
  List<Reminder> _reminders = const [];
  List<Reminder> _completed = const [];

  ReminderCategory? _filter;
  late DateTime _calMonth;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _calMonth = DateTime(_today.year, _today.month);
    _selectedDay = _today.day;
    _future = ReminderRepository.instance.load().then((data) {
      _today = data.today;
      _reminders = data.reminders;
      _completed = data.completed;
      _calMonth = DateTime(_today.year, _today.month);
      _selectedDay = _today.day;
      return data;
    });
  }

  Future<void> _refresh() async {
    final data = ReminderRepository.instance.load();
    final loaded = await data;
    if (!mounted) return;
    setState(() {
      _future = data;
      _today = loaded.today;
      _reminders = loaded.reminders;
      _completed = loaded.completed;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  // ---- Derived ------------------------------------------------------------

  List<Reminder> get _filtered => _filter == null
      ? _reminders
      : _reminders.where((r) => r.category == _filter).toList();

  /// Urgent items (this week + overdue) — the Today's Priorities cards. Only
  /// the first three are shown; the rest are behind "View All".
  List<Reminder> get _priorities {
    final list =
        _filtered.where((r) => r.daysFrom(_today) <= 7).toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            if (byDate != 0) return byDate;
            return a.priority.index.compareTo(b.priority.index);
          });
    return list.take(3).toList();
  }

  /// Everything further out — the Upcoming timeline (first four shown).
  List<Reminder> get _upcoming =>
      _filtered.where((r) => r.daysFrom(_today) > 7).take(4).toList();

  ReminderSummary get _summary {
    int days(Reminder r) => r.daysFrom(_today);
    return ReminderSummary(
      dueToday: _reminders.where((r) => days(r) == 0).length,
      upcomingThisWeek:
          _reminders.where((r) => days(r) >= 0 && days(r) <= 7).length,
      expiringSoon: _reminders
          .where((r) =>
              r.category.isExpiryKind && days(r) >= 0 && days(r) <= 30)
          .length,
      completedThisMonth: _completed.length,
    );
  }

  // The calendar reflects the active category filter, so the whole dashboard
  // stays consistent when a filter is applied.
  Set<int> get _markedDays => _filtered
      .where((r) =>
          r.date.year == _calMonth.year && r.date.month == _calMonth.month)
      .map((r) => r.date.day)
      .toSet();

  List<Reminder> get _selectedDayReminders {
    final day = _selectedDay;
    if (day == null) return const [];
    return _filtered
        .where((r) =>
            r.date.year == _calMonth.year &&
            r.date.month == _calMonth.month &&
            r.date.day == day)
        .toList();
  }

  // ---- Mutations ----------------------------------------------------------

  void _complete(Reminder r) {
    setState(() {
      _reminders = _reminders.where((e) => e.id != r.id).toList();
      _completed = [
        r.copyWith(completed: true, completedLabel: 'Just now'),
        ..._completed,
      ];
    });
    HapticFeedback.selectionClick();
    _toast('“${r.title}” marked complete');
  }

  void _shiftMonth(int delta) {
    setState(() {
      _calMonth = DateTime(_calMonth.year, _calMonth.month + delta);
      _selectedDay = null;
    });
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _refresh,
              child: FutureBuilder<ReminderData>(
                future: _future,
                builder: (context, snapshot) {
                  final loaded = snapshot.hasData;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                              AppSpacing.sm, AppSpacing.screen, AppSpacing.md),
                          child: RemindersHeader(
                            fullName: widget.profile.fullName,
                            notificationCount: loaded ? _summary.dueToday : 0,
                            onSearch: () => _toast('Search — coming soon'),
                            onNotifications: () =>
                                _toast('Notifications — coming soon'),
                          ),
                        ),
                      ),
                      if (!loaded)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 60),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                        )
                      else if (_reminders.isEmpty && _completed.isEmpty)
                        SliverToBoxAdapter(
                          child: RemindersEmptyState(
                            onCreate: () => _toast('Create Reminder — coming soon'),
                          ),
                        )
                      else
                        SliverToBoxAdapter(child: _content()),
                    ],
                  );
                },
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                child: ExpandableFab(
                  actions: _reminderFabActions,
                  onAction: (a) => _toast('${a.label} — coming soon'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final sections = <Widget>[
      _summaryGrid(),
      _filterSection(),
      if (_priorities.isNotEmpty) _prioritiesSection(),
      if (_upcoming.isNotEmpty) _upcomingSection(),
      _calendarSection(),
      _quickActionsSection(),
      if (_completed.isNotEmpty) _completedSection(),
      const SizedBox(height: 120),
    ];
    return Column(
      children: [
        for (var i = 0; i < sections.length; i++)
          FadeSlideIn(
            delay: Duration(milliseconds: (i * 60).clamp(0, 360)),
            child: sections[i],
          ),
      ],
    );
  }

  // ---- Sections -----------------------------------------------------------

  Widget _summaryGrid() {
    final s = _summary;
    final cards = [
      ReminderSummaryCard(
        icon: Icons.today_rounded,
        color: AppColors.critical,
        count: s.dueToday,
        label: "Today's Reminders",
      ),
      ReminderSummaryCard(
        icon: Icons.date_range_rounded,
        color: AppColors.lightBlue,
        count: s.upcomingThisWeek,
        label: 'Upcoming This Week',
      ),
      ReminderSummaryCard(
        icon: Icons.hourglass_bottom_rounded,
        color: AppColors.warning,
        count: s.expiringSoon,
        label: 'Expiring Soon',
      ),
      ReminderSummaryCard(
        icon: Icons.check_circle_rounded,
        color: AppColors.primaryGreen,
        count: s.completedThisMonth,
        label: 'Completed This Month',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ReminderFilterChips(
        selected: _filter,
        onSelected: (c) => setState(() => _filter = c),
      ),
    );
  }

  Widget _prioritiesSection() {
    return _Section(
      header: SectionHeader(
        title: "Today's Priorities",
        subtitle: 'What needs your attention',
        icon: Icons.priority_high_rounded,
        iconColor: AppColors.critical,
        actionLabel: 'View All',
        onAction: () => _toast('All priorities — coming soon'),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _priorities.length; i++)
            Padding(
              padding: EdgeInsets.only(
                  bottom: i == _priorities.length - 1 ? 0 : AppSpacing.xs),
              child: ReminderCard(
                reminder: _priorities[i],
                today: _today,
                onTap: () => _toast('${_priorities[i].title} — coming soon'),
                onComplete: () => _complete(_priorities[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _upcomingSection() {
    return _Section(
      header: SectionHeader(
        title: 'Upcoming Events',
        subtitle: 'The weeks ahead',
        icon: Icons.event_note_rounded,
        actionLabel: 'View all',
        onAction: () => _toast('All events — coming soon'),
      ),
      child: InoCard(
        radius: AppRadius.card,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            for (var i = 0; i < _upcoming.length; i++)
              UpcomingEventTile(
                reminder: _upcoming[i],
                today: _today,
                isFirst: i == 0,
                isLast: i == _upcoming.length - 1,
                onTap: () => _toast('${_upcoming[i].title} — coming soon'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _calendarSection() {
    final dayReminders = _selectedDayReminders;
    return _Section(
      header: const SectionHeader(
        title: 'Month View',
        subtitle: 'Tap a date to see its reminders',
        icon: Icons.calendar_month_rounded,
      ),
      child: Column(
        children: [
          MonthCalendar(
            month: _calMonth,
            today: _today,
            markedDays: _markedDays,
            selectedDay: _selectedDay,
            onSelectDay: (d) => setState(() => _selectedDay = d),
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          if (_selectedDay != null) ...[
            const SizedBox(height: AppSpacing.sm),
            if (dayReminders.isEmpty)
              _NoReminderNote(
                label:
                    'No reminders on $_selectedDay ${_monthName(_calMonth.month)}',
              )
            else
              Column(
                children: [
                  for (var i = 0; i < dayReminders.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                          bottom:
                              i == dayReminders.length - 1 ? 0 : AppSpacing.sm),
                      child: ReminderCard(
                        reminder: dayReminders[i],
                        today: _today,
                        onTap: () =>
                            _toast('${dayReminders[i].title} — coming soon'),
                        onComplete: () => _complete(dayReminders[i]),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _quickActionsSection() {
    return _Section(
      header: const SectionHeader(
        title: 'Quick Actions',
        subtitle: 'Create a reminder in one tap',
        icon: Icons.bolt_rounded,
        iconColor: AppColors.lightBlue,
      ),
      fullBleed: true,
      child: ReminderQuickActions(
        onSelect: (label) => _toast('$label reminder — coming soon'),
      ),
    );
  }

  Widget _completedSection() {
    final shown = _completed.take(3).toList();
    return _Section(
      header: SectionHeader(
        title: 'Recently Completed',
        subtitle: 'Nice work',
        icon: Icons.task_alt_rounded,
        iconColor: AppColors.primaryGreen,
        actionLabel: 'View All',
        onAction: () => _toast('All completed — coming soon'),
      ),
      child: InoCard(
        radius: AppRadius.card,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++)
              CompletedReminderTile(
                reminder: shown[i],
                isLast: i == shown.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];
}

/// A titled section: a [SectionHeader] then a body. [fullBleed] children manage
/// their own horizontal padding (e.g. horizontally scrolling rows).
class _Section extends StatelessWidget {
  const _Section({
    required this.header,
    required this.child,
    this.fullBleed = false,
  });

  final Widget header;
  final Widget child;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Tighter vertical rhythm between sections (was AppSpacing.section/28).
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: header,
          ),
          if (fullBleed)
            child
          else
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _NoReminderNote extends StatelessWidget {
  const _NoReminderNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded,
              size: 18, color: palette.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// Reminder-creation FAB actions.
const List<QuickAction> _reminderFabActions = [
  QuickAction(
      label: 'Add Reminder',
      icon: Icons.add_alert_rounded,
      color: AppColors.primaryGreen),
  QuickAction(
      label: 'Add Birthday',
      icon: Icons.cake_rounded,
      color: Color(0xFFF5704A)),
  QuickAction(
      label: 'Add Anniversary',
      icon: Icons.celebration_rounded,
      color: Color(0xFFEC4899)),
  QuickAction(
      label: 'Add Renewal Reminder',
      icon: Icons.autorenew_rounded,
      color: AppColors.lightBlue),
];
