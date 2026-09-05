import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note_models.dart';
import '../../services/notes_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/common/ino_loader.dart';

/// A note category's name in the active language.
///
/// The enum itself stays the storage key - only the word shown changes.
String noteCategoryLabel(AppLocalizations l10n, NoteCategory c) => switch (c) {
      NoteCategory.personal => l10n.t('noteCatPersonal'),
      NoteCategory.financial => l10n.t('noteCatFinancial'),
      NoteCategory.tax => l10n.t('tax'),
      NoteCategory.property => l10n.t('property'),
      NoteCategory.health => l10n.t('health'),
      NoteCategory.insurance => l10n.t('insurance'),
      NoteCategory.banking => l10n.t('noteCatBanking'),
      NoteCategory.investments => l10n.t('investments'),
      NoteCategory.business => l10n.t('catBusiness'),
      NoteCategory.other => l10n.t('catOther'),
    };

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
    final l10n = AppLocalizations.of(context);
    // The title is optional. When it's blank the note takes its first line of
    // body text as a heading (that is what the user actually typed), and falls
    // back to "Untitled" for a note with no text at all - so a saved note is
    // never a blank row in the list.
    var title = _title.text.trim();
    if (title.isEmpty) {
      final firstLine = _description.text
          .trim()
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      title = firstLine.length > 60
          ? '${firstLine.substring(0, 60).trimRight()}…'
          : firstLine;
      if (title.isEmpty) title = l10n.t('untitled');
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
        _toast(existing == null
            ? l10n.t('noteSaved')
            : l10n.t('noteChangesSaved'));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        _toast(l10n.t('noteSaveFailed'), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.isDark ? palette.surface : Colors.white,
        title: Text(l10n.t('deleteNoteTitle'),
            style: TextStyle(color: palette.textPrimary)),
        content: Text(
            l10n
                .t('deleteNoteBody')
                .replaceAll('{name}', widget.existing!.title),
            style: TextStyle(color: palette.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.t('cancel'),
                  style: TextStyle(color: palette.textSecondary))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.t('delete'),
                  style: const TextStyle(color: AppColors.critical))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.remove(widget.existing!.id);
      if (mounted) {
        _toast(l10n.t('noteDeleted'));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        _toast(l10n.t('noteDeleteFailed'), error: true);
      }
    }
  }

  Future<void> _pickCategory() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final sheetBg = palette.isDark ? palette.surface : Colors.white;
    final picked = await showModalBottomSheet<NoteCategory>(
      context: context,
      backgroundColor: sheetBg,
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
            Text(l10n.t('category'),
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
                          color: palette.isDark
                              ? palette.surfaceVariant
                              : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: Border.all(color: palette.border),
                        ),
                        child: Icon(c.icon,
                            color: AppColors.primaryGreen, size: 21),
                      ),
                      title: Text(noteCategoryLabel(l10n, c),
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary)),
                      trailing: c == _category
                          ? Icon(Icons.check_circle_rounded,
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
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: _isEditing ? l10n.t('editNote') : l10n.t('newNote'),
      actions: [
        IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _isFavorite = !_isFavorite);
          },
          tooltip: l10n.t('favorite'),
          icon: Icon(
            _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: _isFavorite ? AppColors.warning : palette.textPrimary,
          ),
        ),
        IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _isPinned = !_isPinned);
          },
          tooltip: l10n.t('pin'),
          icon: Icon(
            _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            color: _isPinned ? AppColors.primaryGreen : palette.textPrimary,
          ),
        ),
        if (_isEditing)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: palette.textPrimary),
            color: palette.isDark ? palette.surface : Colors.white,
            surfaceTintColor: Colors.transparent,
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
                child: Text(
                  _isArchived ? l10n.t('unarchive') : l10n.t('archive'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(l10n.t('delete'),
                    style: const TextStyle(color: AppColors.critical)),
              ),
            ],
          ),
      ],
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
                  AppSpacing.screen, AppSpacing.xl),
              children: [
                SettingsCard(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(l10n.t('category')),
                      const SizedBox(height: AppSpacing.xs),
                      _CategoryChip(category: _category, onTap: _pickCategory),
                      const SizedBox(height: AppSpacing.md),
                      // The title used to be an unlabelled headline field at
                      // the very top, which read as part of the note itself -
                      // people couldn't tell where the title was. It now sits
                      // under its own label, and is optional.
                      _FieldLabel(l10n.t('reminderTitle'), optional: true),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _title,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        maxLength: 80,
                        style: AppText.headline
                            .copyWith(color: palette.textPrimary, fontSize: 20),
                        decoration: InputDecoration(
                          hintText: l10n.t('noteTitleHint'),
                          hintStyle: AppText.body
                              .copyWith(color: palette.textFaint),
                          filled: false,
                          isDense: true,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md, vertical: 14),
                          border: _fieldBorder(palette.border),
                          enabledBorder: _fieldBorder(palette.border),
                          focusedBorder: _fieldBorder(
                              AppColors.primaryGreen, width: 1.4),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _FieldLabel(l10n.t('notes')),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _description,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: null,
                        minLines: 8,
                        style: AppText.body
                            .copyWith(color: palette.textPrimary, height: 1.5),
                        decoration: InputDecoration(
                          hintText: l10n.t('writeYourNote'),
                          hintStyle:
                              AppText.body.copyWith(color: palette.textFaint),
                          filled: false,
                          isDense: true,
                          // Keep text inset from the outline so it doesn't
                          // sit flush against the border while typing.
                          contentPadding: const EdgeInsets.all(AppSpacing.md),
                          border: _fieldBorder(palette.border),
                          enabledBorder: _fieldBorder(palette.border),
                          focusedBorder: _fieldBorder(
                              AppColors.primaryGreen, width: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SettingsCard(
                  child: Row(
                    children: [
                      Icon(Icons.label_outline_rounded,
                          size: 18, color: palette.textFaint),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _tags,
                          style:
                              AppText.body.copyWith(color: palette.textPrimary),
                          decoration: _borderlessFieldDecoration(
                            hintText: l10n.t('tagsCommaSeparated'),
                            hintStyle: AppText.body
                                .copyWith(color: palette.textFaint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _saveBar(palette, l10n),
        ],
      ),
    );
  }

  /// Clears the app-wide outlined InputDecorationTheme so title/tags stay
  /// flush inside the card without a nested focus ring.
  InputDecoration _borderlessFieldDecoration({
    required String hintText,
    required TextStyle hintStyle,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _saveBar(AppPalette palette, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: palette.isDark ? palette.bg : Colors.white.withValues(alpha: 0.92),
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
                      ? const InoLoader(size: 22, color: Colors.white)
                      : Text(
                          _isEditing
                              ? l10n.t('saveChanges')
                              : l10n.t('saveNote'),
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

/// Rounded field outline shared by the title and body inputs.
OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      borderSide: BorderSide(color: color, width: width),
    );

/// Small caption above a field, with an "Optional" hint where it applies.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(text,
            style: AppText.subtitle
                .copyWith(color: palette.textPrimary, fontSize: 13)),
        if (optional) ...[
          const SizedBox(width: 6),
          Text(AppLocalizations.of(context).t('optional'),
              style:
                  AppText.label.copyWith(color: palette.textFaint, fontSize: 11)),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.onTap});

  final NoteCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.isDark ? palette.surfaceVariant : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 16, color: AppColors.primaryGreen),
              const SizedBox(width: 6),
              Text(
                noteCategoryLabel(AppLocalizations.of(context), category),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
