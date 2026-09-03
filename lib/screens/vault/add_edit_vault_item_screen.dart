import 'package:flutter/material.dart';

import '../../models/vault_item.dart';
import '../../services/password_utils.dart';
import '../../state/vault_controller.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vault/password_strength_bar.dart';
import '../../widgets/common/ino_loader.dart';

/// Create or edit a vault entry. Returns `true` via [Navigator.pop] when a
/// change was saved.
class AddEditVaultItemScreen extends StatefulWidget {
  const AddEditVaultItemScreen({super.key, this.existing});

  final VaultItem? existing;

  bool get isEdit => existing != null;

  @override
  State<AddEditVaultItemScreen> createState() => _AddEditVaultItemScreenState();
}

class _AddEditVaultItemScreenState extends State<AddEditVaultItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;

  late VaultCategory _category;
  late bool _favorite;
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController(text: e?.password ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? VaultCategory.other;
    _favorite = e?.favorite ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final controller = VaultController.instance;
      if (widget.isEdit) {
        await controller.updateItem(
          widget.existing!,
          title: _title.text,
          username: _username.text.trim(),
          password: _password.text,
          url: _url.text,
          notes: _notes.text,
          category: _category,
          favorite: _favorite,
        );
      } else {
        await controller.addItem(
          title: _title.text,
          username: _username.text.trim(),
          password: _password.text,
          url: _url.text,
          notes: _notes.text,
          category: _category,
          favorite: _favorite,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.critical,
          ),
        );
      }
    }
  }

  void _generate() {
    setState(() {
      _password.text = PasswordUtils.generate();
      _obscure = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit password' : 'Add password'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _text(
                controller: _title,
                label: 'Title',
                hint: 'e.g. Gmail, Netflix',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              _text(
                controller: _username,
                label: 'Username / email',
                hint: 'name@example.com',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              _text(
                controller: _password,
                label: 'Password',
                obscure: _obscure,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Password is required' : null,
                onChanged: (_) => setState(() {}),
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Generate',
                      onPressed: _generate,
                      icon: const Icon(Icons.autorenew_rounded),
                    ),
                    IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              PasswordStrengthBar(password: _password.text),
              const SizedBox(height: AppSpacing.md),
              _text(
                controller: _url,
                label: 'Website (optional)',
                hint: 'https://example.com',
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final uri = Uri.tryParse(v.trim());
                  final ok = uri != null &&
                      (uri.hasScheme
                          ? uri.host.isNotEmpty
                          : v.trim().contains('.'));
                  return ok ? null : 'Enter a valid URL';
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _CategoryPicker(
                selected: _category,
                onChanged: (c) => setState(() => _category = c),
              ),
              const SizedBox(height: AppSpacing.md),
              _text(
                controller: _notes,
                label: 'Notes (optional)',
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                value: _favorite,
                onChanged: (v) => setState(() => _favorite = v),
                activeThumbColor: AppColors.primaryGreen,
                contentPadding: EdgeInsets.zero,
                title: Text('Mark as favorite',
                    style: AppText.body.copyWith(color: palette.textPrimary)),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSizes.button,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const InoLoader(size: 20, color: Colors.white)
                      : Text(widget.isEdit ? 'Save changes' : 'Save password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    int maxLines = 1,
    Widget? suffix,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) {
    final palette = AppPalette.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      validator: validator,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: AppText.body.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: palette.surface,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});

  final VaultCategory selected;
  final ValueChanged<VaultCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: AppText.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: VaultCategory.values.map((c) {
            final active = c == selected;
            return ChoiceChip(
              selected: active,
              onSelected: (_) => onChanged(c),
              avatar: Icon(c.icon,
                  size: 18,
                  color: active ? Colors.white : c.color),
              label: Text(c.label),
              labelStyle: AppText.caption.copyWith(
                color: active ? Colors.white : palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: c.color,
              backgroundColor: palette.surfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              side: BorderSide.none,
            );
          }).toList(),
        ),
      ],
    );
  }
}
