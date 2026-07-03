import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/category_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Opens the Create Category sheet and returns the created [DocumentCategory],
/// or null if the user dismissed it. The category is already persisted to
/// [CategoryStore] by the time this resolves.
Future<DocumentCategory?> showCreateCategorySheet(BuildContext context) {
  return showModalBottomSheet<DocumentCategory>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CreateCategorySheet(),
  );
}

/// A premium bottom sheet for creating a custom document category: a name field
/// (validated, de-duplicated), an icon picker and a colour picker. On save it
/// persists to [CategoryStore] and pops with the new category.
class CreateCategorySheet extends StatefulWidget {
  const CreateCategorySheet({super.key});

  @override
  State<CreateCategorySheet> createState() => _CreateCategorySheetState();
}

class _CreateCategorySheetState extends State<CreateCategorySheet> {
  final _controller = TextEditingController();
  String _iconKey = kCategoryIcons.first.key;
  int _colorValue = kCategoryColorValues.first;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name');
      return;
    }
    if (name.length < 2) {
      setState(() => _error = 'Name is too short');
      return;
    }
    if (CategoryStore.instance.exists(name)) {
      setState(() => _error = 'That category already exists');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final created = await CategoryStore.instance.add(
      DocumentCategory(name: name, iconKey: _iconKey, colorValue: _colorValue),
    );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final color = Color(_colorValue);
    // Keep the sheet clear of the keyboard.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.large)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
                AppSpacing.screen, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grabber.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // Header: live preview badge + titles.
                Row(
                  children: [
                    Container(
                      width: AppSizes.iconContainer,
                      height: AppSizes.iconContainer,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Icon(categoryIconFor(_iconKey),
                          color: color, size: 26),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.t('newCategory'),
                              style: AppText.headline.copyWith(
                                  color: palette.textPrimary, fontSize: 19)),
                          const SizedBox(height: 2),
                          Text('Organise your documents your way',
                              style: AppText.caption
                                  .copyWith(color: palette.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // Name field.
                Text('Category Name',
                    style: AppText.subtitle
                        .copyWith(color: palette.textPrimary, fontSize: 13)),
                const SizedBox(height: 7),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _save(),
                  decoration: _decoration(context, 'e.g. Education', color),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 15, color: AppColors.critical),
                      const SizedBox(width: 5),
                      Text(_error!,
                          style: AppText.label
                              .copyWith(color: AppColors.critical)),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                // Icon picker.
                Text('Icon',
                    style: AppText.subtitle
                        .copyWith(color: palette.textPrimary, fontSize: 13)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in kCategoryIcons)
                      _IconSwatch(
                        icon: option.icon,
                        selected: option.key == _iconKey,
                        color: color,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _iconKey = option.key);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // Colour picker.
                Text('Colour',
                    style: AppText.subtitle
                        .copyWith(color: palette.textPrimary, fontSize: 13)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final value in kCategoryColorValues)
                      _ColorSwatch(
                        value: value,
                        selected: value == _colorValue,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _colorValue = value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                // Save button.
                PressableScale(
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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _saving ? null : _save,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(l10n.t('createCategory'),
                                        style: AppText.subtitle.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, String hint, Color accent) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: palette.textFaint),
      filled: true,
      fillColor: palette.surfaceVariant,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(palette.border),
      enabledBorder: border(palette.border),
      focusedBorder: border(accent, 1.6),
    );
  }
}

class _IconSwatch extends StatelessWidget {
  const _IconSwatch({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.16)
                : palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? color : palette.border,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Icon(icon,
              size: 23, color: selected ? color : palette.textSecondary),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = Color(value);
    return PressableScale(
      pressedScale: 0.88,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.textPrimary : Colors.transparent,
              width: 2.4,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}
