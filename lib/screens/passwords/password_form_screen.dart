import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/password_models.dart';
import '../../services/password_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';

/// Add / edit one credential.
///
/// The password field is masked by default, can be revealed, and sits above a
/// live strength meter that reacts as it is typed. The generator is one tap
/// away and writes straight into the field.
class PasswordFormScreen extends StatefulWidget {
  const PasswordFormScreen({super.key, this.existing});

  final PasswordEntry? existing;

  @override
  State<PasswordFormScreen> createState() => _PasswordFormScreenState();
}

class _PasswordFormScreenState extends State<PasswordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = PasswordStore.instance;

  final _title = TextEditingController();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _notes = TextEditingController();
  final _tags = TextEditingController();

  PasswordCategory _category = PasswordCategory.other;
  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _title.text = e.title;
    _url.text = e.url ?? '';
    _username.text = e.username ?? '';
    _email.text = e.email ?? '';
    _password.text = e.password;
    _notes.text = e.notes ?? '';
    _tags.text = e.tags.join(', ');
    _category = e.category;
  }

  @override
  void dispose() {
    for (final c in [
      _title, _url, _username, _email, _password, _notes, _tags //
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final i = await showModulePicker(
      context,
      title: 'Category',
      labels: [for (final c in PasswordCategory.values) c.label],
      icons: [for (final c in PasswordCategory.values) c.icon],
      colors: [for (final c in PasswordCategory.values) c.color],
      selectedIndex: PasswordCategory.values.indexOf(_category),
    );
    if (i == null || !mounted) return;
    setState(() => _category = PasswordCategory.values[i]);
  }

  Future<void> _generate() async {
    final generated = await showPasswordGeneratorSheet(context);
    if (generated == null || !mounted) return;
    setState(() {
      _password.text = generated;
      _obscure = false; // show what was just generated, so it can be checked
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    FocusScope.of(context).unfocus();

    final now = DateTime.now();
    final tags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    final entry = PasswordEntry(
      id: widget.existing?.id ?? _store.newId('pw'),
      title: _title.text.trim(),
      password: _password.text,
      category: _category,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      url: orNull(_url),
      username: orNull(_username),
      email: orNull(_email),
      notes: orNull(_notes),
      tags: tags,
      iconKey: widget.existing?.iconKey,
      isFavorite: widget.existing?.isFavorite ?? false,
    );

    if (_isEdit) {
      await _store.update(entry);
    } else {
      await _store.add(entry);
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (_isEdit) await showSuccessBurst(context, 'Credential updated');
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final strength = passwordStrength(_password.text);

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        child: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
              children: [
                ModuleHeader(
                  title: _isEdit ? 'Edit credential' : 'New credential',
                  subtitle: _isEdit ? widget.existing!.title : _category.label,
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Account ----
                FadeSlideIn(
                  child: ModuleSection(
                    title: 'Account',
                    icon: _category.icon,
                    accent: _category.color,
                    children: [
                      ModuleField(
                        label: 'Website or app',
                        controller: _title,
                        hint: 'e.g. Google',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      ModulePickerField(
                        label: 'Category',
                        value: _category.label,
                        icon: _category.icon,
                        accent: _category.color,
                        onTap: _pickCategory,
                      ),
                      ModuleField(
                        label: 'Website URL',
                        controller: _url,
                        hint: 'https://…',
                        keyboardType: TextInputType.url,
                        textCapitalization: TextCapitalization.none,
                      ),
                      ModuleField(
                        label: 'Username',
                        controller: _username,
                        textCapitalization: TextCapitalization.none,
                      ),
                      ModuleField(
                        label: 'Email',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Password ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: ModuleSection(
                    title: 'Password',
                    icon: Icons.key_rounded,
                    accent: AppColors.primaryGreen,
                    trailing: ModuleIconButton(
                      icon: Icons.auto_awesome_rounded,
                      size: 34,
                      tooltip: 'Generate',
                      onTap: _generate,
                    ),
                    children: [
                      ModuleField(
                        label: 'Password',
                        controller: _password,
                        obscure: _obscure,
                        textCapitalization: TextCapitalization.none,
                        validator: (v) =>
                            (v ?? '').isEmpty ? 'Enter a password' : null,
                        onChanged: (_) => setState(() {}),
                        suffix: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              visualDensity: VisualDensity.compact,
                              tooltip: _obscure ? 'Show' : 'Hide',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                size: 19,
                                color: palette.textSecondary,
                              ),
                            ),
                            IconButton(
                              onPressed: _password.text.isEmpty
                                  ? null
                                  : () {
                                      Clipboard.setData(
                                          ClipboardData(text: _password.text));
                                      HapticFeedback.selectionClick();
                                      showModuleToast(context, 'Password copied');
                                    },
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Copy',
                              icon: Icon(Icons.copy_rounded,
                                  size: 18, color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      StrengthMeter(strength: strength),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Extras ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 110),
                  child: ModuleSection(
                    title: 'Tags & notes',
                    icon: Icons.sell_rounded,
                    accent: const Color(0xFF64748B),
                    children: [
                      ModuleField(
                        label: 'Tags',
                        controller: _tags,
                        hint: 'Comma-separated, e.g. personal, 2FA',
                        textCapitalization: TextCapitalization.none,
                      ),
                      ModuleField(
                        label: 'Notes',
                        controller: _notes,
                        hint: 'Recovery codes hint, security questions…',
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: GradientButton(
            label: _isEdit ? 'Save changes' : 'Save credential',
            busy: _saving,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

/// The four-segment strength meter with its verdict label.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({super.key, required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filled = (strength.fraction * 4).round();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                height: 5,
                decoration: BoxDecoration(
                  color: i < filled ? strength.color : palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            if (i < 3) const SizedBox(width: 5),
          ],
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              strength.label,
              textAlign: TextAlign.right,
              style: AppText.label.copyWith(color: strength.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the generator and returns the accepted password, or null on dismiss.
Future<String?> showPasswordGeneratorSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GeneratorSheet(),
  );
}

/// The password generator: length slider, character-class switches and a
/// re-roll. Every change regenerates immediately so the recipe is felt.
class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet();

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  PasswordRecipe _recipe = const PasswordRecipe();
  late String _password = generatePassword(_recipe);

  void _reroll() {
    HapticFeedback.selectionClick();
    setState(() => _password = generatePassword(_recipe));
  }

  void _update(PasswordRecipe recipe) {
    // Never let the user switch every class off - there'd be nothing to draw
    // from, so the last one stays on.
    if (!recipe.isValid) return;
    setState(() {
      _recipe = recipe;
      _password = generatePassword(recipe);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final strength = passwordStrength(_password);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 20, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                Text('Password generator',
                    style: AppText.title.copyWith(color: palette.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // The generated password.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              decoration: BoxDecoration(
                color: palette.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _password,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressableScale(
                    pressedScale: 0.86,
                    child: GestureDetector(
                      onTap: _reroll,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            StrengthMeter(strength: strength),
            const SizedBox(height: AppSpacing.sm),

            // Length.
            Row(
              children: [
                Text('Length',
                    style: AppText.label.copyWith(color: palette.textPrimary)),
                const Spacer(),
                Text('${_recipe.length}',
                    style: AppText.subtitle
                        .copyWith(color: AppColors.primaryGreen)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryGreen,
                thumbColor: AppColors.primaryGreen,
                inactiveTrackColor: palette.border,
                overlayColor: AppColors.primaryGreen.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: _recipe.length.toDouble(),
                min: 8,
                max: 48,
                divisions: 40,
                onChanged: (v) => _update(_recipe.copyWith(length: v.round())),
              ),
            ),

            // Character classes.
            _ClassToggle(
              label: 'Lowercase (a–z)',
              value: _recipe.lowercase,
              onChanged: (v) => _update(_recipe.copyWith(lowercase: v)),
            ),
            _ClassToggle(
              label: 'Uppercase (A–Z)',
              value: _recipe.uppercase,
              onChanged: (v) => _update(_recipe.copyWith(uppercase: v)),
            ),
            _ClassToggle(
              label: 'Numbers (2–9)',
              value: _recipe.digits,
              onChanged: (v) => _update(_recipe.copyWith(digits: v)),
            ),
            _ClassToggle(
              label: 'Symbols (!@#…)',
              value: _recipe.symbols,
              onChanged: (v) => _update(_recipe.copyWith(symbols: v)),
            ),
            const SizedBox(height: 4),
            Text(
              'Look-alike characters (0/O, 1/l/I) are left out so the password '
              'can still be typed by hand.',
              style: AppText.caption
                  .copyWith(color: palette.textFaint, fontSize: 11.5),
            ),
            const SizedBox(height: AppSpacing.md),
            GradientButton(
              label: 'Use this password',
              icon: Icons.check_rounded,
              onTap: () => Navigator.of(context).pop(_password),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassToggle extends StatelessWidget {
  const _ClassToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      activeThumbColor: AppColors.primaryGreen,
      title: Text(label,
          style: AppText.body.copyWith(color: palette.textPrimary)),
    );
  }
}
