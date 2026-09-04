import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/reminders/add_reminder_sheet.dart';
import '../../widgets/reminders/reminder_card.dart';
import '../../widgets/reminders/reminder_detail_sheet.dart';
import '../../widgets/reminders/reminder_filter_chips.dart';
import 'reminder_calendar_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// The full reminders list - everything the compact home screen defers to.
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
          content: Text(AppLocalizations.of(context)
              .t('reminderAddedToast')
              .replaceAll('{title}', created.title)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final glass = divineGlassEnabled(context);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final barTop = topInset > 0 ? topInset + 6 : 18.0;
    final barH = DivineGlassAppBar.barHeight + barTop;

    return Scaffold(
      backgroundColor: palette.bg,
      extendBodyBehindAppBar: glass,
      appBar: DivineGlassAppBar.asPreferredSize(
        context,
        title: widget.scope.localizedTitle(l10n),
        actions: [
          IconButton(
            tooltip: l10n.t('calendar'),
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _openCalendar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: InoBackground(
        sky: glass,
        child: Padding(
          padding: EdgeInsets.only(top: glass ? barH : 0),
          child: SafeArea(
            top: !glass,
            child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              if (!_store.isLoaded) {
                return Center(
                  child: InoLoader(color: AppColors.primaryGreen),
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
                        // Flattened to rows so the list can build lazily. The
                        // previous `ListView(children: [...])` constructed and
                        // laid out a ReminderCard for every reminder the user
                        // has on every rebuild — including the ones far below
                        // the fold, and again on each filter tap.
                        : _ReminderRows(
                            groups: groups,
                            today: _store.today,
                            onOpen: (r) => showReminderDetail(context, r),
                            onComplete: _store.complete,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}

/// One row of the flattened All-Reminders list: either a group header or a
/// single reminder. Flattening is what lets the list virtualise — a grouped
/// `ListView(children: [...])` has to materialise every group and every card up
/// front, however far off-screen they are.
sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.labelKey, this.count);
  final String labelKey;
  final int count;
}

class _CardRow extends _Row {
  const _CardRow(this.reminder);
  final Reminder reminder;
}

/// Trailing gap that closed each group in the original layout.
class _GapRow extends _Row {
  const _GapRow();
}

/// Lazily-built grouped reminder list.
///
/// Renders exactly the same sequence of widgets the eager `ListView` did —
/// header, cards each with an 8px bottom gap, then a 12px gap before the next
/// group — but through a builder, so only the rows near the viewport are ever
/// constructed, laid out or painted.
class _ReminderRows extends StatelessWidget {
  const _ReminderRows({
    required this.groups,
    required this.today,
    required this.onOpen,
    required this.onComplete,
  });

  final List<ReminderGroup> groups;
  final DateTime today;
  final void Function(Reminder) onOpen;
  final void Function(Reminder) onComplete;

  List<_Row> _flatten() {
    final rows = <_Row>[];
    for (final g in groups) {
      rows.add(_HeaderRow(g.labelKey, g.items.length));
      for (final r in g.items) {
        rows.add(_CardRow(r));
      }
      rows.add(const _GapRow());
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _flatten();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, 120),
      // Extra build-ahead so a fast fling doesn't outrun the builder.
      // ignore: deprecated_member_use
      cacheExtent: 600.0,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        switch (row) {
          case _HeaderRow(:final labelKey, :final count):
            return _GroupHeader(labelKey: labelKey, count: count);
          case _GapRow():
            return const SizedBox(height: AppSpacing.sm);
          case _CardRow(:final reminder):
            return Padding(
              key: ValueKey(reminder.id),
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: ReminderCard(
                reminder: reminder,
                today: today,
                onTap: () => onOpen(reminder),
                onComplete: () => onComplete(reminder),
              ),
            );
        }
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.labelKey, required this.count});

  final String labelKey;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).t(labelKey),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: palette.border),
              ),
              child:  Icon(Icons.check_circle_outline_rounded,
                  size: 32, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.t('nothingHere'),
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.t('noRemindersMatchView'),
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
