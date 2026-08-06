import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/password_models.dart';
import '../../services/password_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';

/// Add / edit one saved password.
///
/// The form is deliberately tiny: a NICKNAME - a decoy name the user invents,
/// never the real site or app - and the password itself. Nothing else is
/// asked for, so nothing else can leak. Saving always passes through the
/// consent sheet: the entry is only stored after the user approves it, which
/// is what the `consent` flag on the row records.
class PasswordFormScreen extends StatefulWidget {
  const PasswordFormScreen({super.key, this.existing});

  final PasswordEntry? existing;

  @override
  State<PasswordFormScreen> createState() => _PasswordFormScreenState();
}

class _PasswordFormScreenState extends State<PasswordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = PasswordStore.instance;

  final _nickname = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _nickname.text = e.nickname;
    _password.text = e.password;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _password.dispose();
    super.dispose();
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
    FocusScope.of(context).unfocus();

    // The consent gate. Declining leaves the form exactly as it was - nothing
    // is stored anywhere until this returns true.
    final agreed = await showSaveConsentSheet(context);
    if (agreed != true || !mounted) return;

    setState(() => _saving = true);
    final now = DateTime.now();
    final entry = PasswordEntry(
      id: widget.existing?.id ?? _store.newId('pw'),
      nickname: _nickname.text.trim(),
      password: _password.text,
      consent: true,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    if (_isEdit) {
      await _store.update(entry);
    } else {
      await _store.add(entry);
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (_isEdit) await showSuccessBurst(context, 'Password updated');
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final strength = passwordStrength(_password.text);

    final glass = divineGlassEnabled(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: glass,
        child: SafeArea(
          top: !glass,
          bottom: false,
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                ModuleHeader(
                  title: _isEdit ? 'Edit password' : 'Add password',
                  subtitle: 'A nickname and the password · nothing else',
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 140),
                    children: [
                // ---- Nickname ----
                FadeSlideIn(
                  child: ModuleSection(
                    title: 'Nickname',
                    icon: Icons.badge_rounded,
                    accent: AppColors.primaryGreen,
                    children: [
                      ModuleField(
                        label: 'Type a name by which you can remember this password',
                        controller: _nickname,
                        hint: 'e.g. blue parrot',
                        textCapitalization: TextCapitalization.none,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Give this password a nickname'
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const _NicknameNote(),
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
                        suffix: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
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
                      ),
                      StrengthMeter(strength: strength),
                    ],
                  ),
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
            label: _isEdit ? 'Save changes' : 'Save password',
            busy: _saving,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

/// The standing explanation of why the nickname must be a decoy.
class _NicknameNote extends StatelessWidget {
  const _NicknameNote();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border:
            Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Icon(Icons.tips_and_updates_rounded,
              size: 17, color: AppColors.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Use a random nickname only you understand - not the real app '
              'or site name. "blue parrot" is good; "Instagram" is not.',
              style: AppText.caption.copyWith(
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The consent sheet every save passes through. Returns true only when the
/// user explicitly agrees - dismissing the sheet any other way declines.
Future<bool?> showSaveConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ConsentSheet(),
  );
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
                 Icon(Icons.verified_user_rounded,
                    size: 20, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                Text('Before this password is saved',
                    style: AppText.title.copyWith(color: palette.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your password will be saved with proper security - it is '
              'encrypted on this device with your vault passphrase before it '
              'is stored, so nobody else can read it.\n\n'
              'One check before you agree: make sure you entered a NICKNAME, '
              'not the real name. Saving "Instagram" with password "ramu1243" '
              'links the two together - a random nickname like "blue parrot" '
              'keeps them apart.',
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: PressableScale(
                    pressedScale: 0.97,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          'Go back',
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: 'I understand · save',
                    icon: Icons.check_rounded,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
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
                 Icon(Icons.auto_awesome_rounded,
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
