import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../models/user_profile.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
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

/// The Reminders home — a calm, single-glance answer to "what needs my
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

  @override
  void initState() {
    super.initState();
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
          content: Text(AppLocalizations.of(context)
              .t('reminderAddedToast')
              .replaceAll('{title}', created.title)),
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
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _refresh,
              child: ListenableBuilder(
                listenable: _store,
                builder: (context, _) {
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
                            notificationCount:
                                _store.isLoaded ? _store.summary.dueToday : 0,
                            onSearch: _search,
                            onNotifications: () =>
                                _openScope(RemindersScope.today),
                          ),
                        ),
                      ),
                      if (!_store.isLoaded)
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
                      else if (_store.isEmpty)
                        SliverToBoxAdapter(
                          child: RemindersEmptyState(onCreate: _add),
                        )
                      else
                        SliverToBoxAdapter(child: _content()),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              right: AppSpacing.lg,
              bottom: 96,
              child: _AddFab(onTap: _add),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final priorities = _store.priorities(_filter, limit: 4);
    final sections = <Widget>[
      _summaryGrid(),
      _filterChips(),
      _prioritiesSection(priorities),
      _viewAllRow(),
      const SizedBox(height: 120),
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

  Widget _summaryGrid() {
    final s = _store.summary;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.md),
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
              const SizedBox(width: AppSpacing.xs),
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
          const SizedBox(height: AppSpacing.xs),
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
              const SizedBox(width: AppSpacing.xs),
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
                const Icon(Icons.priority_high_rounded,
                    size: 18, color: AppColors.critical),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.t('todaysPriorities'),
                    style: AppText.title.copyWith(
                      color: AppPalette.of(context).textPrimary,
                    ),
                  ),
                ),
                if (priorities.isNotEmpty)
                  GestureDetector(
                    onTap: () => _openScope(RemindersScope.all),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        l10n.t('viewAll'),
                        style: AppText.label.copyWith(
                          color: AppColors.primaryGreen,
                          fontSize: 13,
                        ),
                      ),
                    ),
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
                    bottom: i == priorities.length - 1 ? 0 : AppSpacing.xs),
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
          AppSpacing.screen, AppSpacing.md, AppSpacing.screen, 0),
      child: Row(
        children: [
          Expanded(
            child: _ViewAllButton(onTap: () => _openScope(RemindersScope.all)),
          ),
          const SizedBox(width: AppSpacing.xs),
          _SquareIconButton(
            icon: Icons.calendar_month_rounded,
            tooltip: AppLocalizations.of(context).t('calendar'),
            onTap: _openCalendar,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CaughtUpNote extends StatelessWidget {
  const _CaughtUpNote();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 30, color: AppColors.primaryGreen),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.t('allCaughtUp'),
            style: AppText.subtitle.copyWith(
                color: palette.textPrimary, fontWeight: FontWeight.w700),
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
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).t('viewAllReminders'),
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded,
                    size: 18, color: palette.textPrimary),
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

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.9,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.36),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
