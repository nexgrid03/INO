import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/note_models.dart';
import '../../services/notes_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';

/// Create or edit a single note. Pass [existing] to edit; omit it to create.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.existing});

  final Note? existing;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _store = NotesStore.instance;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();

  late NoteCategory _category;
  late bool _isPinned;
  late bool _isFavorite;
  late bool _isArchived;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title.text = e?.title ?? '';
    _description.text = e?.description ?? '';
    _tags.text = e?.tags.join(', ') ?? '';
    _category = e?.category ?? NoteCategory.personal;
    _isPinned = e?.isPinned ?? false;
    _isFavorite = e?.isFavorite ?? false;
    _isArchived = e?.isArchived ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tags.text.trim().isEmpty
      ? const []
      : _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('Give your note a title', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await _store.add(
          title: title,
          description: _description.text.trim(),
          category: _category,
          tags: _parsedTags,
          isPinned: _isPinned,
          isFavorite: _isFavorite,
        );
      } else {
        await _store.update(existing.copyWith(
          title: title,
          description: _description.text.trim(),
          category: _category,
          tags: _parsedTags,
          isPinned: _isPinned,
          isFavorite: _isFavorite,
          isArchived: _isArchived,
          updatedAt: DateTime.now(),
        ));
      }
      if (mounted) {
        _toast(existing == null ? 'Note saved' : 'Changes saved');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      // Insert/update failed (offline, session expired, …) — keep the editor
      // open with the user's text intact so nothing is lost.
      if (mounted) {
        _toast('Couldn\'t save the note. Check your connection.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Delete note?'),
        content: Text('“${widget.existing!.title}” will be permanently removed.',
            style: TextStyle(color: palette.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.critical))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.remove(widget.existing!.id);
      if (mounted) {
        _toast('Note deleted');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        _toast('Couldn\'t delete the note. Check your connection.',
            error: true);
      }
    }
  }

  Future<void> _pickCategory() async {
    final palette = AppPalette.of(context);
    final picked = await showModalBottomSheet<NoteCategory>(
      context: context,
      backgroundColor: palette.surface,
      isScrollControlled: true,
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
            const SizedBox(height: AppSpacing.sm),
            Text('Category',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs,
                    AppSpacing.md, AppSpacing.md),
                children: [
                  for (final c in NoteCategory.values)
                    ListTile(
                      leading: Container(
                        width: AppSizes.iconContainerSm,
                        height: AppSizes.iconContainerSm,
                        decoration: BoxDecoration(
                          color: c.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Icon(c.icon, color: c.color, size: 21),
                      ),
                      title: Text(c.label,
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary)),
                      trailing: c == _category
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.primaryGreen, size: 22)
                          : null,
                      onTap: () => Navigator.of(context).pop(c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _category = picked);
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(palette),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                    AppSpacing.screen, AppSpacing.xl),
                children: [
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 22),
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: AppText.headline
                          .copyWith(color: palette.textFaint, fontSize: 22),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _CategoryChip(category: _category, onTap: _pickCategory),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _description,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    minLines: 6,
                    style: AppText.body
                        .copyWith(color: palette.textPrimary, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Write your note…',
                      hintStyle: AppText.body.copyWith(color: palette.textFaint),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Icon(Icons.label_outline_rounded,
                          size: 18, color: palette.textFaint),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _tags,
                          decoration: InputDecoration(
                            hintText: 'Tags (comma separated)',
                            hintStyle: AppText.body
                                .copyWith(color: palette.textFaint),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _saveBar(palette),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _isFavorite = !_isFavorite);
            },
            tooltip: 'Favorite',
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _isFavorite ? AppColors.warning : palette.textSecondary,
            ),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _isPinned = !_isPinned);
            },
            tooltip: 'Pin',
            icon: Icon(
              _isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              color: _isPinned ? AppColors.primaryGreen : palette.textSecondary,
            ),
          ),
          if (_isEditing)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
              onSelected: (v) {
                if (v == 'archive') {
                  setState(() => _isArchived = !_isArchived);
                } else if (v == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: 'archive',
                    child: Text(_isArchived ? 'Unarchive' : 'Archive')),
                const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.critical))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _saveBar(AppPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.sm),
          child: PressableScale(
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                height: AppSizes.button,
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
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)))
                      : Text(_isEditing ? 'Save Changes' : 'Save Note',
                          style: AppText.subtitle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.onTap});

  final NoteCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: category.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 16, color: category.color),
              const SizedBox(width: 6),
              Text(category.label,
                  style: TextStyle(
                      color: category.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: category.color),
            ],
          ),
        ),
      ),
    );
  }
}
