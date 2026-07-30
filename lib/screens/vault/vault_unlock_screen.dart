import 'package:flutter/material.dart';

import '../../state/vault_controller.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vault/password_strength_bar.dart';

/// The vault gate's content when it is locked or not yet set up. Handles both:
///   • First-time SETUP — choose + confirm a master password.
///   • UNLOCK — enter the existing master password.
class VaultLockView extends StatefulWidget {
  const VaultLockView({super.key, required this.isSetup});

  /// True when the user has no vault yet (create a master password).
  final bool isSetup;

  @override
  State<VaultLockView> createState() => _VaultLockViewState();
}

class _VaultLockViewState extends State<VaultLockView> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pwd = _password.text;
    setState(() => _error = null);

    if (widget.isSetup) {
      if (pwd.length < 8) {
        setState(() => _error = 'Use at least 8 characters.');
        return;
      }
      if (pwd != _confirm.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
    } else if (pwd.isEmpty) {
      setState(() => _error = 'Enter your master password.');
      return;
    }

    setState(() => _busy = true);
    if (widget.isSetup) {
      await VaultController.instance.setupMasterPassword(pwd);
    } else {
      final ok = await VaultController.instance.unlock(pwd);
      if (!ok && mounted) {
        setState(() => _error = 'Incorrect master password.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                widget.isSetup ? 'Create your vault' : 'Unlock your vault',
                textAlign: TextAlign.center,
                style: AppText.headline.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.isSetup
                    ? 'Set a master password. It encrypts everything on your '
                        'device — we never see it, so it cannot be recovered.'
                    : 'Enter your master password to decrypt your saved '
                        'passwords.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              _field(
                controller: _password,
                label: widget.isSetup ? 'Master password' : 'Master password',
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onChanged: (_) => setState(() {}),
                onSubmitted: widget.isSetup ? null : (_) => _submit(),
              ),
              if (widget.isSetup) ...[
                const SizedBox(height: AppSpacing.sm),
                PasswordStrengthBar(password: _password.text),
                const SizedBox(height: AppSpacing.md),
                _field(
                  controller: _confirm,
                  label: 'Confirm master password',
                  obscure: _obscure,
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppText.caption.copyWith(color: AppColors.critical),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSizes.button,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(widget.isSetup ? 'Create vault' : 'Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    VoidCallback? onToggleObscure,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    final palette = AppPalette.of(context);
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: AppText.body.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: palette.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide.none,
        ),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: palette.textSecondary,
                ),
              ),
      ),
    );
  }
}
