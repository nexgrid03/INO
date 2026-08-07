import 'package:flutter/material.dart';

import '../../models/note_models.dart';
import '../../services/notes_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import 'note_editor_screen.dart';

enum _NotesFilter { all, pinned, favorites, archived }

extension _NotesFilterX on _NotesFilter {
  String get label => switch (this) {
        _NotesFilter.all => 'All',
        _NotesFilter.pinned => 'Pinned',
        _NotesFilter.favorites => 'Favorites',
        _NotesFilter.archived => 'Archived',
      };
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

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
    final base =
        _filter == _NotesFilter.archived ? _store.archived : _store.active;
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
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
                    borderRadius: BorderRadius.circular(AppRadius.pill))),
            const SizedBox(height: AppSpacing.xs),
            _sheetAction(
              icon: note.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              label: note.isPinned ? 'Unpin' : 'Pin',
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
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              onTap: () {
                Navigator.of(context).pop();
                _store.toggleFavorite(note.id);
              },
            ),
            _sheetAction(
              icon: note.isArchived
                  ? Icons.unarchive_rounded
                  : Icons.archive_rounded,
              label: note.isArchived ? 'Unarchive' : 'Archive',
              onTap: () {
                Navigator.of(context).pop();
                _store.toggleArchive(note.id);
              },
            ),
            _sheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              danger: true,
              onTap: () {
                Navigator.of(context).pop();
                _store.remove(note.id).then((_) {
                  if (mounted) _toast('Note deleted');
                }).catchError((Object e) {
                  // The store already rolled the note back - just tell the user.
                  if (mounted) {
                    _toast('Couldn\'t delete the note. Check your connection.',
                        error: true);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
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
      leading: Icon(icon, color: danger ? AppColors.critical : AppColors.primaryGreen),
      title: Text(label, style: AppText.subtitle.copyWith(color: color)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final glass = divineGlassEnabled(context);
    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: ListenableBuilder(
        listenable: _store,
        builder: (context, _) =>
            _store.isEmpty ? const SizedBox.shrink() : _AddButton(onTap: _openEditor),
      ),
      body: InoBackground(
        child: SafeArea(
          top: !glass,
          child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final loading = _store.isLoading && !_store.isLoaded;
              final failed = _store.loadError != null && _store.isEmpty;
              final empty = _store.isEmpty;
              final notes = _visible();
              return Column(
                children: [
                  _header(palette),
                  if (!loading && !failed && !empty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _searchBar(palette),
                    const SizedBox(height: AppSpacing.md),
                    _filterRow(palette),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
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
                                        ? _noMatches(palette)
                                        : _grid
                                            ? _gridView(notes)
                                            : _listView(notes),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(AppPalette palette) {
    final trailing = DivineGlassHeaderAction(
      icon: _grid ? Icons.view_agenda_rounded : Icons.grid_view_rounded,
      tooltip: _grid ? 'List view' : 'Grid view',
      onTap: () => setState(() => _grid = !_grid),
    );

    if (divineGlassEnabled(context)) {
      return DivineGlassAppBar(
        title: 'Notes Vault',
        onBack: () => Navigator.of(context).maybePop(),
        trailing: trailing,
        centerTitle: false,
        includeStatusBar: true,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          InoBackButton(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Notes Vault',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 22,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _searchBar(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.border),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          style: AppText.body.copyWith(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search notes',
            hintStyle: AppText.body.copyWith(color: palette.textFaint),
            prefixIcon: Icon(Icons.search_rounded, color: palette.textFaint),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, color: palette.textFaint),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _filterRow(AppPalette palette) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        children: [
          for (final f in _NotesFilter.values) ...[
            _FilterChip(
              label: f.label,
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  Widget _noMatches(AppPalette palette) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Always scrollable so pull-to-refresh works on the no-results state.
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                _filter == _NotesFilter.archived
                    ? 'No archived notes.'
                    : 'No notes match your search or filter.',
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
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.xl * 3,
      ),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => FadeSlideIn(
        delay: Duration(milliseconds: (i * 30).clamp(0, 240)),
        child: _NoteCard(
          note: notes[i],
          grid: false,
          onTap: () => _openEditor(notes[i]),
          onMore: () => _quickActions(notes[i]),
        ),
      ),
    );
  }

  Widget _gridView(List<Note> notes) {
    return GridView.builder(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.xl * 3,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.72,
      ),
      itemCount: notes.length,
      itemBuilder: (context, i) => FadeSlideIn(
        delay: Duration(milliseconds: (i * 30).clamp(0, 240)),
        child: _NoteCard(
          note: notes[i],
          grid: true,
          onTap: () => _openEditor(notes[i]),
          onMore: () => _quickActions(notes[i]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

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
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryGreen : palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: selected ? AppColors.primaryGreen : palette.border),
          ),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              color: selected ? Colors.white : palette.textSecondary,
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
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(note.category.icon, color: accent, size: grid ? 18 : 20),
              ),
              const Spacer(),
              if (note.isPinned)
                Icon(Icons.push_pin_rounded, size: 14, color: accent),
              if (note.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.star_rounded,
                      size: 14, color: AppColors.warning),
                ),
              GestureDetector(
                onTap: onMore,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.more_horiz_rounded,
                      size: 18, color: palette.textFaint),
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
                    note.title.isEmpty ? 'Untitled' : note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle
                        .copyWith(color: palette.textPrimary, fontSize: 14.5),
                  ),
                  if (note.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        note.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary, height: 1.35),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            Text(
              note.title.isEmpty ? 'Untitled' : note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.subtitle
                  .copyWith(color: palette.textPrimary, fontSize: 15),
            ),
            if (note.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                note.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption
                    .copyWith(color: palette.textSecondary, height: 1.4),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
          ],
          if (grid) const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    note.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!grid) ...[
                const Spacer(),
                Text(
                  _fmtDate(note.updatedAt),
                  style: AppText.label
                      .copyWith(color: palette.textFaint, fontSize: 11),
                ),
              ],
            ],
          ),
          if (grid) ...[
            const SizedBox(height: 4),
            Text(
              _fmtDate(note.updatedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppText.label.copyWith(color: palette.textFaint, fontSize: 11),
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 56, color: palette.textFaint),
                  const SizedBox(height: AppSpacing.md),
                  Text('Couldn\'t load notes',
                      style:
                          AppText.title.copyWith(color: palette.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.body
                        .copyWith(color: palette.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Try Again',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
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
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                border: Border.all(color: AppColors.tealPale),
                boxShadow: AppShadows.card,
              ),
              child:  Icon(Icons.edit_note_rounded,
                  color: AppColors.primaryGreen, size: 52),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No Notes Yet',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Capture reminders, password hints, property and tax notes, '
              'and general records - securely in one place.',
              textAlign: TextAlign.center,
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            PressableScale(
              child: GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: 14),
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
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Add First Note',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
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
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 15),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text('New Note',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
