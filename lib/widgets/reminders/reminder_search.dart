import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import 'reminder_card.dart';
import 'reminder_detail_sheet.dart';

/// A real, live search over every reminder (active + completed) by title, note
/// or category. Tapping a result opens its detail sheet.
class ReminderSearchDelegate extends SearchDelegate<void> {
  ReminderSearchDelegate(this._l10n)
      : super(searchFieldLabel: _l10n.t('searchReminders'));

  final AppLocalizations _l10n;

  final _store = ReminderStore.instance;

  List<Reminder> _matches() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool hit(Reminder r) =>
        r.title.toLowerCase().contains(q) ||
        r.subtitle.toLowerCase().contains(q) ||
        r.category.label.toLowerCase().contains(q) ||
        r.category.localizedLabel(_l10n).toLowerCase().contains(q);
    return [
      ..._store.active.where(hit),
      ..._store.completed.where(hit),
    ];
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    final palette = AppPalette.of(context);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: palette.textFaint),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _resultsList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _resultsList(context);

  Widget _resultsList(BuildContext context) {
    final palette = AppPalette.of(context);
    final results = _matches();

    if (query.trim().isEmpty) {
      return _Hint(
        icon: Icons.search_rounded,
        text: _l10n.t('searchByTitleNoteCategory'),
        palette: palette,
      );
    }
    if (results.isEmpty) {
      return _Hint(
        icon: Icons.sentiment_dissatisfied_rounded,
        text: _l10n.t('noRemindersMatchQuery').replaceAll('{q}', query),
        palette: palette,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screen),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final r = results[i];
        return Opacity(
          opacity: r.completed ? 0.6 : 1,
          child: ReminderCard(
            reminder: r,
            today: _store.today,
            onTap: () => showReminderDetail(context, r),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.text,
    required this.palette,
  });

  final IconData icon;
  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: palette.textFaint),
            const SizedBox(height: AppSpacing.sm),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
