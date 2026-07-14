import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../services/activity_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// The complete activity history: the real feed (documents, reminders, backups)
/// with category filters, pull-to-refresh and a loading / empty / error flow.
class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

enum _Filter { all, documents, reminders, backups }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.documents => 'Documents',
        _Filter.reminders => 'Reminders',
        _Filter.backups => 'Backups',
      };

  bool matches(ActivityItem a) => switch (this) {
        _Filter.all => true,
        _Filter.documents => a.kind == ActivityKind.document,
        _Filter.reminders => a.kind == ActivityKind.reminder,
        _Filter.backups => a.kind == ActivityKind.backup,
      };
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  List<ActivityItem>? _items;
  bool _error = false;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ActivityService.instance.load(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SettingsScaffold(
      title: 'Activity',
      child: _error
          ? ErrorRetry(onRetry: _load)
          : items == null
              ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4))
              : _content(items),
    );
  }

  Widget _content(List<ActivityItem> all) {
    final filtered = all.where(_filter.matches).toList();
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            children: [
              for (final f in _Filter.values) ...[
                _FilterChip(
                  label: f.label,
                  selected: f == _filter,
                  onTap: () => setState(() => _filter = f),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No activity yet',
                        message: _filter == _Filter.all
                            ? 'Add or scan a document to see it here.'
                            : 'Nothing under ${_filter.label.toLowerCase()} yet.',
                        compact: true,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                        AppSpacing.sm, AppSpacing.screen, AppSpacing.xl),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _HistoryTile(item: filtered[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGreen : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: selected ? AppColors.primaryGreen : palette.border),
        ),
        child: Text(label,
            style: AppText.caption.copyWith(
                color: selected ? Colors.white : palette.textSecondary,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.localizedTitle(AppLocalizations.of(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.subtitle.copyWith(color: palette.textPrimary)),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(item.localizedTime(AppLocalizations.of(context)),
              style: AppText.caption.copyWith(color: palette.textFaint)),
        ],
      ),
    );
  }
}
