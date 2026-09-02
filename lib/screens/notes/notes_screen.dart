import 'package:flutter/material.dart';

import '../../core/responsive/responsive_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../models/note_models.dart';
import '../../services/notes_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/settings_scaffold.dart';
import 'note_editor_screen.dart';
import '../../widgets/common/ino_loader.dart';

enum _NotesFilter { all, pinned, favorites, archived }

extension _NotesFilterX on _NotesFilter {
  String label(AppLocalizations l10n) => switch (this) {
    _NotesFilter.all => l10n.t('all'),
    _NotesFilter.pinned => l10n.t('pinned'),
    _NotesFilter.favorites => l10n.t('favorites'),
    _NotesFilter.archived => l10n.t('archived'),
  };
}

String _fmtDate(DateTime d, AppLocalizations l10n) =>
    '${d.day} ${l10n.monthShort(d.month)} ${d.year}';

/// The Notes Vault - personal notes, reminders, password hints (never actual
/// passwords), property/tax notes and general records. Starts empty; grid or
/// list view; search, pin, favorite and archive.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _store = NotesStore.instance;
  final _searchController = TextEditingController();

  String _query = '';
  bool _grid = true;
  _NotesFilter _filter = _NotesFilter.all;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Note> _visible() {
    final base = _filter == _NotesFilter.archived
        ? _store.archived
        : _store.active;
    return base.where((n) {
      if (_filter == _NotesFilter.pinned && !n.isPinned) return false;
      if (_filter == _NotesFilter.favorites && !n.isFavorite) return false;
      return n.matches(_query);
    }).toList();
  }

  Future<void> _openEditor([Note? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: existing)),
    );
  }

  void _quickActions(Note note) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.isDark ? palette.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _sheetAction(
              icon: note.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              label: note.isPinned ? l10n.t('unpin') : l10n.t('pin'),
              onTap: () {
                Navigator.of(context).pop();
                _store.togglePin(note.id);
              },
            ),
            _sheetAction(
              icon: note.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              label: note.isFavorite
                  ? l10n.t('removeFromFavorites')
                  : l10n.t('addToFavorites'),
              onTap: () {
                Navigator.of(context).pop();
                _store.toggleFavorite(note.id);
              },
            ),
            _sheetAction(
              icon: note.isArchived
                  ? Icons.unarchive_rounded
                  : Icons.archive_rounded,
              label: note.isArchived ? l10n.t('unarchive') : l10n.t('archive'),
              onTap: () {
                Navigator.of(context).pop();
                _store.toggleArchive(note.id);
              },
            ),
            _sheetAction(
              icon: Icons.delete_outline_rounded,
              label: l10n.t('delete'),
              danger: true,
              onTap: () {
                Navigator.of(context).pop();
                _store
                    .remove(note.id)
                    .then((_) {
                      if (mounted) _toast(l10n.t('noteDeleted'));
                    })
                    .catchError((Object e) {
                      if (mounted) {
                        _toast(l10n.t('noteDeleteFailed'), error: true);
                      }
                    });
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
      ),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final palette = AppPalette.of(context);
    final color = danger ? AppColors.critical : palette.textPrimary;
    return ListTile(
      leading: Icon(
        icon,
        color: danger ? AppColors.critical : AppColors.primaryGreen,
      ),
      title: Text(label, style: AppText.subtitle.copyWith(color: color)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('notes'),
      actions: [
        IconButton(
          tooltip: _grid ? l10n.t('listView') : l10n.t('gridView'),
          icon: Icon(
            _grid ? Icons.view_agenda_rounded : Icons.grid_view_rounded,
            color: palette.textPrimary,
          ),
          onPressed: () => setState(() => _grid = !_grid),
        ),
      ],
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final loading = _store.isLoading && !_store.isLoaded;
          final failed = _store.loadError != null && _store.isEmpty;
          final empty = _store.isEmpty;
          final notes = _visible();

          if (loading) {
            return const Center(child: InoLoader());
          }

          return Stack(
            children: [
              Column(
                children: [
                  if (!failed && !empty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screen,
                        AppSpacing.xs,
                        AppSpacing.screen,
                        AppSpacing.sm,
                      ),
                      child: FloatingSearchBar(
                        hint: l10n.t('searchNotes'),
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        trailing: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: l10n.t('clear'),
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: palette.textFaint,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                    ),
                    _filterRow(l10n),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.primaryGreen,
                      onRefresh: _store.reload,
                      child: failed
                          ? _ErrorState(
                              message: _store.loadError!,
                              onRetry: _store.reload,
                            )
                          : empty
                          ? _EmptyState(onAdd: _openEditor)
                          : notes.isEmpty
                          ? _noMatches(palette, l10n)
                          : _grid
                          ? _gridView(notes)
                          : _listView(notes),
                    ),
                  ),
                ],
              ),
              if (!empty)
                Positioned(
                  right: AppSpacing.screen,
                  bottom: AppSpacing.lg,
                  child: SafeArea(child: _AddButton(onTap: _openEditor)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterRow(AppLocalizations l10n) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        children: [
          for (final f in _NotesFilter.values) ...[
            _FilterChip(
              label: f.label(l10n),
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  Widget _noMatches(AppPalette palette, AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                _filter == _NotesFilter.archived
                    ? l10n.t('noArchivedNotes')
                    : l10n.t('noNotesMatch'),
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listView(List<Note> notes) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.xl * 4,
      ),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      // No FadeSlideIn: recycled rows replay the entrance every time they
      // scroll back into view (see the note in profile_screen.dart).
      itemBuilder: (context, i) => _NoteCard(
        key: ValueKey(notes[i].id),
        note: notes[i],
        grid: false,
        onTap: () => _openEditor(notes[i]),
        onMore: () => _quickActions(notes[i]),
      ),
    );
  }

  Widget _gridView(List<Note> notes) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        context.responsivePadding,
        0,
        context.responsivePadding,
        AppSpacing.xl * 4,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.notesGridColumns,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: context.notesGridAspectRatio,
      ),
      itemCount: notes.length,
      itemBuilder: (context, i) => _NoteCard(
        key: ValueKey(notes[i].id),
        note: notes[i],
        grid: true,
        onTap: () => _openEditor(notes[i]),
        onMore: () => _quickActions(notes[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.tealMist
                : (palette.isDark ? palette.surface : Colors.white),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.primaryGreen : palette.border,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              color: selected ? AppColors.primaryGreen : palette.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    super.key,
    required this.note,
    required this.grid,
    required this.onTap,
    required this.onMore,
  });

  final Note note;
  final bool grid;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = note.category.color;
    final iconSize = grid ? 36.0 : AppSizes.iconContainerSm;
    return InoCard(
      radius: AppRadius.card,
      padding: EdgeInsets.all(grid ? AppSpacing.sm + 2 : AppSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: grid ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: palette.isDark
                      ? accent.withValues(alpha: 0.18)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  note.category.icon,
                  color: AppColors.primaryGreen,
                  size: grid ? 18 : 20,
                ),
              ),
              const Spacer(),
              if (note.isPinned)
                Icon(
                  Icons.push_pin_rounded,
                  size: 14,
                  color: AppColors.primaryGreen,
                ),
              if (note.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: AppColors.warning,
                  ),
                ),
              GestureDetector(
                onTap: onMore,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: palette.textFaint,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: grid ? 8 : AppSpacing.sm),
          if (grid)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title.isEmpty ? l10n.t('untitled') : note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 14.5,
                    ),
                  ),
                  if (note.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        note.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: palette.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            Text(
              note.title.isEmpty ? l10n.t('untitled') : note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.subtitle.copyWith(
                color: palette.textPrimary,
                fontSize: 15,
              ),
            ),
            if (note.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                note.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
          ],
          if (grid) const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.isDark
                        ? palette.surfaceVariant
                        : Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    noteCategoryLabel(l10n, note.category),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!grid) ...[
                const Spacer(),
                Text(
                  _fmtDate(note.updatedAt, l10n),
                  style: AppText.label.copyWith(
                    color: palette.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          if (grid) ...[
            const SizedBox(height: 4),
            Text(
              _fmtDate(note.updatedAt, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                color: palette.textFaint,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 56,
                    color: palette.textFaint,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.t('couldntLoadNotes'),
                    style: AppText.title.copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.t('tryAgain'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: palette.isDark ? palette.surfaceVariant : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.large + 8),
                border: Border.all(color: palette.border),
                boxShadow: AppShadows.card,
              ),
              child: Icon(
                Icons.edit_note_rounded,
                color: AppColors.primaryGreen,
                size: 52,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.t('noNotesYet'),
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.t('notesEmptySubtitle'),
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PressableScale(
              child: GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.32),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l10n.t('addFirstNote'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.36),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Text(
                l10n.t('newNote'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
