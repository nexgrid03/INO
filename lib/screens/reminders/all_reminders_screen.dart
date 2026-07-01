import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/reminders/add_reminder_sheet.dart';
import '../../widgets/reminders/reminder_card.dart';
import '../../widgets/reminders/reminder_detail_sheet.dart';
import '../../widgets/reminders/reminder_filter_chips.dart';
import 'reminder_calendar_screen.dart';

/// The full reminders list — everything the compact home screen defers to.
///
/// Reminders are grouped into time buckets (Overdue → Later) and filterable by
/// category. Opened either as the "View All" destination (scope `all`) or
/// deep-linked from a summary card / the bell (a narrower [scope]).
class AllRemindersScreen extends StatefulWidget {
  const AllRemindersScreen({
    super.key,
    this.scope = RemindersScope.all,
    this.initialFilter = ReminderFilterKind.all,
  });

  final RemindersScope scope;
  final ReminderFilterKind initialFilter;

  @override
  State<AllRemindersScreen> createState() => _AllRemindersScreenState();
}

class _AllRemindersScreenState extends State<AllRemindersScreen> {
  final _store = ReminderStore.instance;
  late ReminderFilterKind _filter = widget.initialFilter;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  void _openCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReminderCalendarScreen()),
    );
  }

  Future<void> _add() async {
    final created = await showAddReminderSheet(context);
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('“${created.title}” added'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(widget.scope.title,
            style: AppText.title.copyWith(color: palette.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _openCalendar,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (!_store.isLoaded) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppColors.primaryGreen,
              ),
            );
          }
          final scoped =
              _store.inScope(widget.scope).where(_filter.matches).toList();
          final groups = groupRemindersByTime(scoped, _store.today);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xs),
              ReminderFilterChips(
                selected: _filter,
                onSelected: (k) => setState(() => _filter = k),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: groups.isEmpty
                    ? const _EmptyList()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                            AppSpacing.screen, 120),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          for (final g in groups) ...[
                            _GroupHeader(label: g.label, count: g.items.length),
                            for (final r in g.items)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: AppSpacing.xs),
                                child: ReminderCard(
                                  reminder: r,
                                  today: _store.today,
                                  onTap: () => showReminderDetail(context, r),
                                  onComplete: () => _store.complete(r),
                                ),
                              ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.label.copyWith(
              color: palette.textSecondary,
              fontSize: 12.5,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$count',
              style: AppText.label.copyWith(
                  color: palette.textFaint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 44, color: palette.textFaint),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nothing here',
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'No reminders match this view.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
