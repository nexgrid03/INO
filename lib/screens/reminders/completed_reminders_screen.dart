import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/reminders/completed_reminder_tile.dart';
import '../../widgets/common/ino_loader.dart';

/// The reminder history - everything that's been marked done. A quiet, read-only
/// log kept off the home screen so "what needs attention" stays front and
/// centre. Each item can be restored to the active list.
class CompletedRemindersScreen extends StatefulWidget {
  const CompletedRemindersScreen({super.key});

  @override
  State<CompletedRemindersScreen> createState() =>
      _CompletedRemindersScreenState();
}

class _CompletedRemindersScreenState extends State<CompletedRemindersScreen> {
  final _store = ReminderStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('completed'),
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (!_store.isLoaded) {
            return Center(
              child: InoLoader(color: AppColors.primaryGreen),
            );
          }
          final items = _store.completed;
          if (items.isEmpty) {
            return _Empty(palette: palette);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, AppSpacing.md, AppSpacing.screen, 40),
            children: [
              InoCard(
                radius: AppRadius.card,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Dismissible(
                        key: ValueKey(items[i].id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          final r = items[i];
                          _store.restore(r);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n
                                  .t('reminderRestoredToast')
                                  .replaceAll('{title}', r.title)),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppColors.primaryGreen,
                            ),
                          );
                        },
                        background: _RestoreBackground(palette: palette),
                        child: CompletedReminderTile(
                          reminder: items[i],
                          isLast: i == items.length - 1,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  l10n.t('swipeLeftToRestore'),
                  style: AppText.caption.copyWith(color: palette.textFaint),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RestoreBackground extends StatelessWidget {
  const _RestoreBackground({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.undo_rounded,
              size: 18, color: AppColors.primaryGreen),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).t('restore'),
            style: AppText.label.copyWith(color: AppColors.primaryGreen),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
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
              child: Icon(Icons.task_alt_rounded,
                  size: 32, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(AppLocalizations.of(context).t('nothingCompletedYet'),
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).t('completedRemindersAppearHere'),
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
