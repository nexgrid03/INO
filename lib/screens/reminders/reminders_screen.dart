import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../models/user_profile.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shell/ino_bottom_nav.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/reminders/add_reminder_sheet.dart';
import '../../widgets/reminders/reminder_card.dart';
import '../../widgets/reminders/reminder_detail_sheet.dart';
import '../../widgets/reminders/reminder_filter_chips.dart';
import '../../widgets/reminders/reminder_search.dart';
import '../../widgets/reminders/reminder_summary_card.dart';
import '../../widgets/reminders/reminders_empty_state.dart';
import '../../widgets/reminders/reminders_header.dart';
import 'all_reminders_screen.dart';
import 'completed_reminders_screen.dart';
import 'reminder_calendar_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// The Reminders home - a calm, single-glance answer to "what needs my
/// attention right now?".
///
/// Deliberately short: header → a 2×2 summary of tap-through counts → six
/// category filters → **Today's Priorities** (the hero, ≤4 items) → one row to
/// the full list & calendar. Everything secondary (all reminders, calendar,
/// history) lives on its own screen. A single "+" FAB opens the create sheet.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _store = ReminderStore.instance;
  ReminderFilterKind _filter = ReminderFilterKind.all;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    debugPrint('[Reminders] Screen opened');
    _store.ensureLoaded();
  }

  Future<void> _refresh() => _store.reload();

  // ---- Navigation ----------------------------------------------------------

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openScope(RemindersScope scope) =>
      _push(AllRemindersScreen(scope: scope, initialFilter: _filter));

  void _openCompleted() => _push(const CompletedRemindersScreen());

  void _openCalendar() => _push(const ReminderCalendarScreen());

  void _search() => showSearch<void>(
    context: context,
    delegate: ReminderSearchDelegate(AppLocalizations.of(context)),
  );

  Future<void> _add() async {
    final created = await showAddReminderSheet(context);
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).t('reminderAddedToast').replaceAll('{title}', created.title),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    }
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.sm,
                  AppSpacing.screen,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    // The gap only exists when the button can
                    // render (pushed route), so the tab-root
                    // header keeps its original alignment.
                    if (Navigator.of(context).canPop()) ...[
                      const InoBackButton(size: 42),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _store,
                        builder: (context, _) => RemindersHeader(
                          fullName: widget.profile.fullName,
                          email: widget.profile.email,
                          notificationCount: _store.isLoaded
                              ? _store.summary.dueToday
                              : 0,
                          onSearch: _search,
                          onNotifications: () =>
                              _openScope(RemindersScope.today),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primaryGreen,
                  onRefresh: _refresh,
                  child: ListenableBuilder(
                    listenable: _store,
                    builder: (context, _) {
                      final isLoading = !_store.isLoaded || _store.isLoading;
                      final showEmpty = !isLoading && _store.isEmpty && _store.loadError == null;
                      final showDashboard = !isLoading && !_store.isEmpty;
                      final showError = !isLoading && _store.loadError != null && _store.isEmpty;

                      if (showDashboard) {
                        debugPrint('[Reminders] Showing Dashboard');
                      } else if (showEmpty) {
                        debugPrint('[Reminders] Showing Empty State');
                      }

                      return CustomScrollView(
                        slivers: [
                          if (isLoading)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 60),
                                  child: InoLoader(color: AppColors.primaryGreen),
                                ),
                              ),
                            )
                          else if (showError)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _LoadFailed(onRetry: _refresh),
                            )
                          else if (showEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: RemindersEmptyState(onCreate: _add),
                            )
                          else
                            SliverToBoxAdapter(child: _content()),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final priorities = _store.priorities(_filter, limit: 4);
    final sections = <Widget>[
      _weekStrip(),
      _summaryGrid(),
      _filterChips(),
      _prioritiesSection(priorities),
      _viewAllRow(),
      SizedBox(height: InoBottomNav.heightOf(context) + AppSpacing.lg),
    ];
    return Column(
      children: [
        for (var i = 0; i < sections.length; i++)
          FadeSlideIn(
            delay: Duration(milliseconds: (i * 60).clamp(0, 300)),
            child: sections[i],
          ),
      ],
    );
  }

  // ---- Sections ------------------------------------------------------------

  /// Calendar-hub date scroller: the days around today as floating pills, with
  /// category-coloured activity dots and dedicated Anniversary highlights.
  Widget _weekStrip() {
    final activeDay = _selectedDate ?? _store.today;
    final onActiveDay = _store.onDay(activeDay, ReminderFilterKind.all);
    final dayAnniversaries = onActiveDay
        .where((r) => r.category == ReminderCategory.anniversaries)
        .toList();

    // If no anniversary on active day, find any upcoming in the 7-day window
    final weekAnniversaries = dayAnniversaries.isNotEmpty
        ? dayAnniversaries
        : _store.active
            .where((r) =>
                r.category == ReminderCategory.anniversaries &&
                r.daysFrom(_store.today) >= 0 &&
                r.daysFrom(_store.today) <= 7)
            .toList();

    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.t('calendar'),
                  style: AppText.title.copyWith(
                    color: palette.textPrimary,
                    fontSize: 16,
                  ),
                ),
                GestureDetector(
                  onTap: _openCalendar,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Text(
                        'Full Calendar',
                        style: AppText.caption.copyWith(
                          color: palette.isDark
                              ? AppColors.primaryGreen
                              : const Color(0xFF0D5E5E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 15,
                        color: palette.isDark
                            ? AppColors.primaryGreen
                            : const Color(0xFF0D5E5E),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _WeekStrip(
            today: _store.today,
            selectedDay: activeDay,
            onSelectDay: (day) {
              setState(() {
                _selectedDate = (_selectedDate != null &&
                        _selectedDate!.year == day.year &&
                        _selectedDate!.month == day.month &&
                        _selectedDate!.day == day.day)
                    ? null
                    : day;
              });
            },
            dotsFor: (day) {
              final colors = <Color>[];
              for (final r in _store.onDay(day, ReminderFilterKind.all)) {
                final c = r.category.color;
                if (!colors.contains(c)) colors.add(c);
                if (colors.length == 3) break;
              }
              return colors;
            },
            hasAnniversaryFor: (day) => _store
                .onDay(day, ReminderFilterKind.all)
                .any((r) => r.category == ReminderCategory.anniversaries),
          ),
          if (weekAnniversaries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Column(
                children: [
                  for (final ann in weekAnniversaries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: _AnniversaryCalendarCard(
                        reminder: ann,
                        today: _store.today,
                        onTap: () => showReminderDetail(context, ann),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryGrid() {
    final s = _store.summary;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ReminderSummaryCard(
                  icon: Icons.today_rounded,
                  color: AppColors.critical,
                  count: s.dueToday,
                  label: l10n.t('today'),
                  onTap: () => _openScope(RemindersScope.today),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ReminderSummaryCard(
                  icon: Icons.date_range_rounded,
                  color: AppColors.lightBlue,
                  count: s.upcomingThisWeek,
                  label: l10n.t('thisWeek'),
                  onTap: () => _openScope(RemindersScope.week),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ReminderSummaryCard(
                  icon: Icons.hourglass_bottom_rounded,
                  color: AppColors.warning,
                  count: s.expiringSoon,
                  label: l10n.t('expiringSoon'),
                  onTap: () => _openScope(RemindersScope.expiring),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ReminderSummaryCard(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.primaryGreen,
                  count: s.completedThisMonth,
                  label: l10n.t('completed'),
                  onTap: _openCompleted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ReminderFilterChips(
        selected: _filter,
        onSelected: (k) => setState(() => _filter = k),
      ),
    );
  }

  Widget _prioritiesSection(List<Reminder> priorities) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.t('todaysPriorities'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(
                      color: AppPalette.of(context).textPrimary,
                    ),
                  ),
                ),
                if (priorities.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _openScope(RemindersScope.all),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        l10n.t('viewAll'),
                        maxLines: 1,
                        style: AppText.label.copyWith(
                          color: AppPalette.of(context).isDark
                              ? AppColors.primaryGreen
                              : const Color(0xFF0D5E5E),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                _AddIconButton(
                  tooltip: l10n.t('addReminder'),
                  onTap: _add,
                ),
              ],
            ),
          ),
          if (priorities.isEmpty)
            const _CaughtUpNote()
          else
            for (var i = 0; i < priorities.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == priorities.length - 1 ? 0 : AppSpacing.sm,
                ),
                child: ReminderCard(
                  reminder: priorities[i],
                  today: _store.today,
                  onTap: () => showReminderDetail(context, priorities[i]),
                  onComplete: () => _store.complete(priorities[i]),
                ),
              ),
        ],
      ),
    );
  }

  Widget _viewAllRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        0,
      ),
      child: Row(
        children: [
          _SquareIconButton(
            icon: Icons.calendar_month_rounded,
            tooltip: AppLocalizations.of(context).t('calendar'),
            onTap: _openCalendar,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ViewAllButton(onTap: () => _openScope(RemindersScope.all)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Shown when the reminders could not be fetched at all - distinct from "you
/// have none", which used to be the only thing an offline user ever saw.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 52, color: palette.textFaint),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.t('remindersLoadFailed'),
              textAlign: TextAlign.center,
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            PressableScale(
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    l10n.t('tryAgain'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaughtUpNote extends StatelessWidget {
  const _CaughtUpNote();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:  Icon(
              Icons.check_circle_rounded,
              size: 26,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.t('allCaughtUp'),
            style: AppText.subtitle.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.t('nothingThisWeek'),
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Horizontal date scroller from the calendar-hub design: the days around
/// today rendered as floating pills - day-of-week over the day number, with
/// category-coloured activity dots and special anniversary indicators.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.today,
    required this.dotsFor,
    required this.onSelectDay,
    required this.selectedDay,
    required this.hasAnniversaryFor,
  });

  final DateTime today;
  final List<Color> Function(DateTime day) dotsFor;
  final ValueChanged<DateTime> onSelectDay;
  final DateTime selectedDay;
  final bool Function(DateTime day) hasAnniversaryFor;

  static const List<String> _dow = [
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN', //
  ];

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = -2; i <= 6; i++) today.add(Duration(days: i))];
    return SizedBox(
      height: context.horizontalCardHeight(74),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final day = days[index];
          final isToday = day.year == today.year &&
              day.month == today.month &&
              day.day == today.day;
          final isSelected = day.year == selectedDay.year &&
              day.month == selectedDay.month &&
              day.day == selectedDay.day;

          return _DayPill(
            day: day,
            isToday: isToday,
            isSelected: isSelected,
            hasAnniversary: hasAnniversaryFor(day),
            distance: (index - 2).abs(),
            dowLabel: _dow[day.weekday - 1],
            dots: dotsFor(day),
            onTap: () => onSelectDay(day),
          );
        },
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasAnniversary,
    required this.distance,
    required this.dowLabel,
    required this.dots,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool hasAnniversary;
  final int distance;
  final String dowLabel;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final borderColor = isSelected && !isToday
        ? AppColors.primaryGreen
        : hasAnniversary
            ? const Color(0xFF7C6CF0).withValues(alpha: 0.6)
            : palette.border;

    final pill = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 58,
          decoration: BoxDecoration(
            gradient: isToday ? AppColors.brandGradient : null,
            color: isToday
                ? null
                : isSelected
                    ? AppColors.primaryGreen.withValues(alpha: 0.12)
                    : palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.search),
            border: isToday ? null : Border.all(color: borderColor, width: isSelected ? 1.8 : 1.0),
            boxShadow: isToday
                ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.35)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dowLabel,
                style: AppText.label.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: isToday
                      ? Colors.white.withValues(alpha: 0.9)
                      : isSelected
                          ? AppColors.primaryGreen
                          : palette.textFaint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: isToday
                      ? Colors.white
                      : isSelected
                          ? AppColors.primaryGreen
                          : palette.textPrimary,
                ),
              ),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < dots.length; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isToday ? Colors.white : dots[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasAnniversary)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C6CF0), Color(0xFFF472B6)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x337C6CF0),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                size: 8,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );

    return PressableScale(
      pressedScale: 0.93,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: isToday || isSelected ? pill : Opacity(opacity: _fade, child: pill),
      ),
    );
  }

  double get _fade => (1.0 - 0.12 * distance).clamp(0.5, 1.0).toDouble();
}

/// Highlight card showing Anniversary and life milestones with the top calendar.
class _AnniversaryCalendarCard extends StatelessWidget {
  const _AnniversaryCalendarCard({
    required this.reminder,
    required this.today,
    required this.onTap,
  });

  final Reminder reminder;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDueToday = reminder.daysFrom(today) == 0;
    final due = reminder.dueLabel(today);

    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF7C6CF0).withValues(alpha: 0.12),
                const Color(0xFFF472B6).withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: const Color(0xFF7C6CF0).withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C6CF0).withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C6CF0), Color(0xFFF472B6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x407C6CF0),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C6CF0).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ANNIVERSARY',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: const Color(0xFF7C6CF0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          due,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDueToday
                                ? const Color(0xFFE11D48)
                                : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reminder.title,
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: const Color(0xFF7C6CF0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    AppLocalizations.of(context).t('viewAllReminders'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: palette.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.button),
                border: Border.all(color: palette.border),
              ),
              child: Icon(icon, size: 22, color: AppColors.primaryGreen),
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact "add reminder" action that lives in the Today's Priorities
/// header, beside the "View all" link. A small gradient tile with a soft brand
/// glow so it reads as the primary action without the bulk of a floating FAB.
class _AddIconButton extends StatelessWidget {
  const _AddIconButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.88,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                boxShadow: AppShadows.glow(
                  AppColors.primaryGreen,
                  opacity: 0.28,
                ),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
